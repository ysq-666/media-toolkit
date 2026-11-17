@echo off
chcp 65001 >nul
setlocal
rem add known install dirs to PATH (Explorer launches may miss them)
if exist "%LOCALAPPDATA%\Programs\yt-dlp\yt-dlp.exe" set "PATH=%LOCALAPPDATA%\Programs\yt-dlp;%PATH%"
if exist "%LOCALAPPDATA%\Programs\ffmpeg\bin\ffmpeg.exe" set "PATH=%LOCALAPPDATA%\Programs\ffmpeg\bin;%PATH%"
if exist "%LOCALAPPDATA%\Programs\deno\deno.exe" set "PATH=%LOCALAPPDATA%\Programs\deno;%PATH%"
title check AI summary config
set "PY=%LOCALAPPDATA%\Programs\whisper\venv\Scripts\python.exe"
set "HERE=%~dp0"

if not exist "%PY%" goto :noinstall

echo ==================================================
echo   Check the AI summary config (llm_config.txt)
echo ==================================================
echo.
if not exist "%HERE%llm_config.txt" (
  echo   [!] llm_config.txt not found.
  echo       Copy llm_config.sample.txt to llm_config.txt and fill in KEY / BASE / MODEL.
  echo.
  pause
  exit /b 1
)

"%PY%" "%HERE%pipeline.py" --check-llm dummy
echo.
pause
exit /b 0

:noinstall
echo   [X] Whisper venv not found: %PY%
pause
exit /b 1
