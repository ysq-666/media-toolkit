#Requires -Version 5.1
<#
.SYNOPSIS
    素材工具包 · 一键安装环境依赖
.DESCRIPTION
    对照主程序 RuntimeEnv.inspect_all_dependencies() 的同一套 9 项依赖逐项检查，
    缺什么装什么，已有的不动。全部装到当前用户目录，不需要管理员权限。

    快速模式 (Quick)：只装下载链 —— yt-dlp / ffmpeg / deno / Node.js / Firefox。
    完整模式 (Full，默认)：再装 POT 服务端、Whisper 虚拟环境 (Python 3.12)、
    Scrapling 虚拟环境 (Python 3.14) 与浏览器内核，约 2 GB，耗时 20 分钟以上。

    用法：
      双击 一键安装环境依赖.bat                    # 完整模式
      powershell -ExecutionPolicy Bypass -File .\一键安装环境依赖.ps1 -Mode Quick
      powershell -ExecutionPolicy Bypass -File .\一键安装环境依赖.ps1 -Mode Full

    依赖来源（全部官方渠道）：yt-dlp / ffmpeg (Gyan) / deno / Node.js /
    Firefox / bgutil-ytdlp-pot-provider 均直接下载官方发布包；
    Python 3.12 / 3.14 走 winget；Whisper / Scrapling 走 pip。
    POT 那一步是尽力而为（best-effort），失败不影响其余 8 项，汇总里会单独说明。
#>
param(
    [ValidateSet("Quick", "Full")]
    [string]$Mode = "Full"
)

$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ProgramsDir = Join-Path $env:LOCALAPPDATA "Programs"
$TempRoot = Join-Path $env:TEMP "media-toolkit-setup"
$Script:FailedItems = @()
$Script:InstalledItems = @()

# ------------------------------------------------------------------
# 输出与小工具
# ------------------------------------------------------------------
function Write-Step { param([string]$Msg) Write-Host ""; Write-Host "== $Msg" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Msg) Write-Host "  [OK] $Msg" -ForegroundColor Green }
function Write-Info { param([string]$Msg) Write-Host "  $Msg" -ForegroundColor Gray }
function Write-Warn { param([string]$Msg) Write-Host "  [!] $Msg" -ForegroundColor Yellow }
function Write-Fail { param([string]$Msg) Write-Host "  [X] $Msg" -ForegroundColor Red }

function Refresh-Path {
    # winget / 安装程序改了用户 PATH 后，本次会话要重新读注册表才生效
    $machine = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $user = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:PATH = ($machine + ";" + $user)
}

function Add-UserPath {
    param([string]$Dir)
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if (($userPath -split ";") -notcontains $Dir) {
        [Environment]::SetEnvironmentVariable("Path", ($userPath + ";" + $Dir), "User")
        $env:PATH = $env:PATH + ";" + $Dir
        Write-Info "已把 $Dir 加入用户 PATH（新开的终端生效）"
    }
}

function Get-File {
    param([string]$Url, [string]$Out)
    $dir = Split-Path $Out -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $tries = 0
    while ($tries -lt 2) {
        $tries++
        try {
            Write-Info "下载：$Url"
            Invoke-WebRequest -Uri $Url -OutFile $Out -UseBasicParsing -ErrorAction Stop
            if ((Get-Item $Out).Length -gt 1024) { return $true }
            throw "下载到的文件过小，疑似失败页面"
        } catch {
            Write-Warn "Invoke-WebRequest 失败（第 $tries 次）：$($_.Exception.Message)"
            if ($tries -lt 2) { Start-Sleep -Seconds 3 }
        }
    }
    # 备用：系统自带 curl.exe
    try {
        Write-Info "改用 curl.exe 重试"
        & curl.exe --retry 2 -L -o $Out $Url 2>$null
        if ((Test-Path $Out) -and ((Get-Item $Out).Length -gt 1024)) { return $true }
    } catch { }
    return $false
}

