@echo off
setlocal
rem add known install dirs to PATH (Explorer launches may miss them)
if exist "%LOCALAPPDATA%\Programs\yt-dlp\yt-dlp.exe" set "PATH=%LOCALAPPDATA%\Programs\yt-dlp;%PATH%"
if exist "%LOCALAPPDATA%\Programs\ffmpeg\bin\ffmpeg.exe" set "PATH=%LOCALAPPDATA%\Programs\ffmpeg\bin;%PATH%"
if exist "%LOCALAPPDATA%\Programs\deno\deno.exe" set "PATH=%LOCALAPPDATA%\Programs\deno;%PATH%"
title yt-dlp - install global config

set "SRC=%~dp0config.sample"
set "DSTDIR=%APPDATA%\yt-dlp"
set "DST=%DSTDIR%\config"

echo ==================================================
echo   Install yt-dlp global config
echo   Template: %SRC%
echo   Target  : %DST%
echo ==================================================
echo.

if not exist "%SRC%" (
  echo [X] config.sample not found next to this script.
  echo.
  pause
  exit /b 1
)

if not exist "%DSTDIR%" mkdir "%DSTDIR%" >nul 2>nul

if exist "%DST%" (
  set "BAK=%DST%.bak"
  echo [i] existing config backed up to:
  echo     %BAK%
  copy /y "%DST%" "%BAK%" >nul
)

copy /y "%SRC%" "%DST%" >nul
if errorlevel 1 (
  echo [X] copy failed.
  echo.
  pause
  exit /b 1
)

echo [OK] installed. Every yt-dlp run now uses these defaults.
echo      Edit it at : %DST%
echo      Ignore it  : add --ignore-config to a command
echo      Undo it    : run the uninstall-config script
echo.
pause
