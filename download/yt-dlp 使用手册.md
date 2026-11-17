# yt-dlp 使用手册（本机定制版）

> 安装日期：2026-11-16　适用系统：Windows 10/11 x64
> 来源项目：<https://github.com/yt-dlp/yt-dlp>

---

## 0. 本机装了什么（实测环境）

| 组件 | 版本 | 路径 | 作用 |
|---|---|---|---|
| yt-dlp | **2026.10.26** | `C:\Users\<你的用户名>\AppData\Local\Programs\yt-dlp\yt-dlp.exe` | 主程序，下载器 |
| ffmpeg / ffprobe | **9.0.2 essentials** | `C:\Users\<你的用户名>\AppData\Local\Programs\ffmpeg\bin\` | 合并音视频、转码、转封装、嵌封面 |
| Node.js | **v24.15.0**（原有） | `C:\Program Files\nodejs\node.exe` | 备用 JS 运行时（需 `--js-runtimes node` 显式启用） |
| deno | **2.9.8** | `C:\Users\<你的用户名>\AppData\Local\Programs\deno\deno.exe` | **默认启用的** JS 运行时，YouTube 解析靠它 |

> ⚠️ **重要（实测踩坑）**：yt-dlp 2026.10.26 的 JS 运行时**默认只启用 deno**，装了 Node 也不算数，会报
> `WARNING: No supported JavaScript runtime could be found. Only deno is enabled by default; ... to use another runtime add --js-runtimes RUNTIME[:PATH]`
> 两种解法：① 装 deno（已装，现在零配置可用）；② 用 node 时每次加 `--js-runtimes node`。

ffmpeg 这个 build 自带的编码器（实测）：`libx264`、`libx265`、`libvpx-vp9`、`aac`、`libmp3lame`、`libopus`、`libvorbis`。
没有 AV1 编码器（AV1 能解码播放，不能转码输出），日常够用。

两个目录已加入**用户环境变量 PATH**，所以：

- 打开**新的** PowerShell / CMD 窗口，直接敲 `yt-dlp`、`ffmpeg` 即可；
- 已经开着的旧窗口不生效，关掉重开（或手动刷新 PATH）。

> 装机时 winget 下载被本机代理挡住（`InternetOpenUrl() failed`），改用 curl 走代理 `127.0.0.1:10808` 直取官方 release 包，属于便携式安装：**没有注册服务、没有写系统目录**，卸载只需删掉上面两个文件夹并从 PATH 移除。

验证是否正常：

```powershell
yt-dlp --version     # 期望输出 2026.10.26
ffmpeg -version      # 期望第一行含 "ffmpeg version 9.0.2"
node --version       # 期望 v24.x
```

也可以直接双击本目录里的 **`检查环境.bat`**，它会把四项一次性打出来。

### 安装时踩到的两个坑（记录备查）

1. `winget install yt-dlp` / `Gyan.FFmpeg` 全部报 `InternetOpenUrl() failed, 0x80072efd`——winget 走的是 WinHTTP 直连，不认 `HTTP_PROXY` 环境变量，而本机是代理上网。改用 `curl --proxy http://127.0.0.1:10808` 直接抓官方 release 包，手动放到 `Programs` 目录并写入用户 PATH。
2. `.bat` 脚本里放过中文，双击后中文全乱、还把命令行切断（cmd 按 OEM 代码页读批处理文件，UTF-8 内容会破坏引号配对）。所以**本目录所有 bat 的屏幕输出都是英文，注释和说明放在本手册里**——这是刻意设计，不是偷懒。

---

## 1. 一句话认识它

yt-dlp 是**命令行音视频下载器**，支持上千个站点（本机自带 1755 个提取器），是 `youtube-dl` 的实际继任者。
它的核心价值不是"能下 YouTube"，而是：**能列出站点提供的全部格式、任你挑选、再自动用 ffmpeg 拼装成品**。

不能做：DRM 加密内容（Netflix/Spotify 等）、付费/会员正片（除非你提供自己的账号 Cookie）。

---

## 2. 30 秒上手

```powershell
yt-dlp "视频链接"                        # 默认下最高画质（视频+音频自动合并）
yt-dlp -F "视频链接"                     # 先看有哪些格式可选，不下载
yt-dlp -t mp4 "视频链接"                 # 要 mp4，兼容性最好
yt-dlp -t mp3 "视频链接"                 # 只要 mp3 音频
yt-dlp -U                               # 升级自己（网站改版后第一件事）
```

**最重要的习惯：先 `-F` 再下。** 它能告诉你这个视频到底有没有 4K、有没有单独音轨、多大体积。

---

## 3. 图形化用法：本目录的 .bat 脚本

不想敲命令就用这些，**双击运行**，把链接粘贴进去回车，或者**把链接/网页直接拖到 bat 图标上**。

