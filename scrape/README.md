# Scrapling 工具箱（与 yt-dlp 完全分开的一套）

> 安装日期：2026-11-16　项目：<https://github.com/D4Vinci/Scrapling>
> 版本：**0.5.1**　许可：BSD-3-Clause　Star：10.3 万

---

## 0. 装在哪（两套互不干扰）

| 项目 | 位置 |
|---|---|
| Scrapling 程序（独立 venv） | `C:\Users\<你的用户名>\AppData\Local\Programs\scrapling\venv` |
| 浏览器内核 | `C:\Users\<你的用户名>\AppData\Local\ms-playwright`（743 MB，含 chromium-1248 / 1255） |
| 本工具箱 | `<仓库目录>\scrape` |
| yt-dlp 那套（未改动） | `Programs\yt-dlp`、`Programs\ffmpeg`、`Programs\deno`，工具箱在 `桌面\测试\download` |

两套**没有任何共享文件**，路径、虚拟环境、浏览器、配置全部隔离；卸载 Scrapling 不影响 yt-dlp。

---

## 1. 它是什么

一句话：**网页抓取 / 爬虫框架**，不是下载器。

四层能力：

1. **解析器** `Selector`：CSS、XPath、正则、文本搜索、相似元素定位（`find_similar()`）；比 BeautifulSoup 快一个数量级。
2. **HTTP 抓取** `Fetcher` / `FetcherSession`：底层 curl_cffi，可伪装 Chrome 的 **TLS 指纹**和请求头，支持 HTTP/3、Cookie 会话、代理轮换。
3. **浏览器抓取** `StealthyFetcher` / `StealthySession`：patchright（Playwright 的反检测分支）+ 指纹伪造，能渲染 JS、**解 Cloudflare Turnstile**、拦截广告域、录制页面发出的 API 响应。
4. **爬虫框架** `Spider`：类 Scrapy 写法，并发、按域限速、AutoThrottle、**断点续跑**、JSON/JSONL/CSV/XML 导出、现成模板（`CrawlSpider` / `SitemapSpider` / `ShopifySpider`）。

另外还带：命令行 `scrapling extract`、IPython 交互 shell、**MCP server**（给 AI 客户端用）、`page.markdown()` 直接把网页转成干净 Markdown（喂 AI / 做 RAG）。

---

## 2. 和 yt-dlp 的区别（重点）

| 维度 | **yt-dlp**（已装） | **Scrapling**（本次装） |
|---|---|---|
| 定位 | 音视频**下载器** | 网页**抓取/爬虫框架** |
| 输入 | 视频/音频页面 URL | 任意网页 URL |
| 输出 | mp4 / mp3 / 字幕 / 元数据 | HTML / Markdown / 纯文本 / 结构化数据 |
| 站点适配 | **1755 个内置提取器**，开箱即用 | 不针对站点，自己写选择器 |
| 关键能力 | 格式选择、ffmpeg 合并、播放列表、SponsorBlock | TLS 指纹、浏览器渲染、过 Cloudflare、并发爬、断点续跑、导出 |
| 反爬手段 | Cookie、`--impersonate` | Cookie、浏览器指纹、Turnstile 破解、代理轮换、DoH |
| 能不能下视频 | ✅ 这就是它的本职 | ⚠️ 不直接下；但它能抓出 `m3u8/mp4` 直链，再交给 yt-dlp |
| 依赖 | ffmpeg + JS 运行时（deno） | Python 3.10+，浏览器可选（743 MB） |
| 适合谁 | 想下片、追更、批量归档 | 想采数据、监控页面、绕过反爬、给 AI 喂内容 |

**结论：互补，不是替代。**

- 有现成站点适配（YouTube / B站 / 抖音…）→ 走 yt-dlp，一条命令搞定。
- yt-dlp 报 403 / 需要签名 / 页面是 JS 渲染的 / 要抓接口数据 → 用 Scrapling 抓，再决定下一步。
- 组合拳：Scrapling 取到直链 → `yt-dlp --add-header "Referer:..." "<直链>"` 下载。
  （我们之前写的 `douyin.js` 其实就是这个思路的手写精简版。）

---

## 3. 怎么用

### 方式 A：双击 bat（不用写代码）

`抓取网页.bat` —— 拖链接进去或粘贴，选模式，输出到 `output\page_xxxxx.md`：

```
模式 1 = 快速 HTTP（TLS 指纹伪装，不开浏览器，约 1-2 秒）
模式 2 = 浏览器渲染 JS（约 5 秒，能拿到动态内容）
模式 3 = 浏览器 + 过 Cloudflare（1-3 分钟，慢但能过）
```

可选填 CSS 选择器（如 `.quote`）只抓需要的片段，输出是 Markdown。

命令行也能直接指定：`抓取网页.bat <url> <1|2|3> [选择器]`

### 方式 B：命令行

```powershell
$scp = "$env:LOCALAPPDATA\Programs\scrapling\venv\Scripts\scrapling.exe"

& $scp extract get  "https://quotes.toscrape.com/" out.md                      # 快速 HTTP
& $scp extract get  "https://quotes.toscrape.com/" out.txt --css-selector ".quote"
& $scp extract fetch "https://quotes.toscrape.com/js/" out.md --network-idle   # 浏览器渲染
& $scp extract fetch "https://site/" out.html --solve-cloudflare --timeout 180000
& $scp shell                                                                   # 交互式 IPython
```

