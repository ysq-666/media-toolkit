@echo off
chcp 65001 >nul
setlocal
rem add known install dirs to PATH (Explorer launches may miss them)
if exist "%LOCALAPPDATA%\Programs\yt-dlp\yt-dlp.exe" set "PATH=%LOCALAPPDATA%\Programs\yt-dlp;%PATH%"
if exist "%LOCALAPPDATA%\Programs\ffmpeg\bin\ffmpeg.exe" set "PATH=%LOCALAPPDATA%\Programs\ffmpeg\bin;%PATH%"
if exist "%LOCALAPPDATA%\Programs\deno\deno.exe" set "PATH=%LOCALAPPDATA%\Programs\deno;%PATH%"
title douyin downloader
set "HERE=%~dp0"

set "OUT=%USERPROFILE%\Videos\yt-dlp"
if exist "%HERE%OUT.txt" for /f "usebackq delims=" %%p in ("%HERE%OUT.txt") do set "OUT=%%p"
if not "%YTDLP_OUT%"=="" set "OUT=%YTDLP_OUT%"
if not exist "%OUT%" mkdir "%OUT%" >nul 2>nul

where node >nul 2>nul || goto :nonode

echo ==================================================
echo   Douyin downloader  (bypasses the broken v1.0 extractor)
echo   Output: %OUT%
echo   Usage : drag a link onto this .bat, or run and paste a link
echo   Keep it serial: parallel runs get rate-limited instantly.
echo ==================================================
echo.

if exist "%HERE%cookies.txt" goto :cookok
echo   [!] No cookies.txt found. Douyin share page needs it.
echo.

:cookok
if not "%~1"=="" goto :loop

:ask
set "URL="
set /p "URL=Paste URL then Enter (empty = quit): "
if not defined URL goto :end
call :dl "%URL%"
goto :ask

:loop
if "%~1"=="" goto :end
call :dl "%~1"
shift
ping -n 3 127.0.0.1 >nul
goto :loop

:dl
node "%HERE%douyin.js" "%~1" "%OUT%"
if errorlevel 3 (
  echo.
  echo   [i] Rate limited by Douyin. Waiting 180s, then retrying once ...
  ping -n 181 127.0.0.1 >nul
  node "%HERE%douyin.js" "%~1" "%OUT%"
)
echo.
exit /b 0

:end
echo   Done. Serial + 1-2s gap is safe; 8 parallel requests get blocked instantly.
echo.
pause
exit /b 0

:nonode
echo   [X] node not found in PATH.
pause
exit /b 1
