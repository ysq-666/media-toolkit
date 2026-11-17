# 素材工具包 (Media & Web Intelligence Toolkit)

> **下载 → 抓取 → 转写 → 总结**，四条链路装在同一工作台内，全部本机运行。  
> 界面遵循 [heydamir/unslop](https://github.com/heydamir/unslop) Graphite Dark 工业设计规范：零装饰性 Emoji、4px 严格网格、等宽数值对齐、内置富文本排版检视器。

---

## 1. 核心架构与子系统

```text
toolkit/
├─ 素材工具箱.exe                   ← 唯一入口（通用启动器，在 PATH 里找 python.exe，不绑定任何一台电脑）
├─ toolkit_app.py                  ← 主控台源码（内置 Web Studio 服务 + 原生 Tkinter 备用界面 + CLI）
├─ 启动素材工具箱.bat               ← 备用启动入口（exe 双击没反应时用，自动探测 %LOCALAPPDATA% 虚拟环境）
├─ 一键安装环境依赖.bat             ← 双击安装缺失的 9 项环境依赖（完整模式）
├─ 一键安装环境依赖.ps1             ← 安装脚本本体（-Mode Quick 只装下载链；缺什么装什么）
├─ LICENSE                         ← MIT 开源协议
├─ .gitattributes                  ← .bat 强制 CRLF，避免 cmd 换行问题
├─ .gitignore                      ← Git 忽略规则（防止泄露 llm_config.txt 与 cookies.txt）
├─ docs/
│   └─ 产品架构报告与使用手册.md      ← 完整产品说明书、数据契约与架构解析
├─ download/                       ← ① 音视频下载（yt-dlp 全家桶 + 抖音无水印直读 Firefox Cookie）
├─ summarize/                      ← ② 语音转写 + AI 总结（原生字幕秒提 + Whisper + DeepSeek 跨视频汇总）
├─ scrape/                         ← ③ 反爬网页抓取（Scrapling HTTP / 浏览器渲染 / 过 Cloudflare / YouTube CSV）
└─ xhs/                            ← ④ 小红书专用（直读 Firefox 登录态，图文原图 + 视频笔记无水印 MP4 自动分流）
```

---

## 2. 快速开始

### 先装环境（新电脑只需做一次）
双击 **`一键安装环境依赖.bat`**：它会先逐项检查 9 项依赖，缺什么装什么，已有的不动，全部装到当前用户目录，不需要管理员权限。完整模式约 2 GB、20 分钟以上；只要下载链能用，改用 `powershell -ExecutionPolicy Bypass -File .\一键安装环境依赖.ps1 -Mode Quick`。装完回到工作台「环境与依赖」页点「重新扫描 9 项依赖」确认。也可以直接在工作台「环境与依赖」页点「快速安装缺失依赖（下载链）」或「完整安装缺失依赖（全部 9 项）」。

### 方式 A：图形工作台（推荐）
直接双击 **`素材工具箱.exe`**（它在 PATH 里找 `python.exe`，不绑定任何一台电脑；如果双击没反应，改双击 `启动素材工具箱.bat`，它会自动探测本机 whisper / scrapling 虚拟环境）。主程序本身只用 Python 标准库，启动不需要装第三方包；下载、转写、抓取用的重型工具（yt-dlp、ffmpeg、Whisper、Node.js 等）按第 3 节另装：
- **左侧导航栏（支持键盘快捷键 `1` ~ `6`）**：一键切换「下载中心 / 转写与总结 / 批量平台分析 / 网页抓取 / 小红书图文视频 / 环境与依赖」。
- **中央参数区与实时终端**：所有子进程输出经过 `UTF-8 / GB18030` 双编码自适应解码，彻底告别中文 Windows 路径乱码。
- **右侧富文本检视器**：转写或抓取完成后，自动列出最新 `.md` / `.srt` / `.csv` / `笔记.txt`，支持 **排版视图渲染**、**源码视图切换**、**一键定位文件所在目录 (`explorer /select`)**、**打开文件** 与 **复制全文**。

### 方式 B：命令行自动化 (CLI)
```powershell
.\素材工具箱.exe check
.\素材工具箱.exe download "https://www.youtube.com/watch?v=xxxx" --mode 1080p
.\素材工具箱.exe summarize "https://www.bilibili.com/video/BVxxxx" --mode ai --model small --lang zh
.\素材工具箱.exe batch "Python 教程" --mode bilibili --count 3 --model small
.\素材工具箱.exe scrape "https://quotes.toscrape.com/" --mode http
.\素材工具箱.exe xhs "https://www.xiaohongshu.com/explore/xxxx?xsec_token=..."
```

---

## 3. 外部运行时依赖（安装在 `%LOCALAPPDATA%\Programs\`）

本仓库代码与重型运行时解耦，以下组件安装在系统用户目录下（可在软件第 `6` 页签「环境与依赖」中一键自检）：

| 组件 | 推荐版本 | 路径 | 服务子系统 |
|---|---|---|---|
| **yt-dlp** | `2026.10.26` | `%LOCALAPPDATA%\Programs\yt-dlp\yt-dlp.exe` | `download` / `summarize` |
| **ffmpeg / ffprobe** | `9.0.2` | `%LOCALAPPDATA%\Programs\ffmpeg\bin` | `download` / `summarize` |
| **deno** | `2.9.8` | `%LOCALAPPDATA%\Programs\deno` | YouTube JS 挑战求解 |
| **POT 插件 + 服务端** | `bgutil 2.0.2` | `%APPDATA%\yt-dlp\plugins` + `%USERPROFILE%\bgutil-ytdlp-pot-provider` | YouTube 媒体流鉴权 (`:4416`) |
| **Python 3.12 venv (Whisper)** | `whisper 20250625` | `%LOCALAPPDATA%\Programs\whisper\venv` | `summarize` 离线语音识别 |
| **Python 3.14 venv (Scrapling)** | `scrapling 0.5.1` | `%LOCALAPPDATA%\Programs\scrapling\venv` | `scrape` 网页提取 |
| **浏览器内核** | `chromium 1248/1255` | `%LOCALAPPDATA%\ms-playwright` | `scrape` 浏览器与 Cloudflare 模式 |
| **Node.js** | `24.15.0` | `C:\Program Files\nodejs` | `douyin.js` / `xhs.js` / `node:sqlite` |
| **Firefox** | `160+` | `C:\Program Files\Mozilla Firefox` | 实时登录态（YouTube / B站 / 抖音 / 小红书） |

以上 9 项都可由一键安装脚本自动补齐，见第 2 节「先装环境」。

---

## 4. 配置说明与 GitHub 安全须知

1. **AI 总结配置**：将 `summarize/llm_config.sample.txt` 复制为 `summarize/llm_config.txt`，填入 `KEY`、`BASE`（如 `https://api.deepseek.com/v1`）与 `MODEL`（如 `deepseek-chat`），也可直接在图形工作台「转写与总结」页签内填写并点击保存。
2. **登录态配置**：建议直接在 Firefox 浏览器中登录目标站点（YouTube / B站 / 抖音 / 小红书），四个子系统均已支持直读 Firefox 实时 Cookie 库，无需手动导出 `cookies.txt`。
3. **本仓库已脱敏**：公开发布的包里不含任何 API Key 与 Cookie（只有 `llm_config.sample.txt` / `config.sample` 模板）。如果你在本地填入了自己的配置又想分享，请先删掉 `summarize/llm_config.txt` 与 `download/cookies.txt`（`.gitignore` 已默认拦截这两类文件，不会误提交）。

详细架构设计与数据契约请参阅 [`docs/产品架构报告与使用手册.md`](docs/产品架构报告与使用手册.md)。
