@echo off
chcp 65001 >nul
setlocal
rem add known install dirs to PATH (Explorer launches may miss them)
if exist "%LOCALAPPDATA%\Programs\yt-dlp\yt-dlp.exe" set "PATH=%LOCALAPPDATA%\Programs\yt-dlp;%PATH%"
if exist "%LOCALAPPDATA%\Programs\ffmpeg\bin\ffmpeg.exe" set "PATH=%LOCALAPPDATA%\Programs\ffmpeg\bin;%PATH%"
if exist "%LOCALAPPDATA%\Programs\deno\deno.exe" set "PATH=%LOCALAPPDATA%\Programs\deno;%PATH%"
title yt-dlp - merge per-site cookie exports
set "HERE=%~dp0"
set "SRC=%HERE%cookies-src"
set "OUT=%HERE%cookies.txt"

echo ==================================================
echo   Merge per-site cookie exports into one cookies.txt
echo   Drop folder: %SRC%
echo   Output     : %OUT%
echo ==================================================
echo.

where node >nul 2>nul || goto :nonode
if not exist "%SRC%" mkdir "%SRC%" >nul 2>nul

echo   Steps:
echo     1. Export cookies of each site with the extension
echo        (one .txt per site, any file name)
echo     2. Put all of them into:  %SRC%
echo     3. Run this script
echo.

node "%HERE%merge-cookies.js" "%SRC%" "%OUT%"
if errorlevel 1 goto :failed

echo.
echo   [OK] merged. Duplicates removed, newest entry wins.
echo   Next: run the cookie test script, then use the download scripts.
echo.
echo   Tip: the original per-site files stay untouched; you can add
echo        more sites later and re-run this script.
echo.
pause
exit /b 0

:failed
echo.
echo   [X] Merge failed. Make sure cookies-src contains at least one .txt.
echo.
pause
exit /b 1

:nonode
echo   [X] node not found in PATH.
echo.
pause
exit /b 1
