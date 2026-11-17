"""按关键词批量下载 + 转写 + 汇总（B站全自动；抖音/小红书走链接列表）

用法：
    # B站：关键词搜索，自动取前 N 条
    python 批量平台分析.py bilibili "猫" --count 3 --model small

    # 抖音 / 小红书：没有可用的搜索接口，给链接列表（每行一个）
    python 批量平台分析.py links links.txt --platform douyin --model small
    python 批量平台分析.py links links.txt --platform xhs --model small

产物（out/batch_<时间>_<关键词>/）：
    01_<标题>.md     每条的转写 + 摘要
    01_<标题>.srt    字幕
    汇总.md          所有条目的要点 + 关键词，可直接发给大模型做整体分析
"""

import argparse
import math
import os
import re
import subprocess
import sys
import time
from collections import Counter
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

HERE = Path(__file__).resolve().parent

def load_llm_config():
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


def generate_cross_video_synthesis(target_topic: str, item_summaries: list[dict]) -> str | None:
    """调用 llm_config.txt 中的大模型（如 DeepSeek）对批量视频做横向对比与核心结论提炼"""
    import json
    import urllib.request
    cfg = load_llm_config()
    key = (cfg.get("KEY") or "").strip()
    if not key or not item_summaries:
        return None
    base = (cfg.get("BASE") or "https://api.openai.com/v1").rstrip("/")
    model = cfg.get("MODEL") or "gpt-4o-mini"

    materials = []
    for idx, it in enumerate(item_summaries, 1):
        pts = "\n".join(f"  - {t}" for _, t in it.get("summary", [])[:6])
        kws = "、".join(it.get("kw", []))
        materials.append(f"【视频 {idx}】《{it['title']}》（时长 {it['dur']:.0f}s）\n关键词：{kws}\n核心片段：\n{pts}")

    joined = "\n\n".join(materials)[:22000]
    prompt = (
        f"你是资深内容与行业研究分析师。下面是围绕主题「{target_topic}」批量采集并转写的 {len(item_summaries)} 条视频要点。\n"
        "请用简体中文输出结构化 Markdown 横向对比报告，包含：\n"
        "### 1. 核心共识与高频观点\n"
        "### 2. 各视频独到信息与差异对比\n"
        "### 3. 可直接落地的实操结论 / 选题建议\n\n"
        f"素材如下：\n{joined}"
    )
    payload = json.dumps({
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "temperature": 0.3,
    }).encode("utf-8")
    req = urllib.request.Request(
        f"{base}/chat/completions",
        data=payload,
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
    )
    try:
        log(f"\n[AI 汇总] 正在调用 {model} 生成跨视频横向对比报告 ...")
        with urllib.request.urlopen(req, timeout=180) as resp:
            data = json.loads(resp.read().decode("utf-8"))
        return data["choices"][0]["message"]["content"].strip()
    except Exception as exc:
        log(f"      [warn] 跨视频 AI 汇总调用未成功 ({exc})，保留基础索引。")
        return None

YTDLP = os.environ.get("YTDLP_BIN", "yt-dlp")
COOKIE_ARGS = ["--cookies-from-browser", os.environ.get("COOKIES_BROWSER", "firefox")]


def log(msg):
    print(msg, flush=True)


def run(cmd, timeout=1800):
    return subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8",
                          errors="replace", timeout=timeout)


def ensure_path():
    """把 ffmpeg / yt-dlp / node 的已知安装目录补进 PATH。"""
    import shutil
    cands = [
        Path(os.environ.get("LOCALAPPDATA", "")) / "Programs" / "ffmpeg" / "bin",
        Path(os.environ.get("LOCALAPPDATA", "")) / "Programs" / "yt-dlp",
    ]
    for c in cands:
        if c.exists():
            os.environ["PATH"] = str(c) + os.pathsep + os.environ.get("PATH", "")
    if not shutil.which("ffmpeg"):
        log("[warn] 找不到 ffmpeg，转写会失败")


