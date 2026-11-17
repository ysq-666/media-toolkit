"""视频 → 文字 → 摘要（yt-dlp 下载 + Whisper 转写 + 可选 LLM 总结）

用法：
    python pipeline.py <URL 或 本地音视频文件> [选项]

选项：
    --model tiny|base|small|medium    Whisper 模型，默认 base（CPU 上快）
    --language zh|en|...              强制语言；默认自动识别
    --out DIR                         输出目录，默认 ./out
    --keep-audio                      保留中间音频文件
    --no-llm                          跳过 LLM，只用本地抽取式摘要

环境变量（想用 LLM 总结时设置，任意 OpenAI 兼容服务都行）：
    OPENAI_API_KEY=sk-xxx
    OPENAI_BASE_URL=https://api.openai.com/v1     （可换成中转/本地 Ollama）
    OPENAI_MODEL=gpt-4o-mini

输出（都在输出目录下，以视频标题命名）：
    <title>_全文.md      原文 + 时间轴 + 摘要
    <title>_字幕.srt     SRT 字幕
"""

import argparse
import json
import math
import os
import re
import subprocess
import sys
import time
import urllib.request
from collections import Counter
import shutil
from pathlib import Path

def parse_srt_to_segments(srt_path: Path) -> list[dict]:
    """将下载到的平台原生 SRT 字幕解析为与 Whisper 相同格式的 segments 列表"""
    raw = srt_path.read_text(encoding="utf-8", errors="ignore")
    blocks = re.split(r"\n\s*\n", raw.strip())
    segs = []
    time_re = re.compile(r"(\d{2}):(\d{2}):(\d{2})[,.](\d{3})\s*-->\s*(\d{2}):(\d{2}):(\d{2})[,.](\d{3})")
    for b in blocks:
        lines = [x.strip() for x in b.splitlines() if x.strip()]
        if len(lines) < 2:
            continue
        m = None
        text_start = 1
        for idx, ln in enumerate(lines[:2]):
            m = time_re.search(ln)
            if m:
                text_start = idx + 1
                break
        if not m:
            continue
        g = [int(x) for x in m.groups()]
        start_s = g[0]*3600 + g[1]*60 + g[2] + g[3]/1000.0
        end_s = g[4]*3600 + g[5]*60 + g[6] + g[7]/1000.0
        txt = " ".join(lines[text_start:])
        txt = re.sub(r"<[^>]+>", "", txt).strip()
        if not txt:
            continue
        if segs:
            # v3.1：YouTube 自动字幕常为滚屏双行（新 cue 含上一句残留），只判完全
            # 相等会残留半句重复。处理三种重叠：完全相等跳过；新句以前句为前缀
            # 则合并为新句；旧句以新句为前缀则跳过；词级首尾重叠则去掉新句开头的重叠词。
            prev = segs[-1]
            ptxt = prev["text"]
            if txt == ptxt:
                continue
            if txt.startswith(ptxt):
                prev["text"] = txt
                prev["end"] = end_s
                continue
            if ptxt.startswith(txt):
                continue
            pw, nw = ptxt.split(), txt.split()
            merged = False
            for k in range(min(len(pw), len(nw), 6), 1, -1):
                if pw[-k:] == nw[:k]:
                    # 至少 2 个词首尾重叠：同一句滚屏，拼进上一段并延长结束时间
                    prev["text"] = ptxt + " " + " ".join(nw[k:])
                    prev["end"] = end_s
                    merged = True
                    break
            if merged:
                continue
        segs.append({"start": start_s, "end": end_s, "text": txt})
    return segs


