# 视频总结工具箱（yt-dlp + Whisper + 可选 LLM）

> 安装日期：2026-11-16　项目：<https://github.com/openai/whisper>
> 引擎：Whisper `20250625` + PyTorch `2.15.0+cpu` + Python 3.12

---

## 0. 装在哪（第三个独立工具箱）

| 项目 | 位置 |
|---|---|
| Whisper 程序（独立 venv，Python 3.12） | `C:\Users\<你的用户名>\AppData\Local\Programs\whisper\venv`（833 MB） |
| 模型缓存 | `%USERPROFILE%\.cache\whisper`（tiny 75 MB / base 145 MB / small 484 MB） |
| 本工具箱 | `<仓库目录>\summarize` |
| 同级目录（互不影响） | `..\download`（下载）、`..\scrape`（网页抓取）、`..\xhs`（小红书图文） |

为什么用 Python 3.12：系统默认是 3.14，**PyTorch 还没有 3.14 的 wheel**；3.12 是现成的、装得上的版本。

---

## 1. 三个工具怎么串起来

```
① yt-dlp          下载视频/音频          （已有）
② Whisper         把音频转成文字          （本次）
③ 摘要             本地抽取式 / LLM 总结   （本次）
   └─ Scrapling    需要时可抓页面上下文（已有，可选）
```

本工具箱里的 `pipeline.py` 一条命令串完 ①②③：

```powershell
# 拖到 视频总结.bat 上，或命令行
& "$env:LOCALAPPDATA\Programs\whisper\venv\Scripts\python.exe" `
  pipeline.py "https://www.youtube.com/watch?v=xxxx" --model small --language zh
```

输出到 `out\`：

- `<标题>_全文.md`：摘要 + 时间轴 + 全文（可直接丢给 AI 再加工）
- `<标题>_字幕.srt`：标准字幕，能拖进播放器/剪辑软件

---

## 2. 模型怎么选（实测数据，本机 i7-8850H / 32 GB / 纯 CPU）

用一段合成的**清晰普通话**（26 秒，含 4 个要点）测：

| 模型 | 大小 | 转写耗时 | 速度 | 准确度 |
|---|---|---|---|---|
| tiny | 75 MB | ~2 s | ~13x 实时 | 差，适合只看大意 |
| base | 145 MB | **3.9 s** | **6.6x 实时** | 一处错（"语音识别"→"语音时别"） |
| small | 484 MB | **12.6 s** | **2.1x 实时** | **全对** |
| medium | 1.5 GB | 未测（预计 4-6x 慢于 small） | — | 更准 |

建议：**中文用 `small`**，英文用 `base` 就够；赶时间用 `base`，要精度用 `small`。

**关键结论：ASR 质量主要由音频决定，不是模型。**
同一套 `base`，对清晰人声能 95%+ 准确；对游戏实录（背景音乐 + 音效 + 人声混在一起）几乎全是乱码。
所以：**要摘要质量，先确保音频里有人在清楚说话**。

---

## 3. 怎么用

### 方式 A：双击 bat

`视频总结.bat` → 粘贴 URL（或把本地视频拖上去）→ 选模型 → 回车。

### 方式 B：命令行

```powershell
$py = "$env:LOCALAPPDATA\Programs\whisper\venv\Scripts\python.exe"
cd "<仓库目录>\summarize"