| 脚本 | 用途 | 输出到 |
|---|---|---|
| `一键下载-1080p视频.bat` | 1080p MP4 + 封面 + 元数据 | `%USERPROFILE%\Videos\yt-dlp\作者\日期 - 标题 [ID].mp4` |
| `一键提取-MP3音频.bat` | 只抽音频转 MP3（最高质量）+ 嵌封面 | `%USERPROFILE%\Music\yt-dlp\...` |
| `一键下载-带字幕封面.bat` | 视频 + 中文/英文字幕（转 srt 并内嵌）+ 封面 | `%USERPROFILE%\Videos\yt-dlp\...` |
| `批量追更-播放列表或频道.bat` | 整个列表/频道批量下，自动跳过已下过的 | `...\Videos\yt-dlp-playlists\列表名\001 - 标题.mp4` |
| `设置保存目录.bat` | **改保存路径**：输入路径或把文件夹拖上去，写进 `OUT.txt` | 生成 `OUT.txt` |
| `测试Cookie.bat` | 检查 `cookies.txt` 是否可用（含 bot-check 视频验证） | — |
| `导出全部Cookie.bat` | **一次导出所有网站 Cookie**（需先关闭浏览器；`... edge` 走 Edge） | 生成 `cookies.txt` |
| `合并Cookie文件.bat` | 合并 `cookies-src` 里逐站导出的 txt，去重成一份 | 生成 `cookies.txt` |
| `抖音下载.bat` | **抖音专用**（yt-dlp 自带提取器已失效），支持短链、去水印 | 同 `OUT.txt` 目录 |
| `检查环境.bat` | 自检：版本、PATH、ffmpeg、node | — |
| `安装全局配置.bat` | 把 `config.sample` 装成全局默认配置（默认未启用） | `%APPDATA%\yt-dlp\config` |
| `卸载全局配置.bat` | 撤销全局配置，恢复 yt-dlp 默认行为 | — |

四个下载脚本都支持：**拖拽链接到图标上**、**一次拖多个链接**、或运行后**粘贴链接**（可连续粘多条）。

### 3.1 改保存路径（三种方式，按使用场景选）

**方式 A：给脚本用 —— 双击 `设置保存目录.bat`（最省事）**

1. 双击 `设置保存目录.bat`；
2. 粘贴目标路径（例如 `D:\Videos` 或 `E:\番剧\2026`）后回车；也可以直接把文件夹**拖到这行 bat 图标上**；
3. 它会建好目录，把路径写进同目录的 `OUT.txt`。

之后四个下载脚本全部存到新位置，脚本本身不用改。
撤销：删掉 `OUT.txt` 即回到默认目录（`Videos\yt-dlp`）。

优先级从高到低：`YTDLP_OUT` 环境变量 > `OUT.txt` > 脚本内默认值。

**方式 B：临时换一次（不动任何文件）**

```powershell
set YTDLP_OUT=D:\Videos\收藏            # 当前窗口有效
.\一键下载-1080p视频.bat "URL"

# 或者命令行直接指定，一次一个视频
yt-dlp -P "D:\Videos\收藏" "URL"
```

**方式 C：改 yt-dlp 自己的默认（全局，对命令行也生效）**

编辑 `%APPDATA%\yt-dlp\config` 里的这一行（该文件需先启用，见第 5 节）：

```ini
-P "D:\Videos\收藏"
```

或者不改文件，直接在命令里带 `-P`。

> 补充：`-P` 只定"根目录"，真正决定文件名结构的是 `-o` 模板，例如
> `-o "%(uploader)s\%(title)s.%(ext)s"` 会在根目录下再建"作者"子文件夹。
> 想彻底平铺不分层：`-o "%(title)s [%(id)s].%(ext)s"`。
想临时换输出目录：先 `set YTDLP_OUT=D:\Videos\我的收藏` 再运行脚本，或在脚本里改 `OUT=` 那一行。

两个小说明：

- 脚本屏幕输出是英文——见第 0 节"坑 2"，中文会破坏 cmd 解析；文件路径和文件名仍然完全支持中文。
- `批量追更` 喂单个视频链接时文件名会带 `NA - ` 前缀（因为单视频没有列表序号），正常现象。

---

## 4. 命令速查（PowerShell / CMD 通用）

### 4.1 查看与演练

```powershell
yt-dlp -F "URL"                                     # 格式列表
yt-dlp -j "URL"                                     # 完整元数据 JSON
yt-dlp --print "%(title)s | %(duration_string)s | %(resolution)s" "URL"
yt-dlp --simulate "URL"                             # 只解析不下载
```

### 4.2 画质与格式

```powershell
# 默认已是 最佳视频+最佳音频，一般不用改
yt-dlp "URL"

# 上限 1080p；优先 h264+aac（兼容老设备/剪辑软件）
yt-dlp -S "res:1080,vcodec:h264,acodec:aac" "URL"

# 精准写法：只接受 mp4 容器
yt-dlp -f "bv*[height<=1080][ext=mp4]+ba[ext=m4a]/b[height<=1080]" "URL"

# 不要 4K，只要最小体积
yt-dlp -S "res:480" -f "bv*+ba/b" "URL"

# 只要一个现成的整合文件（不合并、最快）
yt-dlp -f "b" "URL"
```

字段说明：`bv*`=最佳视频轨、`ba`=最佳音频轨、`b`=最佳整合格式、`/` 表示回退链。
`-S`（排序）比 `-f`（过滤）更好维护，推荐用 `-S`。