def try_fetch_platform_subtitles(target: str, outdir: Path, cookies=None, browser=None):
    """优先尝试秒抓平台自带字幕（YouTube/B站），若存在则免去长达数分钟的音频下载与 Whisper CPU 转写"""
    if Path(target).exists():
        return None
    log("[1/4] 正在检测平台是否提供现成字幕 (秒级快速通道) ...")
    sub_tmp_dir = outdir / f"_sub_probe_{int(time.time())}"
    sub_tmp_dir.mkdir(parents=True, exist_ok=True)
    auth = []
    if cookies:
        auth = ["--cookies", cookies]
    elif browser:
        auth = ["--cookies-from-browser", browser]
    else:
        auto = auto_browser()
        if auto:
            auth = ["--cookies-from-browser", auto]

    cmd = [
        "yt-dlp", "--skip-download",
        "--write-subs", "--write-auto-subs",
        "--sub-langs", "zh-Hans,zh-CN,zh,zh-Hant,ai-zh,en.*",  # v3.1：补 B站 ai-zh
        "--convert-subs", "srt",
        "-o", str(sub_tmp_dir / "sub.%(ext)s"),
        "--no-playlist", "--no-warnings", "--encoding", "utf-8",
        "--print", "title",
        *auth, target,
    ]
    try:
        r = run(cmd, timeout=45)
        srts = sorted(sub_tmp_dir.glob("*.srt"), key=lambda p: (0 if "zh" in p.name else 1, -p.stat().st_size))
        if srts:
            segs = parse_srt_to_segments(srts[0])
            if len(segs) >= 3:
                title_lines = [x.strip() for x in (r.stdout or "").splitlines() if x.strip()]
                title = title_lines[0] if title_lines else target
                log(f"      [命中原生字幕] 已直接获取 {srts[0].name} ({len(segs)} 条时间轴)，跳过音频下载与 Whisper 转写！")
                shutil.rmtree(sub_tmp_dir, ignore_errors=True)
                full_text = " ".join(s["text"] for s in segs)
                return {
                    "title": title,
                    "result": {"text": full_text, "segments": segs, "language": "zh" if "zh" in srts[0].name else "en"},
                    "asr_time": 0.5,
                }
    except Exception:
        pass
    shutil.rmtree(sub_tmp_dir, ignore_errors=True)
    log("      未检测到可用原生字幕，进入标准「音频下载 + Whisper 转写」流程 ...")
    return None


if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

HERE = Path(__file__).resolve().parent


def simplify_chinese(result):
    """Whisper 对中文常输出繁体；有 opencc 就转成简体（失败则原样返回）。"""
    try:
        import opencc
        cc = opencc.OpenCC("t2s")
    except Exception:
        return result
    try:
        result["text"] = cc.convert(result.get("text") or "")
        for seg in result.get("segments") or []:
            seg["text"] = cc.convert(seg.get("text") or "")
    except Exception:
        pass
    return result

def auto_browser():
    """若本机 Firefox 有 cookie 库，就用它的实时登录态（不受快照过期影响）。"""
    env = (os.environ.get("YTDLP_COOKIES_BROWSER") or "").strip()
    if env:
        return env
    prof = Path(os.environ.get("APPDATA", "")) / "Mozilla" / "Firefox" / "Profiles"
    if prof.exists() and any(p.is_dir() and (p / "cookies.sqlite").exists() for p in prof.iterdir()):
        return "firefox"
    return None

def ensure_ffmpeg():
    """whisper 解码音频要用 ffmpeg；PATH 里没有时自动补上本机装好的目录。"""
    import shutil
    if shutil.which("ffmpeg"):
        return
    for c in (Path(os.environ.get("LOCALAPPDATA", "")) / "Programs" / "ffmpeg" / "bin",
              Path(os.environ.get("ProgramFiles", "")) / "ffmpeg" / "bin"):
        if (c / "ffmpeg.exe").exists():
            os.environ["PATH"] = str(c) + os.pathsep + os.environ.get("PATH", "")
            return


def log(msg):
    print(msg, flush=True)


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace", **kw)


