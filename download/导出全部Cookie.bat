@echo off
chcp 65001 >nul
setlocal
rem add known install dirs to PATH (Explorer launches may miss them)
if exist "%LOCALAPPDATA%\Programs\yt-dlp\yt-dlp.exe" set "PATH=%LOCALAPPDATA%\Programs\yt-dlp;%PATH%"
if exist "%LOCALAPPDATA%\Programs\ffmpeg\bin\ffmpeg.exe" set "PATH=%LOCALAPPDATA%\Programs\ffmpeg\bin;%PATH%"
if exist "%LOCALAPPDATA%\Programs\deno\deno.exe" set "PATH=%LOCALAPPDATA%\Programs\deno;%PATH%"
title yt-dlp - export ALL cookies from browser
set "HERE=%~dp0"
set "PORT=9222"
set "OUT=%HERE%cookies.txt"
set "TMPP=%TEMP%\ytdlp-cookie-profile"

rem ---- pick browser: default Chrome, pass "edge" as argument for Edge ----
set "NAME=Chrome"
set "IMG=chrome.exe"
set "BROWSER=%ProgramFiles%\Google\Chrome\Application\chrome.exe"
set "UDD=%LOCALAPPDATA%\Google\Chrome\User Data"
if not exist "%BROWSER%" set "BROWSER=%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe"
if /i "%~1"=="edge" (
  set "NAME=Edge"
  set "IMG=msedge.exe"
  set "BROWSER=%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe"
  set "UDD=%LOCALAPPDATA%\Microsoft\Edge\User Data"
)
if not exist "%BROWSER%" goto :nobrowser
where node >nul 2>nul || goto :nonode

echo ==================================================
echo   Export ALL cookies of every site into one cookies.txt
echo   Browser: %NAME%
echo   Output : %OUT%
echo ==================================================
echo.

tasklist /fi "imagename eq %IMG%" 2>nul | find /i "%IMG%" >nul
if not errorlevel 1 goto :running

echo   [1/3] copying cookie database ...
if exist "%TMPP%" rmdir /s /q "%TMPP%" >nul 2>nul
mkdir "%TMPP%\Default\Network" >nul 2>nul
copy /y "%UDD%\Local State" "%TMPP%\Local State" >nul 2>nul
copy /y "%UDD%\Default\Network\Cookies" "%TMPP%\Default\Network\Cookies" >nul 2>nul
if not exist "%TMPP%\Default\Network\Cookies" goto :locked

echo   [2/3] starting a temporary headless browser ...
start "" /b "%BROWSER%" --headless=new --remote-debugging-port=%PORT% --user-data-dir="%TMPP%" --no-first-run --no-default-browser-check --disable-gpu about:blank

echo   [3/3] dumping cookies ...
node "%HERE%dump-cookies.js" "%OUT%"
if errorlevel 1 goto :failed

echo.
findstr /i "youtube" "%OUT%" >nul 2>nul && echo   [OK] youtube cookies present.
findstr /i "bilibili" "%OUT%" >nul 2>nul && echo   [OK] bilibili cookies present.
echo   File: %OUT%
echo   Next: run  test-cookie script  to verify, then just use the download scripts.
echo.
timeout /t 2 >nul
rmdir /s /q "%TMPP%" >nul 2>nul
pause
exit /b 0

:running
echo   [X] %NAME% is still running.
echo.
echo       Chromium locks its cookie database while running, so close it first:
echo         1. Close every %NAME% window
echo         2. Right-click the %NAME% icon in the system tray and choose "Quit"
echo            (Chrome keeps running in background otherwise)
echo         3. Run this script again
echo.
echo       Do not want to close the browser? Use per-site export instead:
echo         drag one export into the  cookies-src  folder each time,
echo         then run  merge-cookie-files script.
echo.
pause
exit /b 1

:locked
echo   [X] Could not copy the cookie database (still locked).
echo       Make sure %NAME% is fully closed, including background processes.
echo.
rmdir /s /q "%TMPP%" >nul 2>nul
pause
exit /b 1

:failed
echo.
echo   [X] Dump failed. The database may be encrypted differently.
echo       Fallback: export site by site into the  cookies-src  folder
echo       and run  merge-cookie-files script.
echo.
rmdir /s /q "%TMPP%" >nul 2>nul
pause
exit /b 1

:nobrowser
echo   [X] Neither Chrome nor Edge found.
echo.
pause
exit /b 1

:nonode
echo   [X] node not found in PATH. Install Node.js or use the merge fallback.
echo.
pause
exit /b 1
