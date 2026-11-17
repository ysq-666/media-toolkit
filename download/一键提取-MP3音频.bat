@echo off
setlocal
rem add known install dirs to PATH (Explorer launches may miss them)
if exist "%LOCALAPPDATA%\Programs\yt-dlp\yt-dlp.exe" set "PATH=%LOCALAPPDATA%\Programs\yt-dlp;%PATH%"
if exist "%LOCALAPPDATA%\Programs\ffmpeg\bin\ffmpeg.exe" set "PATH=%LOCALAPPDATA%\Programs\ffmpeg\bin;%PATH%"
if exist "%LOCALAPPDATA%\Programs\deno\deno.exe" set "PATH=%LOCALAPPDATA%\Programs\deno;%PATH%"
title yt-dlp - MP3 audio extractor

where yt-dlp >nul 2>nul || goto :noytdlp

set "OUT=%USERPROFILE%\Music\yt-dlp"
if exist "%~dp0OUT.txt" for /f "usebackq delims=" %%p in ("%~dp0OUT.txt") do set "OUT=%%p"
if not "%YTDLP_OUT%"=="" set "OUT=%YTDLP_OUT%"
if not exist "%OUT%" mkdir "%OUT%" >nul 2>nul

set "CK="
if exist "%~dp0cookies.txt" set "CK=--cookies "%~dp0cookies.txt""

echo ==================================================
echo   yt-dlp audio extractor (MP3, best quality, cover art embedded)
echo   Output: %OUT%
echo ==================================================
echo.

if not "%~1"=="" goto :loop

:ask
set "URL="
set /p "URL=Paste URL then Enter (empty = quit): "
if not defined URL goto :end
call :run "%URL%"
goto :ask

:loop
if "%~1"=="" goto :end
call :run "%~1"
shift
goto :loop

:run
echo.
echo === Processing: %~1
yt-dlp -P "%OUT%" -o "%%(uploader,channel,creator|Unknown)s\%%(title)s [%%(id)s].%%(ext)s" -f "ba/b" -x --audio-format mp3 --audio-quality 0 --embed-thumbnail --embed-metadata --no-playlist --windows-filenames --retries 10 --fragment-retries 10 -N 8 %CK% "%~1"
if errorlevel 1 (
  echo   [HINT] Failed. Usual causes:
  echo          - YouTube bot-check / login needed: put cookies.txt in this folder
  echo          - video is private, region-locked or removed
  echo   See section 4.9 of the manual.
)
exit /b 0

:end
echo.
echo All done. Files are in: %OUT%
echo.
pause
exit /b 0

:noytdlp
echo [X] yt-dlp not found. Run the check-environment script, or open a new window.
echo.
pause
exit /b 1
