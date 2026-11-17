@echo off
chcp 65001 >nul
setlocal
rem add known install dirs to PATH (Explorer launches may miss them)
if exist "%LOCALAPPDATA%\Programs\yt-dlp\yt-dlp.exe" set "PATH=%LOCALAPPDATA%\Programs\yt-dlp;%PATH%"
if exist "%LOCALAPPDATA%\Programs\ffmpeg\bin\ffmpeg.exe" set "PATH=%LOCALAPPDATA%\Programs\ffmpeg\bin;%PATH%"
title whisper - environment check
set "VENV=%LOCALAPPDATA%\Programs\whisper\venv"
set "PY=%VENV%\Scripts\python.exe"

echo ==================================================
echo   Whisper environment check
echo ==================================================
echo.

echo [1/4] python + packages
if not exist "%PY%" (
  echo    [X] venv missing: %VENV%
  goto :end
)
"%PY%" -c "import sys, whisper, torch; print('   python', sys.version.split()[0]); print('   whisper', whisper.__version__); print('   torch', torch.__version__, '| cuda:', torch.cuda.is_available())"
echo.

echo [2/4] external tools
where yt-dlp >nul 2>nul
if errorlevel 1 (echo    [X] yt-dlp missing) else (echo    [OK] yt-dlp in PATH)

where ffmpeg >nul 2>nul
if errorlevel 1 goto :noffmpeg
rem do not pipe ffmpeg output in cmd (it can block); read it from a temp file instead
ffmpeg -version > "%TEMP%\wh_ffver.txt" 2>&1
set "FFV="
set /p "FFV=" < "%TEMP%\wh_ffver.txt"
del /q "%TEMP%\wh_ffver.txt" >nul 2>nul
if not defined FFV goto :noffmpeg
echo    %FFV%
goto :ffdone

:noffmpeg
echo    [X] ffmpeg missing (needed to decode audio)

:ffdone
echo.

echo [3/4] model cache (~/.cache/whisper)
if exist "%USERPROFILE%\.cache\whisper" (
  dir /b "%USERPROFILE%\.cache\whisper"
) else (
  echo    empty - first run will download the model
)
echo.

echo [4/4] notes
echo    - CPU mode only (torch 2.x cpu build). GPU would need a CUDA torch wheel ~2.5 GB.
echo    - model sizes: tiny 75MB / base 145MB / small 484MB / medium 1.5GB
echo    - speed on this CPU: roughly 1-3x realtime for base, slower for small.
echo.

:end
echo Reinstall commands:
echo    python -m venv "%VENV%"
echo    "%VENV%\Scripts\python.exe" -m pip install openai-whisper
echo.
pause