& $py pipeline.py "https://www.bilibili.com/video/BVxxxx" --model small --language zh
& $py pipeline.py "D:\Videos\lecture.mp4" --model base
& $py pipeline.py "URL" --model small --language zh --out "D:\notes"
```

### 参数

| 参数 | 说明 |
|---|---|
| `--model tiny/base/small/medium` | 默认 base |
| `--language zh/en/...` | 默认自动识别；指定 `zh` 会额外加简体中文提示，减少繁体输出 |
| `--out DIR` | 输出目录，默认 `./out` |
| `--keep-audio` | 保留中间音频 |
| `--no-llm` | 强制只用本地摘要 |
| `--no-summary` | **只出转写 + 字幕**，不做任何摘要（交给外面的大模型来总结） |

### 让 AI 助手（比如我）直接总结，不用配 key

```powershell
& $py pipeline.py "URL" --model small --language zh --no-summary
# 产出 out\<标题>_转写.md
```

然后把这个 md 的内容（或路径）丢给对话里的模型，由它来总结。
好处：不用 API key、不用本地抽取式、总结质量就是大模型本身的质量。
代价：转写文本要进上下文——1 小时视频约 1.5 万字，需要分段喂、分段总结再合并。

### 中文自动转简体

Whisper 对中文常输出**繁体**。脚本已接 `opencc`（t2s）在转写后自动转简体，
未安装 opencc 时自动跳过，不影响主流程：

```powershell
& "$env:LOCALAPPDATA\Programs\whisper\venv\Scripts\python.exe" -m pip install opencc-python-reimplemented
```

### YouTube 要登录怎么办：用 Firefox 的实时 cookie（推荐）

`cookies.txt` 是"快照"，`__Secure-*PSIDTS` 这类轮换令牌几分钟就可能落后 → 403/bot-check。
Firefox 的 cookie 库能被 yt-dlp **实时读取**，没有快照过期问题。

一次性准备：

1. 装 Firefox（160+ 已验证可用）；
2. 在 Firefox 里登录 youtube.com（能看到头像即成功）；
3. 之后加一个参数即可：

```powershell
& $py pipeline.py "URL" --model small --language zh --no-summary --cookies-from-browser firefox
```

**自动兜底**：不写这个参数也行。脚本遇到 `Sign in to confirm you're not a bot` 时，
会自动检测本机 Firefox 并重试一次（打印 `需要登录态，改用 firefox 的实时 cookie 重试`）。
想换浏览器：`--cookies-from-browser chrome|edge`，或用环境变量 `YTDLP_COOKIES_BROWSER=edge`。



---

## 4. 摘要：三种模式（`视频总结.bat` 启动时会选）

| 模式 | 产出 | 需要 key | 说明 |
|---|---|---|---|
| **1 本地规则** | 一句话 + 要点 + 关键数字 + 关键词 | 不需要 | 纯本机、秒出；只是"规则提取"，不懂语义 |
| **2 AI 总结** | 结构化分析（概括/要点/结论/关键词） | 需要 | 配 `llm_config.txt` 后可用，质量最高 |
| **3 只要文字稿** | 纯转写 + 字幕（`_转写.md`） | 不需要 | 把文件发给 AI 助手，由它总结 |

> 早期版本的"摘要"其实是**摘录原句**，看起来跟正文一样 —— 已改成上面的结构化输出。

### 模式 2 怎么配 key（已配好 DeepSeek）

`llm_config.txt` 已创建，内容为 DeepSeek：

```ini
KEY=sk-…（已填）
BASE=https://api.deepseek.com/v1
MODEL=deepseek-chat
```

- 验证是否可用：双击 **`测试AI配置.bat`**（会打印掩码后的 key、接口地址、模型，并发一次真实请求）
- 换服务商：改 `BASE`/`MODEL` 即可（任何 OpenAI 兼容接口；本地 Ollama 填 `http://127.0.0.1:11434/v1`）
- 该文件是**明文**，别外传、别提交到仓库；怀疑泄露就去平台重置 key

### 通用填法

复制 `llm_config.sample.txt` 为 `llm_config.txt`，填三行：

```ini
KEY=sk-你的key
BASE=https://api.openai.com/v1
MODEL=gpt-4o-mini
```

支持任何 OpenAI 兼容接口（官方 / 中转 / 本地 Ollama）。
不填 key 时，选模式 2 会自动退回模式 1，不会报错中断。

