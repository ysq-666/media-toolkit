@echo off
setlocal
rem add known install dirs to PATH (Explorer launches may miss them)
if exist "%LOCALAPPDATA%\Programs\yt-dlp\yt-dlp.exe" set "PATH=%LOCALAPPDATA%\Programs\yt-dlp;%PATH%"
if exist "%LOCALAPPDATA%\Programs\ffmpeg\bin\ffmpeg.exe" set "PATH=%LOCALAPPDATA%\Programs\ffmpeg\bin;%PATH%"
if exist "%LOCALAPPDATA%\Programs\deno\deno.exe" set "PATH=%LOCALAPPDATA%\Programs\deno;%PATH%"
title yt-dlp - YouTube cookie check
set "HERE=%~dp0"
set "CK=%HERE%cookies.txt"

echo ==================================================
echo   Is your cookies.txt actually usable on YouTube?
echo   File: %CK%
echo ==================================================
echo.

where yt-dlp >nul 2>nul || goto :noytdlp
if not exist "%CK%" goto :nofile

echo [1/3] any YouTube cookies in the file?
type "%CK%" 2>nul | find /i ".youtube.com" >nul 2>nul
if errorlevel 1 goto :noucookies
echo    [OK] found .youtube.com entries
echo.

echo [2/3] does YouTube accept them? (probing a video that REQUIRES login)
yt-dlp --cookies "%CK%" --simulate --no-warnings --print "    [PASS] title: %%(title).40s" "https://www.youtube.com/watch?v=9bZkp7q19f0"
if errorlevel 1 goto :stale
echo.
echo    [PASS] cookies are live - YouTube accepts them.
echo    Use them with:  set YTDLP_YT_COOKIES=1  then run the batch script.
echo.
pause
exit /b 0

:stale
echo    [FAIL] YouTube rejected the request. Two possibilities:
echo      - cookies expired / rotated (most common)
echo      - this IP is flagged harder than cookies can fix
echo.
echo    How to refresh: log into youtube.com in Chrome/Edge, then re-export
echo    cookies.txt (run the export-all-cookies script after closing the browser).
echo.
echo [3/3] control test: a video that does NOT need login
yt-dlp --simulate --no-warnings --print "    [control] title: %%(title).40s" "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
echo.
echo    If the control line printed a title, the tool itself is fine and the
echo    problem is the cookie/IP side. If it also failed, YouTube is blocking
echo    the whole IP right now - wait a few minutes and retry.
echo.
pause
exit /b 1

:noucookies
echo    [X] No .youtube.com entries in cookies.txt.
echo        Your export did not include YouTube (not logged in at export time?).
echo.
pause
exit /b 1

:nofile
echo    [X] cookies.txt not found in this folder.
echo        Export it first: log into YouTube, then run the export-all-cookies script.
echo.
pause
exit /b 1

:noytdlp
echo    [X] yt-dlp not found in PATH.
pause
exit /b 1