function Test-RunOk {
    # 跑一个可执行文件并取第一行输出；跑不通返回 $null
    param([string]$Exe, [string[]]$Arguments)
    try {
        $out = & $Exe @Arguments 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) {
            $first = ($out -split "`r?`n" | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1)
            if ($first) { return $first.Trim() }
            return "可用"
        }
    } catch { }
    return $null
}

function Test-PythonCode {
    # 用指定 python 跑一段 import 自检，成功返回版本行
    param([string]$PyExe, [string]$Code)
    try {
        $out = & $PyExe -c $Code 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) {
            $first = ($out -split "`r?`n" | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1)
            if ($first) { return $first.Trim() }
            return "可用"
        }
    } catch { }
    return $null
}

# ------------------------------------------------------------------
# 9 项依赖的检测（与 toolkit_app.py 的 inspect_all_dependencies() 同口径）
# ------------------------------------------------------------------
function Test-YtDlp {
    $exe = Join-Path $ProgramsDir "yt-dlp\yt-dlp.exe"
    if (Test-Path $exe) { return (Test-RunOk $exe @("--version")) }
    $cmd = Get-Command "yt-dlp" -ErrorAction SilentlyContinue
    if ($cmd) { return (Test-RunOk $cmd.Source @("--version")) }
    return $null
}

function Test-Ffmpeg {
    $exe = Join-Path $ProgramsDir "ffmpeg\bin\ffmpeg.exe"
    if (Test-Path $exe) { return (Test-RunOk $exe @("-version")) }
    $cmd = Get-Command "ffmpeg" -ErrorAction SilentlyContinue
    if ($cmd) { return (Test-RunOk $cmd.Source @("-version")) }
    return $null
}

function Test-Deno {
    $exe = Join-Path $ProgramsDir "deno\deno.exe"
    if (Test-Path $exe) { return (Test-RunOk $exe @("--version")) }
    $cmd = Get-Command "deno" -ErrorAction SilentlyContinue
    if ($cmd) { return (Test-RunOk $cmd.Source @("--version")) }
    return $null
}

function Test-Node {
    $exe = Join-Path ${env:ProgramFiles} "nodejs\node.exe"
    if (Test-Path $exe) { return (Test-RunOk $exe @("--version")) }
    $cmd = Get-Command "node" -ErrorAction SilentlyContinue
    if ($cmd) { return (Test-RunOk $cmd.Source @("--version")) }
    return $null
}

function Test-Firefox {
    $exe = Join-Path ${env:ProgramFiles} "Mozilla Firefox\firefox.exe"
    if (Test-Path $exe) { return "已安装" }
    $exe86 = Join-Path ${env:ProgramFiles(x86)} "Mozilla Firefox\firefox.exe"
    if (Test-Path $exe86) { return "已安装" }
    $local = Join-Path $env:LOCALAPPDATA "Mozilla Firefox\firefox.exe"
    if (Test-Path $local) { return "已安装（当前用户）" }
    $cmd = Get-Command "firefox" -ErrorAction SilentlyContinue
    if ($cmd) { return "已安装" }
    return $null
}

function Test-Pot {
    $main = Join-Path $env:USERPROFILE "bgutil-ytdlp-pot-provider\server\build\main.js"
    if (Test-Path $main) { return "服务端构建文件存在" }
    return $null
}

function Test-WhisperVenv {
    $py = Join-Path $ProgramsDir "whisper\venv\Scripts\python.exe"
    if (-not (Test-Path $py)) { return $null }
    return (Test-PythonCode $py "import sys, whisper, torch; print(f'Py {sys.version.split()[0]} / whisper {whisper.__version__} / torch {torch.__version__}')")
}

function Test-ScraplingVenv {
    $py = Join-Path $ProgramsDir "scrapling\venv\Scripts\python.exe"
    if (-not (Test-Path $py)) { return $null }
    return (Test-PythonCode $py "import sys, scrapling, curl_cffi; print(f'Py {sys.version.split()[0]} / scrapling {scrapling.__version__} / curl_cffi {curl_cffi.__version__}')")
}