## 4b. 摘要原理（旧说明，保留）

### 默认（无需任何账号）：本地抽取式

TF-IDF 选句 + 关键词，纯本地、零成本、秒出。缺点：**只是摘录原句，不会“理解”内容**。

### 进阶（可选）：接 LLM

设好环境变量就行，兼容任何 OpenAI 接口（官方 / 中转 / 本地 Ollama）：

```powershell
$env:OPENAI_API_KEY  = "sk-xxx"
$env:OPENAI_BASE_URL = "https://api.openai.com/v1"     # 中转或本地服务改这里
$env:OPENAI_MODEL    = "gpt-4o-mini"
```

再接上，输出会多一段结构化总结：

```
## 一句话概括
## 主要内容（3-6 条）
## 关键结论 / 可执行信息
## 关键词
```

不设 key 时自动退回本地摘要，不会报错。

---

## 5. 实测记录（2026-11-16）

| 项目 | 结果 |
|---|---|
| 安装 | ✅ whisper 20250625 + torch 2.15.0+cpu（Python 3.12 venv，833 MB） |
| 中文清晰语音（26 s，合成） | ✅ base 6.6x 实时、small 2.1x 实时且全对 |
| 中文嘈杂音频（27 s，游戏实录） | ⚠️ 能出字但基本不可用——音频本身的问题 |
| 本地文件直读 | ✅ mp4 → ffmpeg 解码 → 转写 |
| **URL 全链路**（yt-dlp → 音频 → 转写 → 摘要） | ✅ `dQw4w9WgXcQ`：193 s 音频，tiny 模型 38.5 s 转完（**5.0x 实时**） |
| SRT / Markdown 输出 | ✅ 时间轴、字幕、摘要齐全 |
| `视频总结.bat`（拖文件/粘贴链接） | ✅ 自动补齐 PATH，不依赖当前窗口环境 |
| 模型下载耗时 | base ~40 s、small 484 MB 约 5.6 分钟（走代理） |

---

## 6. 坑与注意

1. **必须用 Python ≤3.12**：3.14 没有 torch wheel。
2. **ffmpeg 必需**：Whisper 靠它解码音频。脚本会自动把 `Programs\ffmpeg\bin` 补进 PATH，但你自己写代码时要留意。
3. **文件名字符**：原视频标题里的 `[ ] #` 会造成命令行通配符问题，脚本已清洗，但外部工具引用时用 `-LiteralPath`。
4. **CPU 速度天花板**：10 分钟视频用 `small` 约 5 分钟；想更快只能上 GPU（P3200 可跑，但 CUDA 版 torch 约 2.5 GB，没装）。
5. **YouTube 下载仍受登录限制**：涉及 bot-check 的视频，先把 `download` 里的 Cookie 问题解决（见那边手册 4.14）。

---

## 7. 目录

```
summarize\
├─ README.md               ← 本文
├─ 视频总结.bat             ← 单条入口（拖链接/文件）
├─ 批量分析.bat             ← 批量入口（B站关键词 / 链接列表）
├─ 测试AI配置.bat           ← 检查 llm_config.txt 是否可用
├─ 检查环境.bat             ← 版本/模型缓存/ffmpeg 自检
├─ pipeline.py             ← 单条主流程
├─ batch_platform.py       ← 批量主流程
├─ llm_config.txt          ← AI 总结配置（已填 DeepSeek）
├─ llm_config.sample.txt
├─ 批量分析-平台能力.md      ← 三平台能力与限制
├─ tools\douyin.js         ← 抖音下载（本地副本，自包含）
└─ out\                    ← 结果（自动创建）
```

重装：

```powershell
$venv = "$env:LOCALAPPDATA\Programs\whisper\venv"
& "C:\Users\<你的用户名>\AppData\Local\Programs\Python\Python312\python.exe" -m venv $venv
& "$venv\Scripts\python.exe" -m pip install openai-whisper
```