# ---------------------------------------------------------------- 搜索
def bilibili_search(keyword, count, max_dur=600, retries=3):
    """flat 模式搜索：只发一次搜索请求，快且不容易被 B站风控拖死。"""
    cmd = [YTDLP, *COOKIE_ARGS, "--flat-playlist", "--no-warnings", "--encoding", "utf-8",
           "--print", "%(id)s", f"bilisearch{max(count, 3)}:{keyword}"]
    for attempt in range(1, retries + 1):
        r = run(cmd, timeout=90)
        if r.returncode == 0 and r.stdout.strip():
            items = []
            for line in r.stdout.strip().splitlines():
                vid = line.strip()
                if not vid:
                    continue
                if vid.startswith("http"):
                    url = vid
                elif vid.isdigit():
                    url = f"https://www.bilibili.com/video/av{vid}"
                else:
                    url = f"https://www.bilibili.com/video/{vid}"
                items.append({"url": url, "title": vid, "duration": ""})
            if items:
                return items[:count]
        err_lines = [x for x in (r.stderr or "").strip().splitlines() if x.strip()]
        err_tail = err_lines[-1][:90] if err_lines else "(超时或无输出)"
        log(f"[!] 搜索失败（第 {attempt} 次）：{err_tail}")
        if attempt < retries:
            time.sleep(10 * attempt)
    return []

def read_links(path):
    p = Path(path)
    if not p.exists():
        raise SystemExit(f"链接文件不存在: {p}")
    urls = [x.strip() for x in p.read_text(encoding="utf-8", errors="ignore").splitlines() if x.strip()]
    return [u for u in urls if not u.startswith("#")]


# ---------------------------------------------------------------- 下载
def download_audio(url, outdir, platform):
    """统一产出 16k 单声道 wav。"""
    outdir.mkdir(parents=True, exist_ok=True)
    if platform == "douyin":
        cands = [HERE / "tools" / "douyin.js", HERE.parent / "download" / "douyin.js"]
        node_js = next((p for p in cands if p.exists()), cands[0])
        if node_js.exists():
            r = run(["node", str(node_js), url, str(outdir)], timeout=900)
            if r.returncode == 0:
                mp4s = sorted(outdir.glob("*.mp4"), key=lambda x: x.stat().st_mtime)
                if mp4s:
                    wav = mp4s[-1].with_suffix(".wav")
                    rr = run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(mp4s[-1]),
                              "-vn", "-ac", "1", "-ar", "16000", str(wav)])
                    if rr.returncode == 0:
                        return wav
            err_lines = [x for x in ((r.stderr or "") + (r.stdout or "")).strip().splitlines() if x.strip()]
            reason = "无输出"
            for ln in reversed(err_lines):
                if ln.startswith("失败") or "风控" in ln or "ERROR" in ln:
                    reason = ln
                    break
            log("    [warn] douyin.js 失败(exit=%s)：%s" % (r.returncode, reason[:110]))

    if platform == "xhs":
        # v3.1 新增：小红书不再走 yt-dlp（图文笔记必报 No video formats found），
        # 改调 xhs/xhs.js：视频笔记取 video.mp4 转 wav；图文笔记无音频，优雅跳过。
        node_js = HERE.parent / "xhs" / "xhs.js"
        if not node_js.exists():
            log("    [warn] 找不到 xhs/xhs.js，无法下载小红书视频")
            return None
        before = set(outdir.rglob("video.mp4"))
        r = run(["node", str(node_js), url, str(outdir)], timeout=900)
        if r.returncode != 0:
            err_lines = [x for x in ((r.stderr or "") + (r.stdout or "")).strip().splitlines() if x.strip()]
            reason = "无输出"
            for ln in reversed(err_lines):
                if ln.startswith("失败") or "风控" in ln or "ERROR" in ln:
                    reason = ln
                    break
            log("    [warn] xhs.js 失败(exit=%s)：%s" % (r.returncode, reason[:110]))
            return None
        fresh = sorted(set(outdir.rglob("video.mp4")) - before, key=lambda x: x.stat().st_mtime)
        if not fresh:
            log("    [skip] 该笔记是图文（无视频音频），已跳过")
            return None
        mp4 = fresh[-1]
        wav = mp4.with_suffix(".wav")
        rr = run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(mp4),
                  "-vn", "-ac", "1", "-ar", "16000", str(wav)])
        if rr.returncode == 0:
            return wav
        log("    [warn] ffmpeg 转音频失败")
        return None

    cmd = [YTDLP, *COOKIE_ARGS, "-x", "--audio-format", "wav",
           "--postprocessor-args", "ffmpeg:-ac 1 -ar 16000",
           "-o", str(outdir / "%(id)s.%(ext)s"),
           "--no-playlist", "--no-warnings", "--encoding", "utf-8",
           "--print", "after_move:filepath", "--print", "title", url]
    r = run(cmd, timeout=1800)
    if r.returncode != 0:
        err_lines = [x for x in (r.stderr or "").strip().splitlines() if x.strip()]
        log("      [原因] " + (err_lines[-1][:110] if err_lines else "(无输出)"))
        return None
    wavs = sorted(outdir.glob("*.wav"), key=lambda x: x.stat().st_mtime)
    title = None
    for line in (r.stdout or "").strip().splitlines():
        line = line.strip()
        if line and not Path(line).exists():
            title = line
            break
    return (wavs[-1] if wavs else None), title