function Test-Playwright {
    $base = Join-Path $env:LOCALAPPDATA "ms-playwright"
    if (Test-Path (Join-Path $base "chromium-1248")) { return "chromium-1248 已安装" }
    if (Test-Path (Join-Path $base "chromium-1255")) { return "chromium-1255 已安装" }
    return $null
}

function Get-PythonExe {
    # 按版本号找 Python：先试 py 启动器，再试 winget 默认安装路径，最后看 PATH 里的 python
    param([string]$Version)  # "3.12" 或 "3.14"
    $pyLauncher = Get-Command "py" -ErrorAction SilentlyContinue
    if ($pyLauncher) {
        $out = & py ("-" + $Version) --version 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0 -and $out -match "Python $Version") {
            return @{ Launcher = @("py", "-$Version"); Exe = $null }
        }
    }
    $short = $Version.Replace(".", "")
    $wingetPath = Join-Path $env:LOCALAPPDATA "Programs\Python\Python$short\python.exe"
    if (Test-Path $wingetPath) { return @{ Launcher = @(); Exe = $wingetPath } }
    $cmd = Get-Command "python" -ErrorAction SilentlyContinue
    if ($cmd) {
        $out = & python --version 2>&1 | Out-String
        if ($out -match "Python $Version") { return @{ Launcher = @(); Exe = $cmd.Source } }
    }
    return $null
}

# ------------------------------------------------------------------
# 9 项依赖的安装（只装缺失的）
# ------------------------------------------------------------------
function Install-YtDlp {
    Write-Step "安装 yt-dlp（官方最新版，单文件）"
    $dir = Join-Path $ProgramsDir "yt-dlp"
    $out = Join-Path $dir "yt-dlp.exe"
    if (-not (Get-File "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe" $out)) {
        Write-Fail "yt-dlp 下载失败，请检查网络后重试，或手动下载后放到 $dir"
        return $false
    }
    $ver = Test-RunOk $out @("--version")
    if ($ver) { Write-Ok "yt-dlp $ver"; Add-UserPath $dir; return $true }
    Write-Fail "yt-dlp.exe 已下载但运行失败"
    return $false
}

function Install-Ffmpeg {
    Write-Step "安装 ffmpeg / ffprobe（Gyan essentials 构建）"
    $zip = Join-Path $TempRoot "ffmpeg-release-essentials.zip"
    $extract = Join-Path $TempRoot "ffmpeg-extract"
    if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
    if (-not (Get-File "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip" $zip)) {
        Write-Fail "ffmpeg 下载失败，请检查网络后重试"
        return $false
    }
    Expand-Archive -Path $zip -DestinationPath $extract -Force
    $bin = Get-ChildItem $extract -Directory | Where-Object { $_.Name -like "ffmpeg-*-essentials_build" } | Select-Object -First 1
    if (-not $bin) { Write-Fail "解压后找不到 ffmpeg 目录"; return $false }
    $dest = Join-Path $ProgramsDir "ffmpeg\bin"
    if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Force -Path $dest | Out-Null }
    Copy-Item (Join-Path $bin.FullName "bin\*") $dest -Force
    $exe = Join-Path $dest "ffmpeg.exe"
    $ver = Test-RunOk $exe @("-version")
    if ($ver) { Write-Ok "ffmpeg 已安装（$($ver.Split(" ")[0..2] -join ' ')）"; Add-UserPath $dest; return $true }
    Write-Fail "ffmpeg 已解压但运行失败"
    return $false
}