def srt_time(sec):
    h = int(sec // 3600)
    m = int(sec % 3600 // 60)
    s = sec % 60
    return f"{h:02d}:{m:02d}:{s:06.3f}".replace(".", ",")


# ---------------------------------------------------------------- 1. 取音频
def fetch_audio(target, outdir, cookies=None, browser=None):
    """URL 走 yt-dlp，本地文件直接返回。"""
    p = Path(target)
    if p.exists():
        log(f"[1/4] 本地文件: {p}")
        return str(p), p.stem, None

    log("[1/4] 用 yt-dlp 下载音频 ...")

    def build(extra):
        return [
            "yt-dlp", "-x", "--audio-format", "wav",
            "--postprocessor-args", "ffmpeg:-ac 1 -ar 16000",
            "-o", str(outdir / "audio.%(ext)s"),
            "--no-playlist", "--no-warnings", "--encoding", "utf-8",
            "--print", "after_move:filepath", "--print", "title",
            *extra, target,
        ]

    auth = []
    if cookies:
        auth = ["--cookies", cookies]
    elif browser:
        auth = ["--cookies-from-browser", browser]

    r = run(build(auth))
    if r.returncode != 0 and not auth:
        auto = auto_browser()
        err = (r.stderr or "") + (r.stdout or "")
        if auto and ("Sign in to confirm" in err or "not a bot" in err):
            log(f"      需要登录态，自动改用 {auto} 的实时 cookie 重试 ...")
            r = run(build(["--cookies-from-browser", auto]))
    if r.returncode != 0:
        tail = (r.stderr or "").strip().splitlines()[-3:]
        raise SystemExit("yt-dlp 下载失败：\n  " + "\n  ".join(tail) +
                         "\n提示：YouTube 若提示需要登录，请参考 README 的「YouTube 登录」一节。")
    lines = [x.strip() for x in r.stdout.strip().splitlines() if x.strip()]
    # yt-dlp 的输出顺序是：标题在前，最终文件路径在后
    audio_path, title = None, None
    for line in lines:
        if Path(line).exists():
            audio_path = line
        elif title is None:
            title = line
    if not audio_path:
        raise SystemExit("yt-dlp 没返回音频路径")
    title = title or Path(audio_path).stem
    log(f"      音频: {audio_path}")
    log(f"      标题: {title}")
    return audio_path, title, target


# ---------------------------------------------------------------- 2. 转写
def transcribe(audio, model_size, language):
    log(f"[2/4] Whisper 转写中（模型 {model_size}，CPU 模式，首次会下载模型）...")
    import whisper  # 延迟导入，--help 更快

    t0 = time.time()
    model = whisper.load_model(model_size, device="cpu")
    log(f"      模型加载完成 {time.time()-t0:.1f}s")
    t1 = time.time()
    prompt = None
    if language == "zh":
        prompt = "以下是普通话视频的转写，请使用简体中文和标准标点符号。"
    result = model.transcribe(
        audio,
        language=language,
        fp16=False,
        verbose=False,
        condition_on_previous_text=False,
        initial_prompt=prompt,
    )
    dur = time.time() - t1
    segs = result.get("segments") or []
    audio_len = segs[-1]["end"] if segs else 0
    log(f"      转写完成 {dur:.1f}s（音频 {audio_len:.0f}s，速度 {audio_len/max(dur,1e-6):.1f}x 实时）")
    log(f"      识别语言: {result.get('language')}")
    return result, dur


# ---------------------------------------------------------------- 3. 摘要
def tokenize(text):
    """中英混排的粗粒度分词：英文按词，中文按 2-gram。"""
    text = re.sub(r"\s+", " ", text)
    words = re.findall(r"[a-zA-Z][a-zA-Z0-9'-]{1,}", text.lower())
    zh = re.findall(r"[\u4e00-\u9fff]", text)
    bigrams = ["".join(zh[i:i + 2]) for i in range(len(zh) - 1)]
    return words + bigrams


def extractive_summary(segments, ratio=0.18, max_sent=12):
    """不依赖 LLM 的抽取式摘要：TF-IDF 打分选句，按原顺序输出。"""
    sents = []
    for seg in segments:
        t = (seg.get("text") or "").strip()
        if not t:
            continue
        for piece in re.split(r"(?<=[。！？!?；;])|\n", t):
            piece = piece.strip()
            if len(piece) >= 5:
                sents.append((seg["start"], piece))
    if not sents:
        return [], [], []

    df = Counter()
    docs = [set(tokenize(s)) for _, s in sents]
    for d in docs:
        for w in d:
            df[w] += 1
    n = len(sents)
    scores = []
    for i, (start, s) in enumerate(sents):
        toks = tokenize(s)
        if not toks:
            scores.append((0, i)); continue
        tf = Counter(toks)
        score = sum((1 + math.log(tf[w])) * math.log(1 + n / (1 + df[w])) for w in tf)
        scores.append((score / math.sqrt(len(toks)), i))

    scores.sort(reverse=True)
    keep = max(3, min(max_sent, int(len(sents) * ratio)))
    picked = sorted(i for _, i in scores[:keep])
    summary = [(sents[i][0], sents[i][1]) for i in picked]

    # 关键词：全局 TF-IDF 最高的词
    all_tf = Counter()
    for _, s in sents:
        all_tf.update(tokenize(s))
    kw_scores = {w: c * math.log(1 + n / (1 + df[w])) for w, c in all_tf.items() if len(w) > 1}
    keywords = [w for w, _ in sorted(kw_scores.items(), key=lambda x: -x[1])[:15]]
    return summary, keywords, sents


def load_llm_config():
    """优先环境变量，其次同目录 llm_config.txt（KEY=/BASE=/MODEL=）。"""
    cfg = {}
    p = HERE / "llm_config.txt"
    if p.exists():
        for line in p.read_text(encoding="utf-8", errors="ignore").splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            cfg[k.strip().upper()] = v.strip().strip('"').strip("'")
    for env, key in (("OPENAI_API_KEY", "KEY"), ("OPENAI_BASE_URL", "BASE"), ("OPENAI_MODEL", "MODEL")):
        if os.environ.get(env):
            cfg[key] = os.environ[env]
    return cfg


def structured_summary(segments, max_points=8):
    """不依赖大模型的结构化摘要：一句话概括 + 要点 + 关键数字 + 关键词。"""
    sents = []
    for seg in segments:
        t = (seg.get("text") or "").strip()
        for piece in re.split(r"(?<=[。！？!?；;])", t):
            piece = piece.strip(" ,，。")
            if len(piece) >= 5:
                sents.append((seg["start"], piece))
    if not sents:
        return {"overview": "", "points": [], "numbers": [], "keywords": []}

    df = Counter()
    docs = [set(tokenize(s)) for _, s in sents]
    for d in docs:
        df.update(d)
    n = len(sents)
    scored = []
    for i, (_start, s) in enumerate(sents):
        toks = tokenize(s)
        if not toks:
            continue
        tf = Counter(toks)
        sc = sum((1 + math.log(tf[w])) * math.log(1 + n / (1 + df[w])) for w in tf) / math.sqrt(len(toks))
        scored.append((sc, i))
    scored.sort(reverse=True)
    if not scored:
        return {"overview": "", "points": [], "numbers": [], "keywords": []}

    keep = max(3, min(max_points, int(len(sents) * 0.35)))
    picked = sorted(i for _, i in scored[:keep])
    points = []
    for i in picked:
        s = sents[i][1]
        points.append(s if len(s) <= 60 else s[:58] + "…")

    lead_words = ("今天", "本期", "这期", "我们", "介绍", "分享", "讲讲", "总结", "结论")
    lead = [i for i, (_s, t) in enumerate(sents) if t.startswith(lead_words) or any(k in t for k in lead_words)]
    top_i = lead[0] if lead else scored[0][1]
    overview = sents[top_i][1]
    overview = overview if len(overview) <= 45 else overview[:43] + "…"

    nums = []
    for m in re.finditer(r"\d+(?:\.\d+)?\s*(?:%|％|分钟|小时|天|个月|年|次|个|倍|元|GB|MB)", " ".join(s for _, s in sents)):
        frag = m.group(0).replace(" ", "").strip()
        if re.search(r"\d", frag) and len(frag) >= 2 and frag not in nums:
            nums.append(frag)
    nums = nums[:8]

    tf_all = Counter()
    for _, s in sents:
        tf_all.update(tokenize(s))
    STOP = set("的了是在和从到就都也还又而与被把对及或之其所以对于这个那个我们你们他们")
    cand = {w: c * math.log(1 + n / (1 + df[w])) for w, c in tf_all.items()
            if len(w) > 1 and not (w[0] in STOP or w[-1] in STOP)}
    keywords = [w for w, _ in sorted(cand.items(), key=lambda x: -x[1])[:12]]
    return {"overview": overview, "points": points, "numbers": nums, "keywords": keywords}

def llm_summary(title, full_text, segments):
    """有 OPENAI_API_KEY 时用 LLM 生成结构化总结。"""
    cfg = load_llm_config()
    key = (cfg.get("KEY") or "").strip()
    if not key:
        return None
    base = (cfg.get("BASE") or "https://api.openai.com/v1").rstrip("/")
    model = cfg.get("MODEL") or "gpt-4o-mini"

    body_text = full_text[:24000]
    prompt = (
        "你是视频内容分析助手。下面是一段视频的转写文本（可能含识别错误）。\n"
        "请用简体中文输出 Markdown，严格按下面结构：\n"
        "## 一句话概括\n（不超过 40 字）\n"
        "## 主要内容\n（3-6 条要点，每条一句话）\n"
        "## 关键结论 / 可执行信息\n（如果有；没有就写“无”）\n"
        "## 关键词\n（5-8 个，逗号分隔）\n\n"
        f"视频标题：{title}\n\n转写文本：\n{body_text}"
    )
    payload = json.dumps({
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "temperature": 0.3,
    }).encode()
    req = urllib.request.Request(
        f"{base}/chat/completions", data=payload,
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=180) as resp:
            data = json.loads(resp.read().decode())
        return data["choices"][0]["message"]["content"].strip(), model
    except Exception as exc:  # noqa: BLE001
        log(f"      [warn] LLM 调用失败（{type(exc).__name__}: {str(exc)[:120]}），退回本地抽取式摘要")
        return None


# ---------------------------------------------------------------- 4. 输出
def write_outputs(outdir, title, result, segments, local, llm_text, stats):
    safe = re.sub(r"[^\w\u4e00-\u9fff \-]+", "_", title).strip("_ ")[:60] or "video"
    md_path = outdir / f"{safe}_转写.md" if not local and not llm_text else outdir / f"{safe}_全文.md"
    srt_path = outdir / f"{safe}_字幕.srt"

    with open(srt_path, "w", encoding="utf-8") as fh:
        for i, seg in enumerate(segments, 1):
            fh.write(f"{i}\n{srt_time(seg['start'])} --> {srt_time(seg['end'])}\n"
                     f"{(seg.get('text') or '').strip()}\n\n")

    lines = [f"# {title}", ""]
    lines.append(f"> 时长 {stats['audio_len']:.0f}s ｜ 转写耗时 {stats['asr_time']:.0f}s "
                 f"｜ 速度 {stats['speed']:.1f}x 实时 ｜ 模型 {stats['model']} ｜ 语言 {stats['language']}")
    lines.append("")

    if llm_text:
        lines += ["## AI 总结", "", llm_text, ""]
    else:
        lines += ["## 摘要（本地规则生成，未调用大模型）", ""]
        if local.get("overview"):
            lines += [f"**一句话**：{local['overview']}", ""]
        if local.get("points"):
            lines += ["**要点**", ""] + [f"- {p}" for p in local["points"]] + [""]
        if local.get("numbers"):
            lines += ["**关键数字**：" + " ｜ ".join(local["numbers"]), ""]
        if local.get("keywords"):
            lines += ["**关键词**：" + "、".join(local["keywords"]), ""]
        if not (local.get("overview") or local.get("points")):
            lines += ["_（音频里没检测到可总结的语句）_", ""]

    lines += ["## 时间轴", ""]
    bucket, buf = None, []
    for seg in segments:
        b = int(seg["start"] // 60)
        if bucket is None:
            bucket = b
        if b != bucket:
            if buf:
                lines.append(f"- **{bucket:02d}:00** " + " ".join(buf)[:160] + ("…" if len(" ".join(buf)) > 160 else ""))
            bucket, buf = b, []
        buf.append((seg.get("text") or "").strip())
    if buf:
        lines.append(f"- **{bucket:02d}:00** " + " ".join(buf)[:160] + "…")
    lines += ["", "## 全文", ""]
    for seg in segments:
        lines.append(f"`{srt_time(seg['start'])[:8]}` {(seg.get('text') or '').strip()}")
    lines.append("")

    md_path.write_text("\n".join(lines), encoding="utf-8")
    return md_path, srt_path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("target", help="视频 URL 或本地音视频文件")
    ap.add_argument("--model", default="base")
    ap.add_argument("--language", default=None)
    ap.add_argument("--out", default=None)
    ap.add_argument("--keep-audio", action="store_true")
    ap.add_argument("--no-llm", action="store_true")
    ap.add_argument("--no-summary", action="store_true", help="只出转写和字幕，不做任何摘要（交给外部 LLM 处理）")
    ap.add_argument("--cookies", default=None, help="Netscape 格式 cookies 文件（YouTube 要登录时用）")
    ap.add_argument("--cookies-from-browser", default=None, help="直接读浏览器实时 cookie，如 firefox / chrome / edge")
    ap.add_argument("--check-llm", action="store_true", help="只检查大模型配置是否可用，然后退出")
    ap.add_argument("--force-asr", action="store_true", help="强制使用 Whisper 语音转写，不走平台自带字幕快速通道")
    args = ap.parse_args()

    ensure_ffmpeg()

    if args.check_llm:
        cfg = load_llm_config()
        key = cfg.get("KEY") or ""
        base = cfg.get("BASE") or "(默认 api.openai.com)"
        model = cfg.get("MODEL") or "(默认 gpt-4o-mini)"
        masked = (key[:6] + "…" + key[-4:]) if len(key) > 12 else "(未配置)"
        log(f"KEY   : {masked}")
        log(f"BASE  : {base}")
        log(f"MODEL : {model}")
        if not key:
            log("结论：未配置 KEY，摘要会走本地规则模式。")
            return 1
        got = llm_summary("连通性测试", "这是一次连通性测试，请只回复：可用。", [])
        if got:
            log(f"结论：可用 ✅  模型回复：{got[0][:40]}")
            return 0
        log("结论：调用失败 ❌  检查 KEY / BASE / 网络（或余额）")
        return 1

    outdir = Path(args.out) if args.out else (HERE / "out")
    outdir.mkdir(parents=True, exist_ok=True)

    fast_sub = None if args.force_asr else try_fetch_platform_subtitles(args.target, outdir, args.cookies, args.cookies_from_browser)
    if fast_sub:
        audio, title, src = None, fast_sub["title"], None
        result, asr_time = fast_sub["result"], fast_sub["asr_time"]
    else:
        audio, title, src = fetch_audio(args.target, outdir, args.cookies, args.cookies_from_browser)
        result, asr_time = transcribe(audio, args.model, args.language)
    if str(result.get("language") or "").startswith("zh"):
        result = simplify_chinese(result)
    segments = result.get("segments") or []
    full_text = (result.get("text") or "").strip()

    if args.no_summary:
        log("[3/4] 跳过摘要（--no-summary）")
        local, llm_text = {}, None
    else:
        log("[3/4] 生成摘要 ...")
        local = structured_summary(segments)
        llm_text = None
    if not args.no_summary and not args.no_llm:
        got = llm_summary(title, full_text, segments)
        if got:
            llm_text = got[0]
            log(f"      使用 LLM: {got[1]}")
        else:
            log("      未配置 OPENAI_API_KEY，使用本地抽取式摘要")

    audio_len = segments[-1]["end"] if segments else 0
    stats = {
        "audio_len": audio_len, "asr_time": asr_time,
        "speed": audio_len / max(asr_time, 1e-6),
        "model": args.model, "language": result.get("language", "?"),
    }
    md, srt = write_outputs(outdir, title, result, segments, local, llm_text, stats)
    log("[4/4] 完成：")
    log(f"      摘要: {md}")
    log(f"      字幕: {srt}")
    if not args.keep_audio and src is not None:
        try:
            Path(audio).unlink()
        except OSError:
            pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