### 4.3 音频

```powershell
yt-dlp -x --audio-format mp3 --audio-quality 0 "URL"     # mp3 最高质量
yt-dlp -x --audio-format m4a "URL"                       # 苹果生态/无损容器更合适
yt-dlp -x --audio-format flac "URL"                      # 站点本身提供无损时才有意义
yt-dlp -t mp3 "URL"                                      # 官方预设，等价于第一条
```

### 4.4 字幕

```powershell
yt-dlp --write-subs --sub-langs "zh.*,en.*" "URL"                 # 下人工字幕
yt-dlp --write-auto-subs --sub-langs "zh-Hans" "URL"              # 下自动生成字幕
yt-dlp --write-subs --sub-langs "zh.*,en.*" --embed-subs `
       --convert-subs srt --write-auto-subs "URL"                 # 转 srt 并内嵌
```

### 4.5 封面与元数据

```powershell
yt-dlp --write-thumbnail --convert-thumbnails jpg "URL"           # 单独存封面图
yt-dlp --embed-thumbnail --embed-metadata "URL"                   # 嵌进文件（mp4/m4a/mkv）
```

### 4.6 播放列表 / 频道 / 批量

```powershell
yt-dlp "播放列表URL"                                  # 整个列表
yt-dlp --no-playlist "URL"                            # 链接带 list= 时，强制只下当前视频
yt-dlp -I 1:10 "列表URL"                              # 前 10 个
yt-dlp --playlist-items 1-5,8,20- "列表URL"
yt-dlp --download-archive archive.txt "频道URL"       # 追更：下过的记在 archive.txt，不再重复
yt-dlp --dateafter 20260101 "频道URL"                 # 只要 2026 年之后的
```

### 4.7 命名与目录

```powershell
yt-dlp -P "D:\Videos" -o "%(uploader)s\%(upload_date>%Y-%m-%d)s - %(title)s [%(id)s].%(ext)s" "URL"
```

常用字段：`title` `id` `ext` `uploader` `channel` `upload_date` `playlist_index` `resolution` `duration_string`。
技巧：`%(upload_date>%Y-%m-%d)s`（日期格式化）、`%(title).80B`（截断 80 字节）、`%(uploader|未知)s`（默认值）。
后处理会改文件名，想看最终落盘路径用 `--print after_move:filepath`。

### 4.8 网络：代理 / 限速 / 重试 / 反爬

```powershell
yt-dlp --proxy "http://127.0.0.1:10808" "URL"      # 走本机代理（你机器上就有这个端口）
yt-dlp -r 5M "URL"                                  # 限速 5MB/s
yt-dlp --retries 10 --fragment-retries 10 "URL"     # 弱网/被限流时加
yt-dlp -N 8 "URL"                                   # 分片并发 8（DASH/HLS 加速）
yt-dlp --impersonate chrome "URL"                   # 伪装 TLS 指纹，绕部分站点风控
yt-dlp --sleep-requests 0.75 --sleep-interval 5 "URL"   # 温柔模式，防封
```

### 4.9 登录态 / 会员内容（解决 90% 的"下不下来"）

Cookie 有三种拿法，按你的耐心选：

#### 方式 1：一次导出**所有网站**（推荐，一条脚本搞定）

双击 **`导出全部Cookie.bat`**：

1. **先彻底关掉浏览器**（关窗口 → 托盘图标右键 Quit，Chromium 关窗口后仍在后台跑，会锁住 cookie 库）；
2. 双击脚本，会自动：复制 `Local State` + `Cookies` 数据库 → 起一个临时无头浏览器 → 通过 DevTools 协议把**全站 Cookie** 一次性导出 → 写成 `cookies.txt` → 关闭临时浏览器并清理；
3. 用 Edge 也行：命令行 `导出全部Cookie.bat edge`。

> 原理：Chromium 136+ 禁止对**默认配置目录**开启远程调试，所以脚本把 cookie 库复制到临时目录再读（这也顺带绕过了运行中锁库的问题）。
> 代价：**会话级 Cookie（没有过期时间的）不会落盘**，复制不到。YouTube / B 站这类站点的登录态都是长效 Cookie，不受影响。

#### 方式 2：逐站导出 + 合并（不想关浏览器时用）

扩展一次只能导出当前站点，那就导完再合并：

1. 用扩展把每个站的 cookie 导出成 `.txt`（文件名随意）；
2. 全部丢进工具箱里的 **`cookies-src`** 文件夹（脚本会自动创建）；
3. 双击 **`合并Cookie文件.bat`** → 去重、排序、补标准头部 → 生成 `cookies.txt`。

去重规则：同一 `域名 + 路径 + 名字` 只保留**最后一条**，所以新导出的会覆盖旧的，可以放心反复追加。

#### 方式 3：命令行直接用

```powershell
yt-dlp --cookies cookies.txt "URL"          # 用导出的 cookie 文件
yt-dlp --cookies-from-browser edge "URL"    # 借用本机 Edge 登录态（浏览器需关闭）
yt-dlp --cookies-from-browser chrome "URL"  # Chrome（同上）
yt-dlp -u 账号 -p 密码 "URL"                # 站点支持账号密码时
```

导出后，**四个下载脚本会自动使用**工具箱目录下的 `cookies.txt`，不需要改命令。

用 `测试Cookie.bat` 一键验证是否生效。

> ⚠️ 一个容易踩的坑：yt-dlp 用 `--cookies` 时会**回写**这个文件（把头部改成 `# This file is generated by yt-dlp. Do not edit.`，并丢掉 `#HttpOnly_` 前缀）。
> 想保留原始导出，就另存一份 `cookies-master.txt` 备份，需要时再复制回 `cookies.txt`。