function Install-Deno {
    Write-Step "安装 deno（YouTube JS 挑战求解用）"
    $zip = Join-Path $TempRoot "deno.zip"
    $extract = Join-Path $TempRoot "deno-extract"
    if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
    if (-not (Get-File "https://github.com/denoland/deno/releases/latest/download/deno-x86_64-pc-windows-msvc.zip" $zip)) {
        Write-Fail "deno 下载失败，请检查网络后重试"
        return $false
    }
    Expand-Archive -Path $zip -DestinationPath $extract -Force
    $dir = Join-Path $ProgramsDir "deno"
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    Copy-Item (Join-Path $extract "deno.exe") (Join-Path $dir "deno.exe") -Force
    $ver = Test-RunOk (Join-Path $dir "deno.exe") @("--version")
    if ($ver) { Write-Ok "deno $ver"; Add-UserPath $dir; return $true }
    Write-Fail "deno 已解压但运行失败"
    return $false
}

function Install-Node {
    Write-Step "安装 Node.js 24.15.0（douyin.js / xhs.js / POT 需要，含 node:sqlite）"
    $ver = "24.15.0"
    $zip = Join-Path $TempRoot "node.zip"
    $extract = Join-Path $TempRoot "node-extract"
    if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
    if (-not (Get-File "https://nodejs.org/dist/v$ver/node-v$ver-win-x64.zip" $zip)) {
        Write-Fail "Node.js 下载失败，请检查网络后重试"
        return $false
    }
    Expand-Archive -Path $zip -DestinationPath $extract -Force
    $src = Join-Path $extract "node-v$ver-win-x64"
    $dir = Join-Path $ProgramsDir "nodejs"
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    Copy-Item (Join-Path $src "*") $dir -Recurse -Force
    $exe = Join-Path $dir "node.exe"
    $v = Test-RunOk $exe @("--version")
    if ($v) {
        Write-Ok "Node.js $v"
        Add-UserPath $dir
        Refresh-Path
        $sqlite = & $exe -e "require('node:sqlite'); console.log('node:sqlite 可用')" 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) { Write-Ok "node:sqlite 可用" } else { Write-Warn "node:sqlite 自检未通过（不影响大部分功能）" }
        return $true
    }
    Write-Fail "Node.js 已解压但运行失败"
    return $false
}

function Install-Firefox {
    Write-Step "安装 Firefox（实时登录态：YouTube / 抖音 / 小红书 / B站）"
    $exe = Join-Path $TempRoot "Firefox Setup.exe"
    if (-not (Get-File "https://download.mozilla.org/?product=firefox-latest-ssl&os=win64&lang=zh-CN" $exe)) {
        Write-Fail "Firefox 下载失败，请检查网络后重试，或手动从官网安装"
        return $false
    }
    Write-Info "正在静默安装 Firefox（无管理员权限时会自动装到当前用户目录）…"
    Start-Process -FilePath $exe -ArgumentList "/S" -Wait
    Start-Sleep -Seconds 3
    if (Test-Firefox) { Write-Ok "Firefox 已安装"; return $true }
    Write-Fail "Firefox 安装后仍未找到，请手动安装一次"
    return $false
}

