@echo off
chcp 65001 >nul
setlocal
title video summary - yt-dlp + Whisper
set "HERE=%~dp0"
set "PY=%LOCALAPPDATA%\Programs\whisper\venv\Scripts\python.exe"
if exist "%LOCALAPPDATA%\Programs\yt-dlp\yt-dlp.exe" set "PATH=%LOCALAPPDATA%\Programs\yt-dlp;%PATH%"
if exist "%LOCALAPPDATA%\Programs\ffmpeg\bin\ffmpeg.exe" set "PATH=%LOCALAPPDATA%\Programs\ffmpeg\bin;%PATH%"
if exist "%LOCALAPPDATA%\Programs\deno\deno.exe" set "PATH=%LOCALAPPDATA%\Programs\deno;%PATH%"

if not exist "%PY%" goto :noinstall

echo ==================================================
echo   Video to transcript to SUMMARY
echo   engine: yt-dlp (download) + Whisper (ASR)
echo   output: %HERE%out
echo ==================================================
echo.

if not "%~1"=="" goto :args

:ask
set "TARGET="
set /p "TARGET=Paste a URL, or drag a media file here (empty = quit): "
if not defined TARGET goto :end
set "MODE="
set /p "MODE=Summary mode [1=local rules, 2=AI via llm_config.txt, 3=transcript only] (default 1): "
if not defined MODE set "MODE=1"
set "MODEL="
set /p "MODEL=Model tiny/base/small (default base): "
if not defined MODEL set "MODEL=base"
set "LANG="
set /p "LANG=Language zh/en, empty = auto: "
goto :run

:args
set "TARGET=%~1"
set "MODE=%~2"
set "MODEL=%~3"
if not defined MODE set "MODE=1"
if not defined MODEL set "MODEL=base"
set "LANG=%~4"

:run
echo.
echo Target : %TARGET%
echo Model  : %MODEL%
echo Mode   : %MODE%  (1 local / 2 AI / 3 transcript only)
echo.

set "EXTRA="
if "%MODE%"=="2" set "EXTRA="
if "%MODE%"=="1" set "EXTRA=--no-llm"
if "%MODE%"=="3" set "EXTRA=--no-summary"

set "LANGARG="
if defined LANG set "LANGARG=--language %LANG%"

if "%MODE%"=="2" if not exist "%HERE%llm_config.txt" (
  echo   [!] llm_config.txt not found.
  echo       Copy llm_config.sample.txt to llm_config.txt and fill in KEY/BASE/MODEL.
  echo       Falling back to local rules for now.
  set "EXTRA=--no-llm"
)

"%PY%" "%HERE%pipeline.py" "%TARGET%" --model %MODEL% %LANGARG% %EXTRA%
echo.
echo Files are in: %HERE%out
echo   *_full.md  = summary + timeline + full text
echo   *.srt      = subtitles
echo.
pause
exit /b 0

:end
exit /b 0

:noinstall
echo   [X] Whisper venv not found:
echo       %PY%
echo       See README.md for the install commands.
pause
exit /b 1
