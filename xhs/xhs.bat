@echo off
chcp 65001 >nul
setlocal
rem add known install dirs to PATH (Explorer launches may miss them)
if exist "%LOCALAPPDATA%\Programs\yt-dlp\yt-dlp.exe" set "PATH=%LOCALAPPDATA%\Programs\yt-dlp;%PATH%"
if exist "%LOCALAPPDATA%\Programs\ffmpeg\bin\ffmpeg.exe" set "PATH=%LOCALAPPDATA%\Programs\ffmpeg\bin;%PATH%"
if exist "%LOCALAPPDATA%\Programs\deno\deno.exe" set "PATH=%LOCALAPPDATA%\Programs\deno;%PATH%"
title xiaohongshu downloader
set "HERE=%~dp0"

set "OUT=%USERPROFILE%\Pictures\xhs"
if exist "%HERE%OUT.txt" for /f "usebackq delims=" %%p in ("%HERE%OUT.txt") do set "OUT=%%p"
if not "%XHS_OUT%"=="" set "OUT=%XHS_OUT%"
if not exist "%OUT%" mkdir "%OUT%" >nul 2>nul

where node >nul 2>nul || goto :nonode

echo ==================================================
echo   Xiaohongshu downloader  (images + text of a note)
echo   Output: %OUT%
echo   Usage : drag a link onto this .bat, or run and paste a link
echo   Keep it serial: parallel runs get rate-limited instantly.
echo ==================================================
echo.

rem login state: Firefox live cookies first, cookies.txt only as fallback
if exist "%HERE%cookies.txt" goto :cookok
echo   [i] Using Firefox live cookies. Make sure you are logged into
echo       xiaohongshu.com in Firefox (you should see your avatar there).
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
node "%HERE%xhs.js" "%~1" "%OUT%"
if errorlevel 3 (
  echo.
  echo   [i] Rate limited by Xiaohongshu. Waiting 180s, then retrying once ...
  ping -n 181 127.0.0.1 >nul
  node "%HERE%xhs.js" "%~1" "%OUT%"
)
echo.
exit /b 0

:end
echo   Done. Serial + 1-2s gap is safe; parallel requests get blocked instantly.
echo.
pause
exit /b 0

:nonode
echo   [X] node not found in PATH.
pause
exit /b 1