function Install-Pot {
    # 尽力而为：失败只警告，不让整个安装停下（没有 POT 也能下载，只影响部分 YouTube 高清流）
    Write-Step "安装 POT 服务端 + 插件（bgutil 2.0.2，YouTube 高清流需要）"
    try {
        $serverDir = Join-Path $env:USERPROFILE "bgutil-ytdlp-pot-provider"
        $mainJs = Join-Path $serverDir "server\build\main.js"
        $pluginDir = Join-Path $env:APPDATA "yt-dlp\plugins"
        if (-not (Test-Path $pluginDir)) { New-Item -ItemType Directory -Force -Path $pluginDir | Out-Null }
        $pluginZip = Join-Path $pluginDir "bgutil-ytdlp-pot-provider.zip"

        if (-not (Test-Path $mainJs)) {
            $zip = Join-Path $TempRoot "bgutil.zip"
            $got = Get-File "https://github.com/Brainicism/bgutil-ytdlp-pot-provider/releases/download/2.0.2/bgutil-ytdlp-pot-provider.zip" $zip
            if (-not $got) {
                Write-Warn "2.0.2 发布包下载失败，改用 main 分支源码包"
                $got = Get-File "https://codeload.github.com/Brainicism/bgutil-ytdlp-pot-provider/zip/refs/heads/main" $zip
            }
            if (-not $got) { throw "bgutil 下载失败" }
            $extract = Join-Path $TempRoot "bgutil-extract"
            if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
            Expand-Archive -Path $zip -DestinationPath $extract -Force
            # 发布包：根目录就是 server/；源码包：多一层顶层目录
            $src = Get-ChildItem $extract -Directory | Where-Object { Test-Path (Join-Path $_.FullName "server\package.json") } | Select-Object -First 1
            if (-not $src) { $src = Get-Item $extract }
            if (Test-Path $serverDir) { Remove-Item $serverDir -Recurse -Force }
            if ($src.FullName -eq $extract) { Copy-Item (Join-Path $extract "*") $serverDir -Recurse -Force }
            else { Copy-Item $src.FullName $serverDir -Recurse -Force }
            # 插件 zip：发布包本身就是插件文件；源码包则把整个 zip 拷过去由 yt-dlp 解读
            if ((Get-Item $zip).Length -gt 1024) { Copy-Item $zip $pluginZip -Force }
        } elseif (-not (Test-Path $pluginZip)) {
            Write-Warn "服务端已存在，但插件 zip 缺失，请手动从 bgutil 发布页下载 bgutil-ytdlp-pot-provider.zip 放到 $pluginDir"
        }

        $nodeExe = $null
        $nodeCmd = Get-Command "node" -ErrorAction SilentlyContinue
        if ($nodeCmd) { $nodeExe = $nodeCmd.Source }
        if (-not $nodeExe) { throw "找不到 node，请先装好 Node.js 再装 POT" }
        $srv = Join-Path $serverDir "server"
        if (-not (Test-Path (Join-Path $srv "package.json"))) { throw "server/package.json 不存在，bgutil 包结构可能变了" }
        Write-Info "正在编译 POT 服务端（npm ci + npx tsc，需几分钟）…"
        Push-Location $srv
        try {
            & npm ci 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "npm ci 失败" }
            & npx tsc 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "npx tsc 失败" }
        } finally { Pop-Location }
        if (Test-Path $mainJs) { Write-Ok "POT 服务端已就绪（$mainJs）"; return $true }
        throw "编译后仍找不到 server/build/main.js"
    } catch {
        Write-Warn "POT 安装未完成：$($_.Exception.Message)"
        Write-Warn "可稍后手动处理：见 download/yt-dlp 使用手册.md §4.13，或直接用下载功能（无 POT 只影响部分 YouTube 高清流）"
        return $false
    }
}

function Install-Python {
    # 走 winget 装指定大版本的最新补丁版；返回是否装好
    param([string]$Version)  # "3.12" 或 "3.14"
    Write-Step "安装 Python $Version（winget）"
    $winget = Get-Command "winget" -ErrorAction SilentlyContinue
    if (-not $winget) {
        Write-Fail "本机没有 winget（需 Windows 10 1809+ / 应用安装程序），请手动装 Python $Version：https://www.python.org/downloads/"
        return $false
    }
    & winget install --id "Python.Python.$Version" -e --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
    Refresh-Path
    $found = Get-PythonExe $Version
    if ($found) { Write-Ok "Python $Version 已就绪"; return $true }
    Write-Fail "winget 安装后仍找不到 Python $Version，请手动安装：https://www.python.org/downloads/"
    return $false
}

function New-Venv {
    param([string]$Version, [string]$VenvPath)
    $found = Get-PythonExe $Version
    if (-not $found) { return $null }
    if (Test-Path $VenvPath) { return (Join-Path $VenvPath "Scripts\python.exe") }
    Write-Info "正在创建虚拟环境：$VenvPath"
    if ($found.Exe) { & $found.Exe -m venv $VenvPath 2>&1 | Out-Null }
    else { & py ("-" + $Version) -m venv $VenvPath 2>&1 | Out-Null }
    $venvPy = Join-Path $VenvPath "Scripts\python.exe"
    if (Test-Path $venvPy) { return $venvPy }
    return $null
}