# ---------------------------------------------------------------- 转写 & 摘要
def transcribe(wav, model):
    res = model.transcribe(str(wav), language="zh", fp16=False,
                           condition_on_previous_text=False,
                           initial_prompt="以下是普通话视频的转写，请使用简体中文和标准标点符号。")
    try:
        import opencc
        cc = opencc.OpenCC("t2s")
        res["text"] = cc.convert(res.get("text") or "")
        for seg in res.get("segments") or []:
            seg["text"] = cc.convert(seg.get("text") or "")
    except Exception:
        pass
    return res


def tokenize(text):
    text = re.sub(r"\s+", " ", text)
    return re.findall(r"[a-zA-Z][a-zA-Z0-9'-]{1,}", text.lower()) + \
        [a + b for a, b in zip(re.findall(r"[\u4e00-\u9fff]", text), re.findall(r"[\u4e00-\u9fff]", text)[1:])]


def summarize(segments, max_sent=8):
    sents = []
    for seg in segments:
        t = (seg.get("text") or "").strip()
        for piece in re.split(r"(?<=[。！？!?；;])", t):
            piece = piece.strip()
            if len(piece) >= 8:
                sents.append((seg["start"], piece))
    if not sents:
        return [], []
    df = Counter()
    docs = [set(tokenize(s)) for _, s in sents]
    for d in docs:
        df.update(d)
    n = len(sents)
    scored = []
    for i, (start, s) in enumerate(sents):
        toks = tokenize(s)
        if not toks:
            continue
        tf = Counter(toks)
        sc = sum((1 + math.log(tf[w])) * math.log(1 + n / (1 + df[w])) for w in tf) / math.sqrt(len(toks))
        scored.append((sc, i))
    scored.sort(reverse=True)
    keep = max(3, min(max_sent, int(len(sents) * 0.18)))
    picked = sorted(i for _, i in scored[:keep])
    tf_all = Counter()
    for _, s in sents:
        tf_all.update(tokenize(s))
    kw = [w for w, _ in sorted({w: c * math.log(1 + n / (1 + df[w])) for w, c in tf_all.items() if len(w) > 1}.items(),
                               key=lambda x: -x[1])[:12]]
    return [sents[i] for i in picked], kw


def srt_time(sec):
    return f"{int(sec // 3600):02d}:{int(sec % 3600 // 60):02d}:{sec % 60:06.3f}".replace(".", ",")