**为什么不用 `--cookies-from-browser`（实测结论）**

本机 Chrome 14 个进程、Edge 25 个进程常驻，直接报：

```
ERROR: Could not copy Chrome cookie database. See https://github.com/yt-dlp/yt-dlp/issues/7271
```

原因是 Chromium 系浏览器运行时锁住了 Cookies 数据库（v127+ 还叠加 App-Bound Encryption）。
能忍的话可以先**完全退出浏览器**再试；更省事的还是 `cookies.txt`。

> 三种报错怎么区分：
> - `Sign in to confirm you're not a bot` → 需要 Cookie（见上）。
> - `This video is unavailable` → 视频本身不可用：已删除 / 私有 / 地区限制 / 年龄限制。换个视频或换出口 IP 再判断。
> - `The web client only works when logged-in` → 该站要求登录，给 Cookie 即可。
>
> 实测：`dQw4w9WgXcQ` 不带 Cookie 直接能下 4K；`jNQXAC9IVRw` 不带 Cookie 必定触发 bot-check。**同一台机器、同一条命令，结果取决于视频本身**，所以别把单次失败当成工具坏了。

### 4.10 其它好用的开关

```powershell
yt-dlp --download-sections "*00:10:00-00:12:00" "URL"   # 只下某一段（配 --force-keyframes-at-cuts 切割更准）
yt-dlp --sponsorblock-remove default "URL"              # 自动剪掉赞助/片头/自我推广段（YouTube）
yt-dlp --split-chapters "URL"                           # 按章节切成多个文件
yt-dlp --remux-video mkv "URL"                          # 只换容器不重编码（秒完成）
yt-dlp --windows-filenames "URL"                        # 文件名强制 Windows 安全
yt-dlp --exec "explorer /select,{}" "URL"                # 下完自动定位到文件
yt-dlp --downloader aria2c -N 16 "URL"                  # 外挂 aria2c 多线程（需自行安装）
```

### 4.11 抖音专用（yt-dlp 内置提取器已失效，别再用它）

**现象**

```
[Douyin] 7694… : Downloading web detail JSON
WARNING: [Douyin] …: Failed to download web detail JSON: HTTP Error 403: Forbidden
ERROR: [Douyin] …: Fresh cookies (not necessarily logged in) are needed; please report this issue on …
```

**根因（已核对上游源码）**

yt-dlp 的 `DouyinIE` 直接请求 `https://www.douyin.com/aweme/v1/web/aweme/detail/`，只带 `aweme_id`，
而该接口现在要求 `a_bogus` 签名参数。源码里对应的仍是这句 TODO：

```python
# TODO: Run verification challenge code to generate signature cookies
raise ExtractorError('Fresh cookies (not necessarily logged in) are needed', ...)
```

也就是说：**这不是你 Cookie 的问题**，加再多 Cookie 也过不去；master 分支同样没修。
注意报错里的 `expected=not s_v_web_id` —— 你的 Cookie 里**有** `s_v_web_id`，所以它让你去提 issue，这正是"已知未修"的信号。

**可用方案：`抖音下载.bat`**

改走 `https://www.iesdouyin.com/share/video/<id>/` 分享页，页面里内嵌的 `_ROUTER_DATA` 自带 `play_addr`，不需要签名。

```powershell
# 用法一：拖链接到 bat，或双击后粘贴（支持 www.douyin.com/video/… 和 v.douyin.com/… 短链）
# 用法二：命令行
node douyin.js "https://v.douyin.com/XXXXXXX" "%USERPROFILE%\Videos\yt-dlp"
```

它会：解析短链 → 拿作品 ID → 取 `play_addr` → **把 `/playwm/` 换成 `/play/`（去水印）** → 下载并命名成 `文案 [作品ID].mp4`。

实测（2026-11-16，你的链接 `v.douyin.com/W5iBp2NUCx8`）：

```
作品 ID: 7694986911550593530
作者: Dovy        时长: 27s
输出: 十年前的游戏放在今天开启DLSS5依然能打#… [7694986911550593530].mp4
大小: 5.7 MB（无水印版；带水印版是 10.1 MB）
ffprobe: h264 1280x720 + aac, 27.3s
```

**注意事项**

- 分享页**带 Cookie 才有 `play_addr`**；不带 Cookie 时实测 `play_addr=false`，所以仍需 `cookies.txt`。
- `ttwid` 必须是新的：过一段时间失效后重新导出 Cookie 即可。
- 图文作品（`image_infos`）没有视频轨，会明确报错，不是 bug。