function Install-WhisperVenv {
    Write-Step "安装 Whisper 虚拟环境（Python 3.12 + openai-whisper + torch CPU + opencc）"
    $venvPath = Join-Path $ProgramsDir "whisper\venv"
    if (-not (Get-PythonExe "3.12")) {
        if (-not (Install-Python "3.12")) { return $false }
    }
    $venvPy = New-Venv "3.12" $venvPath
    if (-not $venvPy) { Write-Fail "Whisper 虚拟环境创建失败"; return $false }
    & $venvPy -m pip install -U pip --disable-pip-version-check --quiet 2>&1 | Out-Null
    Write-Info "正在 pip 安装 openai-whisper + opencc（约几分钟）…"
    & $venvPy -m pip install "openai-whisper==20250625" opencc --disable-pip-version-check --quiet 2>&1 | Out-Null
    Write-Info "正在 pip 安装 torch（CPU 版，约 200MB，需几分钟）…"
    & $venvPy -m pip install torch --index-url https://download.pytorch.org/whl/cpu --disable-pip-version-check --quiet 2>&1 | Out-Null
    $ver = Test-PythonCode $venvPy "import sys, whisper, torch; print(f'Py {sys.version.split()[0]} / whisper {whisper.__version__} / torch {torch.__version__}')"
    if ($ver) { Write-Ok "Whisper 环境就绪（$ver）"; return $true }
    Write-Fail "Whisper 环境安装后自检失败，请重试一次，或手动在虚拟环境里跑 pip install"
    return $false
}

function Install-ScraplingVenv {
    Write-Step "安装 Scrapling 虚拟环境（Python 3.14 + scrapling 0.5.1 + 浏览器内核）"
    $venvPath = Join-Path $ProgramsDir "scrapling\venv"
    if (-not (Get-PythonExe "3.14")) {
        if (-not (Install-Python "3.14")) { return $false }
    }
    $venvPy = New-Venv "3.14" $venvPath
    if (-not $venvPy) { Write-Fail "Scrapling 虚拟环境创建失败"; return $false }
    & $venvPy -m pip install -U pip --disable-pip-version-check --quiet 2>&1 | Out-Null
    Write-Info "正在 pip 安装 scrapling[all] 0.5.1…"
    & $venvPy -m pip install "scrapling[all]==0.5.1" --disable-pip-version-check --quiet 2>&1 | Out-Null
    $scripts = Join-Path $venvPath "Scripts"
    $scraplingExe = Join-Path $scripts "scrapling.exe"
    if (Test-Path $scraplingExe) {
        Write-Info "正在安装浏览器内核（scrapling install，需下载约 150MB，请耐心等待）…"
        & $scraplingExe install 2>&1 | Out-Null
    }
    $patchrightExe = Join-Path $scripts "patchright.exe"
    if (Test-Path $patchrightExe) {
        Write-Info "正在补装 patchright chromium 内核…"
        & $patchrightExe install chromium 2>&1 | Out-Null
    }
    $ver = Test-PythonCode $venvPy "import sys, scrapling, curl_cffi; print(f'Py {sys.version.split()[0]} / scrapling {scrapling.__version__} / curl_cffi {curl_cffi.__version__}')"
    $pw = Test-Playwright
    if ($ver -and $pw) { Write-Ok "Scrapling 环境就绪（$ver；$pw）"; return $true }
    if ($ver) { Write-Warn "Scrapling 已装好，但浏览器内核未检出（$pw），浏览器渲染模式可能不可用，可重跑一次完整安装"; return $true }
    Write-Fail "Scrapling 环境安装后自检失败，请重试一次"
    return $false
}

