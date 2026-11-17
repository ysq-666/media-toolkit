@echo off
setlocal
rem add known install dirs to PATH (Explorer launches may miss them)
if exist "%LOCALAPPDATA%\Programs\yt-dlp\yt-dlp.exe" set "PATH=%LOCALAPPDATA%\Programs\yt-dlp;%PATH%"
if exist "%LOCALAPPDATA%\Programs\ffmpeg\bin\ffmpeg.exe" set "PATH=%LOCALAPPDATA%\Programs\ffmpeg\bin;%PATH%"
if exist "%LOCALAPPDATA%\Programs\deno\deno.exe" set "PATH=%LOCALAPPDATA%\Programs\deno;%PATH%"
title yt-dlp - use Firefox live cookies everywhere
set "CFG=%APPDATA%\yt-dlp\config"
set "LINE=--cookies-from-browser firefox"

echo ==================================================
echo   Make every yt-dlp run use Firefox's live cookies
echo   Config: %CFG%
echo ==================================================
echo.

if not exist "%APPDATA%\yt-dlp" mkdir "%APPDATA%\yt-dlp" >nul 2>nul

if exist "%CFG%" (
  find /i "cookies-from-browser" "%CFG%" >nul 2>nul
  if not errorlevel 1 goto :already
  copy /y "%CFG%" "%CFG%.bak" >nul
  echo [i] existing config backed up to %CFG%.bak
)

>> "%CFG%" echo %LINE%
echo [OK] added: %LINE%
echo.
echo   Effect: yt-dlp (and all the .bat scripts) now read cookies straight
echo   from Firefox every run, so nothing goes stale.
echo   Prerequisite: be logged into youtube.com in Firefox.
echo.
echo   Undo: open the config file and delete that line, or run
echo         the uninstall-config script.
echo.
pause
exit /b 0

:already
echo [i] config already contains a cookies-from-browser line - nothing changed.
echo     Edit %CFG% if you want to switch browsers (chrome / edge / firefox).
echo.
pause
exit /b 0
