@echo off
setlocal
rem add known install dirs to PATH (Explorer launches may miss them)
if exist "%LOCALAPPDATA%\Programs\yt-dlp\yt-dlp.exe" set "PATH=%LOCALAPPDATA%\Programs\yt-dlp;%PATH%"
if exist "%LOCALAPPDATA%\Programs\ffmpeg\bin\ffmpeg.exe" set "PATH=%LOCALAPPDATA%\Programs\ffmpeg\bin;%PATH%"
if exist "%LOCALAPPDATA%\Programs\deno\deno.exe" set "PATH=%LOCALAPPDATA%\Programs\deno;%PATH%"
title yt-dlp - uninstall global config

set "DST=%APPDATA%\yt-dlp\config"

echo ==================================================
echo   Remove yt-dlp global config
echo ==================================================
echo.

if not exist "%DST%" (
  echo [i] no global config present, nothing to do.
  echo.
  pause
  exit /b 0
)

if exist "%DST%.bak" (
  copy /y "%DST%.bak" "%DST%" >nul
  echo [OK] restored previous config from backup.
) else (
  del /q "%DST%"
  echo [OK] config deleted, yt-dlp is back to defaults.
)

echo.
pause