# ------------------------------------------------------------------
# 主流程：先逐项检查，只装缺失的
# ------------------------------------------------------------------
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "  素材工具包 · 一键安装环境依赖（模式：$Mode）" -ForegroundColor Cyan
Write-Host "  全部装到当前用户目录，不需要管理员权限" -ForegroundColor Cyan
if ($Mode -eq "Full") { Write-Host "  完整模式约 2 GB、20 分钟以上；只要下载链可用，改用 -Mode Quick" -ForegroundColor Cyan }
Write-Host "==================================================" -ForegroundColor Cyan
if (-not (Test-Path $TempRoot)) { New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null }
Refresh-Path

$checks = @(
    @{ Name = "yt-dlp";               Test = { Test-YtDlp };        Install = { Install-YtDlp };        Quick = $true }
    @{ Name = "ffmpeg / ffprobe";     Test = { Test-Ffmpeg };       Install = { Install-Ffmpeg };       Quick = $true }
    @{ Name = "deno";                 Test = { Test-Deno };         Install = { Install-Deno };         Quick = $true }
    @{ Name = "Node.js";              Test = { Test-Node };         Install = { Install-Node };         Quick = $true }
    @{ Name = "Firefox";              Test = { Test-Firefox };      Install = { Install-Firefox };      Quick = $true }
    @{ Name = "POT 服务端";           Test = { Test-Pot };          Install = { Install-Pot };          Quick = $false }
    @{ Name = "Whisper 虚拟环境";     Test = { Test-WhisperVenv };  Install = { Install-WhisperVenv };  Quick = $false }
    @{ Name = "Scrapling 虚拟环境";   Test = { Test-ScraplingVenv };Install = { Install-ScraplingVenv };Quick = $false }
    @{ Name = "浏览器内核";           Test = { Test-Playwright };   Install = { $null };                Quick = $false }
)

Write-Step "第 1 步：检查本机 9 项依赖"
foreach ($item in $checks) {
    if ($Mode -eq "Quick" -and -not $item.Quick) { continue }
    $detail = & $item.Test
    if ($detail) { Write-Ok "$($item.Name) 已就绪（$detail）" }
    else { Write-Warn "$($item.Name) 缺失，待安装" }
}

Write-Step "第 2 步：安装缺失项"
foreach ($item in $checks) {
    if ($Mode -eq "Quick" -and -not $item.Quick) { continue }
    if (& $item.Test) { continue }  # 已有的不动
    if ($item.Name -eq "浏览器内核") { continue }  # 由 Scrapling 步骤一并安装
    $ok = & $item.Install
    Refresh-Path
    if ($ok) { $Script:InstalledItems += $item.Name }
    else { $Script:FailedItems += $item.Name }
}

Write-Step "第 3 步：复核 9 项依赖"
$okCount = 0
$total = 0
foreach ($item in $checks) {
    if ($Mode -eq "Quick" -and -not $item.Quick) { continue }
    $total++
    $detail = & $item.Test
    if ($detail) { $okCount++; Write-Ok "$($item.Name)：$detail" }
    else { Write-Fail "$($item.Name)：仍缺失"; if ($Script:FailedItems -notcontains $item.Name) { $Script:FailedItems += $item.Name } }
}

Write-Host ""
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "  安装汇总：$okCount / $total 项就绪（模式：$Mode）" -ForegroundColor Cyan
if ($Script:InstalledItems.Count -gt 0) { Write-Host "  本次新装：$($Script:InstalledItems -join '、')" -ForegroundColor Green }
if ($Script:FailedItems.Count -gt 0) {
    Write-Host "  仍缺失：$($Script:FailedItems -join '、')" -ForegroundColor Yellow
    Write-Host "  建议：检查网络后重跑一次；仍失败请按 README 第 3 节手动安装对应项。" -ForegroundColor Yellow
} else {
    Write-Host "  全部就绪。回到素材工具箱，点「重新扫描 9 项依赖」确认即可。" -ForegroundColor Green
}
Write-Host "==================================================" -ForegroundColor Cyan

if (Test-Path $TempRoot) { Remove-Item $TempRoot -Recurse -Force -ErrorAction SilentlyContinue }
if ($Script:FailedItems.Count -gt 0) { exit 1 }
exit 0
