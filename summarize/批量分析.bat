@echo off
chcp 65001 >nul
setlocal
title batch analyze - keyword to summary
set "HERE=%~dp0"
set "PY=%LOCALAPPDATA%\Programs\whisper\venv\Scripts\python.exe"
if exist "%LOCALAPPDATA%\Programs\yt-dlp\yt-dlp.exe" set "PATH=%LOCALAPPDATA%\Programs\yt-dlp;%PATH%"
if exist "%LOCALAPPDATA%\Programs\ffmpeg\bin\ffmpeg.exe" set "PATH=%LOCALAPPDATA%\Programs\ffmpeg\bin;%PATH%"
if exist "%LOCALAPPDATA%\Programs\deno\deno.exe" set "PATH=%LOCALAPPDATA%\Programs\deno;%PATH%"

if not exist "%PY%" goto :noinstall

echo ==================================================
echo   Batch: keyword or links  ->  download -> transcribe -> summary
echo ==================================================
echo.
echo   1 = Bilibili   (keyword search, fully automatic)
echo   2 = Douyin     (no public search API: give a links.txt)
echo   3 = Xiaohongshu(no public search API: give a links.txt)
echo.
set "MODE="
set /p "MODE=Choose [1/2/3]: "
if "%MODE%"=="1" goto :bili
if "%MODE%"=="2" goto :douyin
if "%MODE%"=="3" goto :xhs
goto :end

:bili
echo.
set "KW="
set /p "KW=Keyword: "
if not defined KW goto :end
set "N="
set /p "N=How many videos (default 3): "
if not defined N set "N=3"
set "MAXD="
set /p "MAXD=Max seconds per video (default 600): "
if not defined MAXD set "MAXD=600"
set "MODEL="
set /p "MODEL=Whisper model tiny/base/small (default small): "
if not defined MODEL set "MODEL=small"
echo.
"%PY%" "%HERE%batch_platform.py" bilibili "%KW%" --count %N% --max-duration %MAXD% --model %MODEL%
goto :done

:douyin
echo.
echo   Prepare a text file, one share link per line, then give its path.
set "FILE="
set /p "FILE=links.txt path: "
if not defined FILE goto :end
"%PY%" "%HERE%batch_platform.py" links "%FILE%" --platform douyin --model small
goto :done

:xhs
echo.
echo   Prepare a text file, one note link per line, then give its path.
set "FILE="
set /p "FILE=links.txt path: "
if not defined FILE goto :end
"%PY%" "%HERE%batch_platform.py" links "%FILE%" --platform xhs --model small
goto :done

:done
echo.
echo Output: %HERE%out
echo Open the summary file first - it lists every item and the keywords.
echo Send that file to an AI for the cross-video comparison.
echo.
pause
exit /b 0

:end
exit /b 0

:noinstall
echo   [X] whisper venv not found: %PY%
echo       Install it first (see README.md).
pause
exit /b 1