### 4.12 YouTube 关键词搜索 + 批量下载

yt-dlp 内置 `ytsearch` 伪链接，**不需要额外的搜索接口**：

```powershell
yt-dlp "ytsearch5:lofi hip hop" --flat-playlist --print "%(title)s | %(id)s"   # 只列结果
yt-dlp "ytsearch10:关键词" -I 1:10 -f "bv*+ba/b" -S res:1080                  # 直接批量下
```

本目录的 **`YouTube关键词批量下载.bat`** 把上面这套封好了：

- 双击后输入关键词、条数、时长上限、以及「1=只列清单 / 2=下载」；
- 也支持参数式：`YouTube关键词批量下载.bat "关键词" 5 10 2`（=关键词/条数/最长分钟/模式）
- 自带：`--download-archive` 去重（下过的不会重复下）、`--match-filter` 时长过滤、1080p + h264 优先、封面/元数据、串行限速

**实测（2026-11-16）**

| 环节 | 结果 |
|---|---|
| 搜索（`ytsearch5:`） | ✅ 1-3 秒返回标题/ID/时长 |
| 时长过滤（`--match-filter`） | ✅ 超时的自动跳过 |
| 下载已知可下视频（`dQw4w9WgXcQ`） | ⚠️ 见下 |

**必须说清楚的一个现实**：YouTube 现在把「搜索」和「取流」分开了。- 搜索随便用，不需要登录；
- **取流（真正下载媒体）越来越依赖登录态 Cookie 和 PO token**。本次实测同一台机器：
  - 默认客户端下 1080p 媒体 → `HTTP Error 403: Forbidden`；
  - 加 `--extractor-args "youtube:player_client=web_safari"` 后 360p 能下（11 MB），1080p 走 m3u8 也可行；
  - 部分 Shorts 直接 `Sign in to confirm you're not a bot`，换客户端也过不去。

所以脚本里做了两级：先按 1080p 下，失败自动降级到 `web_safari` + 360p 再试一次。
**要稳定批量，请务必准备带 YouTube 登录态的 `cookies.txt`**（导出方法见 4.9），没有它成功率完全看 YouTube 心情。

相关提示：

```powershell
yt-dlp --extractor-args "youtube:player_client=web_safari" "URL"    # 换客户端
yt-dlp -f 18 "URL"                                                  # 360p 渐进式 mp4，最稳
yt-dlp "ytsearchdate5:关键词"                                        # 按上传时间排序
```

### 4.13 PO Token Provider（已装好，解决 403）

