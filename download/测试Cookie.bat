@echo off
setlocal
rem add known install dirs to PATH (Explorer launches may miss them)
if exist "%LOCALAPPDATA%\Programs\yt-dlp\yt-dlp.exe" set "PATH=%LOCALAPPDATA%\Programs\yt-dlp;%PATH%"
if exist "%LOCALAPPDATA%\Programs\ffmpeg\bin\ffmpeg.exe" set "PATH=%LOCALAPPDATA%\Programs\ffmpeg\bin;%PATH%"
if exist "%LOCALAPPDATA%\Programs\deno\deno.exe" set "PATH=%LOCALAPPDATA%\Programs\deno;%PATH%"
title yt-dlp - cookies.txt test

set "CK=%~dp0cookies.txt"

echo ==================================================
echo   cookies.txt check
echo   Looking for: %CK%
echo ==================================================
echo.

if not exist "%CK%" goto :missing

echo [1/2] parsing cookies.txt ...
yt-dlp --cookies "%CK%" --simulate --print "%%(title)s" "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
if errorlevel 1 goto :bad

echo.
echo [2/2] trying a video that normally needs a login (the bot-check one) ...
yt-dlp --cookies "%CK%" --simulate --print "%%(title)s" "https://www.youtube.com/watch?v=jNQXAC9IVRw"
if errorlevel 1 goto :nobot

echo.
echo   [PASS] cookies work, including videos that need a login session.
echo          The download scripts pick this file up automatically.
echo.
pause
exit /b 0

:nobot
echo.
echo   [PARTIAL] cookies.txt is readable, but YouTube still refuses.
echo             Most likely you exported cookies while NOT logged in.
echo             Log into YouTube in the browser first, export again.
echo.
pause
exit /b 1

:bad
echo.
echo   [FAIL] cookies.txt is not readable as a Netscape cookie file.
echo          Re-export it with the extension, do not edit it by hand.
echo.
pause
exit /b 1

:missing
echo   [i] No cookies.txt in this folder.
echo.
echo   How to create one (needed for: bot-check / login-only / member videos):
echo     1. Install the Chrome or Edge extension "Get cookies.txt LOCALLY"
echo     2. Open youtube.com in that browser and make sure you are logged in
echo     3. Click the extension icon - Export - save as: cookies.txt
echo     4. Put cookies.txt in THIS folder:
echo            %~dp0
echo     5. Run this script again to verify
echo.
echo   Note: --cookies-from-browser often fails with "Could not copy Chrome
echo   cookie database" while the browser is running. cookies.txt avoids that.
echo.
pause
exit /b 0
