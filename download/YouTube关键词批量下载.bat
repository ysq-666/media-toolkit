@echo off
setlocal
rem add known install dirs to PATH (Explorer launches may miss them)
if exist "%LOCALAPPDATA%\Programs\yt-dlp\yt-dlp.exe" set "PATH=%LOCALAPPDATA%\Programs\yt-dlp;%PATH%"
if exist "%LOCALAPPDATA%\Programs\ffmpeg\bin\ffmpeg.exe" set "PATH=%LOCALAPPDATA%\Programs\ffmpeg\bin;%PATH%"
if exist "%LOCALAPPDATA%\Programs\deno\deno.exe" set "PATH=%LOCALAPPDATA%\Programs\deno;%PATH%"
title yt-dlp - YouTube keyword batch downloader
set "HERE=%~dp0"

set "OUT=%USERPROFILE%\Videos\yt-dlp"
if exist "%HERE%OUT.txt" for /f "usebackq delims=" %%p in ("%HERE%OUT.txt") do set "OUT=%%p"
if not "%YTDLP_OUT%"=="" set "OUT=%YTDLP_OUT%"
if not exist "%OUT%" mkdir "%OUT%" >nul 2>nul

set "ARCHIVE=%HERE%downloaded-youtube.txt"
set "CK="
if not "%YTDLP_YT_COOKIES%"=="1" goto :nocookie
if not exist "%HERE%cookies.txt" goto :nocookie
set "CK=--cookies "%~dp0cookies.txt""
goto :aftercookie

:nocookie
echo   [i] YouTube cookies are OFF by default - a stale cookies.txt makes
echo       YouTube answer with HTTP 403, which is worse than no cookies.
echo       If you exported FRESH YouTube cookies into cookies.txt, enable them with:
echo           set YTDLP_YT_COOKIES=1
echo       then run this script again (same window).
echo.

:aftercookie
where yt-dlp >nul 2>nul || goto :noytdlp

echo ==================================================
echo   YouTube keyword search + batch download
echo   Output : %OUT%
echo   History: %ARCHIVE%  (delete it to re-download)
echo ==================================================
echo.

if not "%~1"=="" goto :args

:ask
set "KW="
set /p "KW=Keyword: "
if not defined KW goto :end
set "N="
set /p "N=How many videos (default 5): "
if not defined N set "N=5"
set "MAXM="
set /p "MAXM=Max duration in minutes (empty = no limit): "
set "MODE="
set /p "MODE=1 = list only, 2 = download (default 2): "
if not defined MODE set "MODE=2"
goto :run

:args
set "KW=%~1"
set "N=%~2"
if not defined N set "N=5"
set "MAXM=%~3"
set "MODE=%~4"
if not defined MODE set "MODE=2"

:run
set /a SECS=999999999
if not defined MAXM goto :nofilter
set /a SECS=%MAXM%*60

:nofilter
echo.
echo Searching: %KW%   (top %N%)
if "%MODE%"=="1" goto :list

:download
rem ensure the PO token provider is up (silently ignored if missing)
if exist "%USERPROFILE%\bgutil-ytdlp-pot-provider\server\build\main.js" (
  netstat -ano | find ":4416" | find "LISTENING" >nul 2>nul
  if errorlevel 1 start "" /b node "%USERPROFILE%\bgutil-ytdlp-pot-provider\server\build\main.js"
)
echo Downloading to: %OUT%
echo.
yt-dlp "ytsearch%N%:%KW%" --yes-playlist -I "1:%N%" -P "%OUT%" -o "%%(uploader,channel|Unknown)s\%%(upload_date>%%Y-%%m-%%d)s - %%(title)s [%%(id)s].%%(ext)s" -f "bv*+ba/b" -S "res:1080" --merge-output-format mp4 --embed-metadata --write-thumbnail --convert-thumbnails jpg --windows-filenames --download-archive "%ARCHIVE%" --match-filter "duration < %SECS%" --ignore-errors --sleep-requests 1 --retries 10 --fragment-retries 10 -N 8 %CK%
if not errorlevel 1 goto :done

echo.
echo   [i] First pass failed. Most common reason: YouTube returns 403 for 1080p
echo       streams when the session is not logged in. Retrying with the
echo       progressive 360p format (works without login most of the time) ...
echo.
yt-dlp "ytsearch%N%:%KW%" --yes-playlist -I "1:%N%" -P "%OUT%" -o "%%(uploader,channel|Unknown)s\%%(upload_date>%%Y-%%m-%%d)s - %%(title)s [%%(id)s].%%(ext)s" -f "18/b[height<=480]" --merge-output-format mp4 --embed-metadata --windows-filenames --download-archive "%ARCHIVE%" --match-filter "duration < %SECS%" --ignore-errors --sleep-requests 1 --retries 5 --fragment-retries 5 %CK%
goto :done

:list
yt-dlp --flat-playlist --no-warnings "ytsearch%N%:%KW%" --print "%%(title)s | %%(id)s | %%(duration_string)s" --match-filter "duration < %SECS%"
goto :done

:done
echo.
echo Finished. Files: %OUT%
echo Note: if YouTube asks for a login, put cookies.txt in this folder.
echo.
pause
exit /b 0

:noytdlp
echo   [X] yt-dlp not found in PATH.
pause
exit /b 1