### 方式 C：Python

```powershell
$py = "$env:LOCALAPPDATA\Programs\scrapling\venv\Scripts\python.exe"
& $py "示例-抓取与解析.py"
& $py "示例-抓取与解析.py" "https://example.com" --css ".quote .text"
& $py "示例-抓取与解析.py" "https://site/" --browser
& $py "示例-抓取与解析.py" "https://site/" --cookies "..\download\cookies.txt"
```

`--cookies` 直接吃 yt-dlp 那套的 `cookies.txt`（Netscape 格式通用），所以**两份 Cookie 不用重复导出**。

最小代码：

```python
from scrapling.fetchers import Fetcher
page = Fetcher.get("https://quotes.toscrape.com/", impersonate="chrome")
print(page.css(".quote .text::text").getall())   # 10 条
print(page.markdown()[:200])                     # 干净 Markdown
```

---

## 4. 实测记录（2026-11-16，全部真跑）

| 测试 | 结果 |
|---|---|
| 解析器（离线）：CSS / XPath / 链式选择 | ✅ `['Hello','World']`、`['A','B']` |
| HTTP 抓取 + `impersonate="chrome"` | ✅ status 200，10 条 quote，**1.75 s** |
| CLI `extract get` → Markdown | ✅ 生成 2662 字节 md |
| 带 Cookie 抓抖音分享页并取 `play_addr` | ✅ **0.58 s**（手写 node 版约 1.0 s，更快） |
| JS 渲染页（`quotes.toscrape.com/js/`） | ✅ 5.4 s，拿到 10 条（纯请求拿不到） |
| Cloudflare Turnstile 演示页 | ✅ 通过（177 s 后 challenge 消失、页面含 success）——**但极慢** |
| 浏览器依赖安装 | ✅ 743 MB（chromium 1248 + 1255 + ffmpeg + winldd） |

---

## 5. 踩到的坑（省你时间）

1. **浏览器版本对不上**：`scrapling install` 装的是 playwright chromium-**1255**，但 `StealthyFetcher` 走 patchright，要 chromium-**1248**。
   报错 `Executable doesn't exist at ...chromium-1248\chrome-win64\chrome.exe`，补一条命令即可：
   ```powershell
   & "$env:LOCALAPPDATA\Programs\scrapling\venv\Scripts\python.exe" -m patchright install chromium
   ```
2. **Cookie 格式**：curl_cffi 只接受 `{name: value}` 的 dict，传带 `domain` 的 dict 列表会报
   `ValueError: too many values to unpack`。示例脚本里的 `load_cookies_netscape()` 已经处理好。
3. **Cloudflare 模式很慢**：2-3 分钟起步，且只对 Turnstile/Interstitial 有效；企业级（Akamai/DataDome/Kasada）别指望。
4. **版本还是 0.x**：API 变动快，跟文档走，别照抄旧教程。
5. **Windows 控制台中文**：bat 里已 `chcp 65001`；直接在 PowerShell 里跑 python 时中文可能显示成乱码，属显示问题，数据本身正常。
6. 浏览器模式**吃内存**（一个 Chromium 实例几百 MB），别并发开一堆。

---

## 6. 目录

```
<仓库目录>\scrape\
├─ README.md                 ← 本文
├─ 抓取网页.bat               ← 图形化抓取（3 种模式）
├─ 检查环境.bat               ← 版本/依赖/浏览器自检
├─ 示例-抓取与解析.py          ← HTTP / 浏览器 / 带 Cookie 三种姿势
├─ YouTube搜索抓取.py          ← 抓 YouTube 搜索结果 → CSV（配合 yt-dlp 用）
└─ output\                   ← 抓取结果（自动创建）
```

### YouTube 搜索结果抓取

`yt-dlp` 自带 `ytsearch` 能搜索（无需登录），但被限流或想先落表格时用这个：

```powershell
$py = "$env:LOCALAPPDATA\Programs\scrapling\venv\Scripts\python.exe"
& $py "YouTube搜索抓取.py" "lofi hip hop"
```

实测：2.2 秒抓到 18 条（ID/标题/时长/频道/播放量），存成 UTF-8-BOM 的 CSV，
并直接打印出可复制的 `yt-dlp https://www.youtube.com/watch?v=...` 命令。
只抓搜索页，不下载视频——下载仍然交给 yt-dlp。

重装步骤（万一环境坏了）：

```powershell
$venv = "$env:LOCALAPPDATA\Programs\scrapling\venv"
python -m venv $venv
& "$venv\Scripts\python.exe" -m pip install "scrapling[fetchers,shell]"
& "$venv\Scripts\scrapling.exe" install
& "$venv\Scripts\python.exe" -m patchright install chromium
```

彻底卸载：删掉 `Programs\scrapling`、`%LOCALAPPDATA%\ms-playwright`、本目录即可（不写注册表、不加 PATH）。