def save_item(outdir, idx, title, res, asr_time):
    safe = re.sub(r"[^\w\u4e00-\u9fff \-]+", "_", title).strip("_ ")[:50] or f"item{idx}"
    stem = f"{idx:02d}_{safe}"
    segs = res.get("segments") or []
    (outdir / f"{stem}.srt").write_text(
        "\n".join(f"{i}\n{srt_time(s['start'])} --> {srt_time(s['end'])}\n{(s.get('text') or '').strip()}\n"
                  for i, s in enumerate(segs, 1)), encoding="utf-8")
    summary, kw = summarize(segs)
    dur = segs[-1]["end"] if segs else 0
    speed = f"{dur / max(asr_time, 1e-6):.1f}x" if dur > 0 else "—"
    body = [f"# {title}", "",
            f"> 时长 {dur:.0f}s ｜ 转写 {asr_time:.0f}s ｜ 速度 {speed} 实时", ""]
    if not segs:
        body += ["## 未检测到语音", "",
                 "这条音频里没有可识别的人声（纯音乐 / 环境音 / 无人讲话）。", ""]
    if summary:
        body += ["## 要点", ""] + [f"- `{srt_time(s)[:8]}` {t}" for s, t in summary] + [""]
    if kw:
        body += ["**关键词**：" + "、".join(kw), ""]
    body += ["## 全文", ""] + [f"`{srt_time(s['start'])[:8]}` {(s.get('text') or '').strip()}" for s in segs]
    (outdir / f"{stem}.md").write_text("\n".join(body), encoding="utf-8")
    return stem, summary, kw, dur


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["bilibili", "links"])
    ap.add_argument("target", help="bilibili 模式=关键词；links 模式=链接文件路径")
    ap.add_argument("--count", type=int, default=3)
    ap.add_argument("--max-duration", type=int, default=600, help="单条视频最长秒数，默认 600（10 分钟），防止下到几小时的长视频")
    ap.add_argument("--platform", default="douyin", choices=["douyin", "xhs", "bilibili"])
    ap.add_argument("--model", default="small")
    ap.add_argument("--out", default=None)
    ap.add_argument("--no-transcribe", action="store_true", help="只搜/只下，不转写")
    args = ap.parse_args()

    ensure_path()
    ensure = lambda c: time.sleep(c)  # noqa: E731

    if args.mode == "bilibili":
        keyword = args.target
        log(f"[1/4] 搜索 B站：{keyword}（取前 {args.count} 条）")
        items = bilibili_search(keyword, args.count, args.max_duration)
        if not items:
            raise SystemExit(
                "搜索没拿到结果：\n"
                "  - 若提示 412：B站风控，等几分钟再试或换关键词\n"
                "  - 若提示‘时长超过上限’：放宽 --max-duration，或提高 --count"
            )
        for i, it in enumerate(items, 1):
            log(f"      {i}. {it['title'][:40]}  ({it['duration']}s)")
        tag = re.sub(r"[^\w\u4e00-\u9fff]+", "_", keyword)[:20]
    else:
        lines = read_links(args.target)
        items = [{"url": u, "title": Path(u).stem, "duration": ""} for u in lines]
        log(f"[1/4] 读取链接：{len(items)} 条")
        tag = args.platform

    outdir = Path(args.out) if args.out else (HERE / "out" / f"batch_{time.strftime('%m%d_%H%M')}_{tag}")
    outdir.mkdir(parents=True, exist_ok=True)
    log(f"      输出目录：{outdir}")

    model = None
    if not args.no_transcribe:
        import whisper
        log(f"      加载模型 {args.model} ...")
        model = whisper.load_model(args.model, device="cpu")

    rows = []
    for i, it in enumerate(items, 1):
        log(f"\n[{i}/{len(items)}] {it['title'][:50]}")
        log("      下载音频 ...")
        got = download_audio(it["url"], outdir, args.platform if args.mode == "links" else "bilibili")
        wav, real_title = got if isinstance(got, tuple) else (got, None)
        if wav is None:
            log("      [skip] 下载失败")
            continue
        if real_title:
            it["title"] = real_title
            log(f"      标题：{real_title[:60]}")
        if args.no_transcribe:
            rows.append((it["title"], None, [], 0, []))
            continue
        log(f"      转写（{args.model}，CPU）...")
        t0 = time.time()
        res = transcribe(wav, model)
        asr = time.time() - t0
        stem, summary, kw, dur = save_item(outdir, i, it["title"], res, asr)
        speed = f"{dur / max(asr,1e-6):.1f}x" if dur > 0 else "无语音"
        log(f"      完成 {asr:.0f}s（{speed}）-> {stem}.md")
        rows.append((it["title"], stem, kw, dur, summary))

    agg = [f"# 批量分析：{args.target}", "", f"> 平台 {args.platform if args.mode=='links' else 'bilibili'} ｜ 条目 {len(rows)} ｜ 生成 {time.strftime('%Y-%m-%d %H:%M')}", ""]
    synth_inputs = [{"title": t, "kw": k, "dur": d, "summary": s} for t, st, k, d, s in rows if st]
    ai_cross_report = generate_cross_video_synthesis(args.target, synth_inputs)
    if ai_cross_report:
        agg += ["## AI 跨视频横向对比与综合结论", "", ai_cross_report, "", "---", ""]

    for title, stem, kw, dur, _summary in rows:
        if stem:
            agg.append(f"## [{stem.split('_')[0]}] {title}")
            agg.append(f"- 时长 {dur:.0f}s ｜ 文件 `{stem}.md`")
            if kw:
                agg.append(f"- 关键词：{'、'.join(kw)}")
            agg.append("")
    agg.append("---")
    agg.append("把这份文件发给大模型，让它做跨条目的对比与总体结论。")
    (outdir / "汇总.md").write_text("\n".join(agg), encoding="utf-8")

    log(f"\n[完成] {len(rows)} 条")
    log(f"       汇总：{outdir / '汇总.md'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
