@echo off
setlocal
rem add known install dirs to PATH (Explorer launches may miss them)
if exist "%LOCALAPPDATA%\Programs\yt-dlp\yt-dlp.exe" set "PATH=%LOCALAPPDATA%\Programs\yt-dlp;%PATH%"
if exist "%LOCALAPPDATA%\Programs\ffmpeg\bin\ffmpeg.exe" set "PATH=%LOCALAPPDATA%\Programs\ffmpeg\bin;%PATH%"
if exist "%LOCALAPPDATA%\Programs\deno\deno.exe" set "PATH=%LOCALAPPDATA%\Programs\deno;%PATH%"
title yt-dlp - batch playlist / channel

where yt-dlp >nul 2>nul || goto :noytdlp

set "OUT=%USERPROFILE%\Videos\yt-dlp-playlists"
if exist "%~dp0OUT.txt" for /f "usebackq delims=" %%p in ("%~dp0OUT.txt") do set "OUT=%%p"
if not "%YTDLP_OUT%"=="" set "OUT=%YTDLP_OUT%"
if not exist "%OUT%" mkdir "%OUT%" >nul 2>nul

set "CK="
if exist "%~dp0cookies.txt" set "CK=--cookies "%~dp0cookies.txt""

echo ==================================================
echo   yt-dlp batch downloader for playlists / channels
echo   Already-downloaded items are skipped automatically.
echo   Output : %OUT%
echo   Archive: %OUT%\archive.txt   (delete it to re-download everything)
echo   Tip    : to fetch only the first N items, change -I 1: to -I 1:N
echo ==================================================
echo.

if not "%~1"=="" goto :loop

:ask
set "URL="
set /p "URL=Paste playlist/channel URL then Enter (empty = quit): "
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
yt-dlp -P "%OUT%" -o "%%(playlist_title,channel,uploader|Playlist)s\%%(playlist_index)03d - %%(title)s [%%(id)s].%%(ext)s" -f "bv*+ba/b" -S "res:1080,vcodec:h264,acodec:aac" --merge-output-format mp4 --yes-playlist --download-archive "%OUT%\archive.txt" --ignore-errors --embed-metadata --windows-filenames --retries 10 --fragment-retries 10 --sleep-requests 1 -N 8 %CK% "%~1"
if errorlevel 1 (
  echo   [HINT] Failed. Usual causes:
  echo          - needs login: put cookies.txt in this folder
  echo          - video is private, region-locked or removed
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