YouTube 的媒体流现在要 **PO Token（GVS/player token）**，没有它，很多客户端直接 403。
本机已装 [bgutil-ytdlp-pot-provider](https://github.com/Brainicism/bgutil-ytdlp-pot-provider) **2.0.2**：

| 组件 | 位置 |
|---|---|
| 生成器（Node + BgUtils） | `%USERPROFILE%\bgutil-ytdlp-pot-provider\server`（已 `npm ci` + `tsc` 编译） |
| HTTP 服务 | `node ...\server\build\main.js`，监听 `127.0.0.1:4416` |
| yt-dlp 插件 | `%APPDATA%\yt-dlp\plugins\bgutil-ytdlp-pot-provider.zip`（对**所有** yt-dlp 调用生效） |

用法：**保证 4416 端口在跑就行**，命令不用改。

```powershell
# 图形化：双击 启动POT服务.bat（已在跑会直接提示）
# 或手动：
node "$env:USERPROFILE\bgutil-ytdlp-pot-provider\server\build\main.js"

# 验证插件加载：应看到
yt-dlp -v --simulate "URL" 2>&1 | Select-String "PO Token Providers"
#  [youtube] [pot] PO Token Providers: bgutil:http-2.0.2 (external), bgutil:script-node-2.0.2 (external)
# 真正触发时会打印：
#  [youtube] [pot:bgutil:http] Generating a gvs PO Token for web client via bgutil HTTP server
```

`YouTube关键词批量下载.bat` 已内置：**开跑前自动检测 4416，没起就悄悄拉起来**。

**实测效果（2026-11-16，同一视频 dQw4w9WgXcQ）**

| 场景 | 装 POT 前 | 装 POT 后 |
|---|---|---|
| `player_client=web` 的 GVS token | 无 token → 403 | ✅ 生成 token → 正常下载 |
| 默认客户端 1080p | ❌ 403 | ✅ 33.8 MB mp4 成功（av1 1080p） |
| `-f 18` 渐进式 360p | ❌ 403 | ✅ 11.8 MB 成功 |
| h264 1080p（format 137） | ❌ 403 | ❌ 仍 403（POT 不覆盖这条轨） |
| 需要登录的视频（bot-check） | ❌ | ❌ 仍失败，POT 不能绕过 IP 级登录限制 |

**两个必须记住的结论**

1. **陈旧的 `cookies.txt` 会让情况更糟**：带着过期的 YouTube cookie 请求，YouTube 直接 403。
   所以 `YouTube关键词批量下载.bat` **默认不传 cookies**；确有新鲜 cookie 时，先 `set YTDLP_YT_COOKIES=1` 再跑。
2. **POT 不是万能**：它解决"媒体流要 token"，不解决"这个 IP 被要求登录"。
   要下被 bot-check 的视频，只能配新鲜的 YouTube 登录 Cookie。

### 4.14 哪些视频不用 Cookie 也能下（实测）

结论：**有，但比例取决于你的出口 IP，不是视频类型。**

2026-11-16 在本机（走 `127.0.0.1:10808` 代理，机房 IP）抽了 13 个视频：

| 结果 | 数量 | 例子 |
|---|---|---|
| ✅ 不用 Cookie 直接能下 | 1 | `dQw4w9WgXcQ` |
| ❌ `Sign in to confirm you're not a bot` | 11 | Gangnam Style、Despacito、Big Buck Bunny、Marvel 预告、若干 Shorts… |
| ❌ 视频本身不可用（早已删除） | 1 | `BaW_jenozKc` |

同一批失败视频换客户端也没用（`tv` / `tv_embedded` / `web_embedded` / `mweb` 全部照样要登录）。

所以规律是：

- YouTube 按 **IP 信任度 + 视频状态** 逐条判定，命中就要求登录；
- 机房/代理 IP 几乎必然被要求登录，只有极少数视频（多为热门/命中缓存）能过；
- 换成住宅 IP 或带上真实登录 Cookie，通过率会从"偶尔"变成"基本都能"；
- 年龄限制、会员专属、私享视频**永远**需要对应账号的 Cookie。

**快速判断单个视频要不要 Cookie**（不用下载）：

```powershell
yt-dlp --simulate -F "URL"      # 报 Sign in to confirm 就是需要 Cookie
```

不想记命令就双击 **`检查YouTubeCookie.bat`**：它会先用一个"必须登录"的视频探针判断你的 cookies.txt 是否真的有效，再用一个"无需登录"的视频做对照，把问题定位到 cookie 还是 IP。

**有没有数量限制？（实测数据，2026-11-16）**

脚本本身：**没有人写上限制** —— 不限条数、不限大小，逐条串行；目标文件已存在会直接跳过，不重复请求。

真正的限制来自抖音服务端的**风控（Argus）**，实测结果：

| 场景 | 结果 |
|---|---|
| 串行 + 间隔 800 ms，连打 12 次 | ✅ 12/12 成功，每次 0.4–0.7 s 返回 36 KB 页面 |
| 8 个**并发**请求 | ❌ 0/8，全部返回 2492 字节的验证页（含 `argus-csp-token`） |
| 被拦后立刻重试 / 等 25 s / 等 50 s | ❌ 仍然被拦 |
| 等到 **3 分钟** | ✅ 恢复 |
| 恢复后**紧接着再打一次** | ❌ 立刻又被拦 |

结论：

- **总量基本不限**：只要 Cookie 有效，一条一条下，下多少都行（磁盘占满为止）。
- **速率有限**：并发 = 必死；串行也要留间隔。脚本已按串行 + 2 秒间隔设计。
- **被拦是 IP+会话级的**，不是"次数用完了"；等几分钟就恢复，不用换账号。
- Cookie 过期与下载量无关，是时间/风控问题，重导即好。

脚本已内置：命中风控 → 打印原因 → 自动等 3 分钟重试一次（失败才退出，退出码 3）。

---

## 5. 全局配置模板（`config.sample`）

`config` 文件里一行一个参数，等价于每次自动带上这些开关。

安装位置（Windows 推荐）：`%APPDATA%\yt-dlp\config`

本目录已给好模板。**当前状态：未启用**（安装时只用它跑通了验证，随后已卸载，避免影响你既有习惯）。想要全局默认行为再启用：

```powershell
# 方式一：双击 安装全局配置.bat（已存在会先备份成 config.bak）
# 方式二：手动复制
copy "config.sample" "%APPDATA%\yt-dlp\config"
# 撤销：双击 卸载全局配置.bat
```

模板实际内容（`config.sample`，可自行增删）：

```ini
# coding: utf-8
-P "%USERPROFILE%\Videos\yt-dlp"
-o "%(uploader,channel,creator|Unknown)s\%(upload_date>%Y-%m-%d)s - %(title)s [%(id)s].%(ext)s"
-S res:1080,vcodec:h264,acodec:aac
--merge-output-format mp4
--embed-metadata
--write-thumbnail
--convert-thumbnails jpg
--retries 10
--fragment-retries 10
--concurrent-fragments 8
--windows-filenames
--no-mtime
# --proxy http://127.0.0.1:10808
# --cookies-from-browser edge
# --write-subs
# --write-auto-subs
# --sub-langs zh.*,en.*
# --embed-subs
# --convert-subs srt
# --sponsorblock-remove default
```

注意事项：

- 参数**不能**有空格：写 `-o`，不能写 `- o`；`--` 后不能空格。
- **带空格的值必须加引号**（模板里的 `-o` 就是），否则会被拆成多个参数——这是最容易踩的坑，实测过。
- 首行 `# coding: utf-8` 让 yt-dlp 按 UTF-8 读中文注释，别删。
- 想临时忽略所有配置：加 `--ignore-config`。
- 命令行参数优先于配置文件，所以脚本里显式写的选项不会被配置覆盖。

---

## 6. 更新与维护

```powershell
yt-dlp -U                      # 更新到当前通道最新版（本机是 release 版，可自更新）
yt-dlp --update-to nightly     # 切到 nightly 通道（官方推荐给日常用户）
yt-dlp --update-to master      # 最激进，每次提交都构建
yt-dlp --update-to stable@2026.10.26   # 回滚到指定版本
```

**判断标准：出问题第一件事就是更新。** 站点一改版，旧版立刻失效，八成"下载失败"都是版本太旧。
本机版本 2026.10.26 已是当前最新稳定版。

ffmpeg 想升级：重新下载 <https://www.gyan.dev/ffmpeg/builds/> 的 essentials 包，覆盖 `Programs\ffmpeg` 即可。

---

## 7. 故障排查表

| 现象 | 原因 | 处理 |
|---|---|---|
| `No supported JavaScript runtime could be found. Only deno is enabled by default` | 该版本只默认启用 deno | 装 deno（已装）；或用 node 时加 `--js-runtimes node` |
| `Sign in to confirm you're not a bot` | YouTube 风控，该视频要求登录态 | 放 `cookies.txt` 到工具箱目录，或 `--cookies --cookies-from-browser edge` |
| `Could not copy Chrome cookie database` | 浏览器正在运行，Cookies 库被锁 + v127+ ABE | 完全退出浏览器；或改用 `cookies.txt` |
| `This video is unavailable` | 视频已删 / 私有 / 地区限制 / 年龄限制 | 换视频或换出口 IP；不是工具问题 |
| `[Douyin] Failed to download web detail JSON: 403` + `Fresh cookies … needed` | 抖音 web 接口要 `a_bogus` 签名，yt-dlp 未实现（上游 TODO） | 用 `抖音下载.bat`，见 4.11 |
| `'yt-dlp' 不是内部或外部命令` | 当前窗口 PATH 没刷新 | 关掉重开窗口；或直接用完整路径 `& "$env:LOCALAPPDATA\Programs\yt-dlp\yt-dlp.exe"` |
| `ffmpeg not found` / 合并失败 | ffmpeg 不在 PATH | `--ffmpeg-location "C:\Users\<你的用户名>\AppData\Local\Programs\ffmpeg\bin"` |
| `Requested format is not available` | 版本旧 / 该视频真没这个画质 | 先 `-F` 看实际格式；再 `yt-dlp -U` |
| `HTTP Error 403` | 需要 Cookie 或签名过期 | 更新版本；放 `cookies.txt` |
| 只能下 360p、没有高码率 | 缺 JS 运行时被降级 / 未登录 | 确认 `deno --version` 可用；带 Cookie |
| `The web client only works when logged-in` | 站点要求登录 | 放 `cookies.txt`，或 `--cookies --cookies-from-browser edge` |
| 下载卡在 0% / 很慢 | 网络或分片被限 | `--proxy`、`-N 4`、`--retries 10` |
| 文件是 .webm 不是 mp4 | 站点只给 webm（VP9/AV1） | `--merge-output-format mp4 --remux-video mp4`，或 `-t mp4` |
| 下完了但没声音 | 只下了视频轨没合并 | 别用 `-f bv`，用 `-f "bv*+ba/b"` |
| 中文文件名乱码 | 终端代码页 | 用 Windows Terminal，或 `chcp 65001`；加 `--windows-filenames` |

自检命令（把问题一次看清楚）：

```powershell
yt-dlp -v --simulate "URL"      # 详细日志：版本、依赖、请求过程
yt-dlp --list-impersonate-targets
```

---

## 8. 当 Python 库用（做自动化时）

```python
import yt_dlp

opts = {
    "format": "bv*[height<=1080]+ba/b",
    "outtmpl": "%(uploader)s/%(title)s [%(id)s].%(ext)s",
    "paths": {"home": r"D:\Videos"},
    "cookiefile": "cookies.txt",
    "postprocessors": [
        {"key": "FFmpegExtractAudio", "preferredcodec": "mp3", "preferredquality": "0"},
    ],
}
with yt_dlp.YoutubeDL(opts) as ydl:
    info = ydl.extract_info("URL", download=True)
    print(info["title"], info["duration"])
```

---

## 9. 交付前实测记录（2026-11-16）

不是"装完就说好了"，下面每一项都真跑过：

| 项目 | 结果 |
|---|---|
| `yt-dlp --version` | ✅ 2026.10.26 |
| `ffmpeg -version` | ✅ 9.0.2-essentials_build |
| 提取器数量 `--list-extractors` | ✅ 1755 个 |
| 真实下载（generic 提取器 → mp4） | ✅ 788 KB 视频落地 |
| ffmpeg 转码（→ mp3 / ffprobe 校验时长 10.005s） | ✅ |
| `一键下载-1080p视频.bat`（含 -o 模板、嵌元数据） | ✅ 生成 `Unknown\2026-11-13 - mov_bbb [mov_bbb].mp4` |
| `一键提取-MP3音频.bat` | ✅ 生成 297 KB mp3 |
| `一键下载-带字幕封面.bat`（无字幕视频） | ✅ 正常降级为纯视频 |
| `批量追更-播放列表或频道.bat` | ✅ 生成 archive.txt + 文件 |
| `设置保存目录.bat` → 含中文与空格的路径 | ✅ 写入 `OUT.txt`，随后 1080p 脚本正确落到该目录 |
| 真实 YouTube 1080p（`dQw4w9WgXcQ`）经 bat 下载 | ✅ 合并成 84 MB mp4 + 封面 + 元数据 |
| `jNQXAC9IVRw`（bot-check 视频，无 Cookie） | ✅ 按预期触发 `Sign in to confirm you're not a bot`（用于验证 Cookie 流程） |
| `--cookies-from-browser chrome/edge` | ❌ 报 `Could not copy Chrome cookie database`（浏览器常驻锁库 + v127+ ABE）→ 改用 cookies.txt |
| CDP 全量导出（`dump-cookies.js`） | ✅ 起无头浏览器 → `Storage.getCookies` → 写出 Netscape 格式，字段/HttpOnly 前缀均正确 |
| 「复制 profile → 重启 → dump」链路 | ✅ 已复现验证：复制出的 profile 能被重新启动并解出 cookie |
| 合并脚本（含脏行、重复域名） | ✅ 3 文件→3 条/2 域名，无效行正确跳过 |
| yt-dlp 读取导出的 cookies.txt | ✅ 正常解析（注意：yt-dlp 会回写该文件） |
| 抖音（yt-dlp 内置提取器） | ❌ 403 + `Fresh cookies … needed`（缺 `a_bogus` 签名，上游 TODO，未修） |
| 抖音（`抖音下载.bat` 走分享页） | ✅ 短链 `v.douyin.com/W5iBp2NUCx8` 与长链均成功，5.7 MB 无水印 h264 720p |
| `测试Cookie.bat` 两种分支（无文件 / 有文件） | ✅ 提示与判定均正常 |
| deno 安装 | ✅ 2.9.8，PATH 已生效，JS 运行时警告消失 |
| `安装全局配置.bat` / `卸载全局配置.bat` | ✅ 装入、生效、删除均正常，`--print` 与 `-P` 路径解析已确认 |
| 新进程 PATH 解析（模拟新登录） | ✅ 三者均能在 PATH 中找到 |
| 临时文件清理 | ✅ 下载测试文件、临时解压目录全部删除 |

唯一没跑的是真实 YouTube 链接（需要一个具体视频，且带 Cookie 更稳）。你给个链接我可以顺手验证一遍。

---

## 10. 目录清单

```
<仓库目录>\download\
├─ yt-dlp 使用手册.md          ← 本文
├─ config.sample               ← 全局配置模板（默认未启用）
├─ 一键下载-1080p视频.bat
├─ 一键提取-MP3音频.bat
├─ 一键下载-带字幕封面.bat
├─ 批量追更-播放列表或频道.bat
├─ 设置保存目录.bat            ← 改保存路径（生成 OUT.txt）
├─ 测试Cookie.bat              ← 校验 cookies.txt 是否可用
├─ 导出全部Cookie.bat           ← 一次导出所有网站 Cookie（需关浏览器）
├─ 合并Cookie文件.bat           ← 把逐站导出合并成一份
├─ dump-cookies.js             ← 导出脚本本体（CDP）
├─ merge-cookies.js            ← 合并脚本本体
├─ 抖音下载.bat                 ← 抖音专用下载（绕开签名限制）
├─ douyin.js                   ← 抖音下载本体（分享页 + 去水印）
├─ 检查环境.bat
├─ 安装全局配置.bat
├─ 卸载全局配置.bat
├─ OUT.txt                     ← 可选，由 设置保存目录.bat 生成；删掉即恢复默认
├─ cookies-src\                ← 可选，放逐站导出的 txt（合并脚本读取）
└─ cookies.txt                 ← 可选，脚本自动使用的登录态
```

装好的程序本体（不在此目录）：

```
C:\Users\<你的用户名>\AppData\Local\Programs\yt-dlp\yt-dlp.exe
C:\Users\<你的用户名>\AppData\Local\Programs\ffmpeg\bin\{ffmpeg,ffprobe,ffplay}.exe
```

彻底卸载（不需要了的话）：

```powershell
Remove-Item -Recurse -Force "$env:LOCALAPPDATA\Programs\yt-dlp","$env:LOCALAPPDATA\Programs\ffmpeg","$env:LOCALAPPDATA\Programs\deno"
# 再从「用户环境变量 PATH」里删掉这三行：
#   %LOCALAPPDATA%\Programs\yt-dlp
#   %LOCALAPPDATA%\Programs\ffmpeg\bin
#   %LOCALAPPDATA%\Programs\deno
```

---

## 11. 合规提示

只下载你有权保存的内容：自己的作品、CC 授权素材、明确允许离线保存的资源。
用于个人离线观看通常没问题，二次分发或商用请先确认版权与站点条款。
