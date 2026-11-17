@echo off
setlocal
rem add known install dirs to PATH (Explorer launches may miss them)
if exist "%LOCALAPPDATA%\Programs\yt-dlp\yt-dlp.exe" set "PATH=%LOCALAPPDATA%\Programs\yt-dlp;%PATH%"
if exist "%LOCALAPPDATA%\Programs\ffmpeg\bin\ffmpeg.exe" set "PATH=%LOCALAPPDATA%\Programs\ffmpeg\bin;%PATH%"
if exist "%LOCALAPPDATA%\Programs\deno\deno.exe" set "PATH=%LOCALAPPDATA%\Programs\deno;%PATH%"
title yt-dlp - PO Token provider
set "SRV=%USERPROFILE%\bgutil-ytdlp-pot-provider\server"
set "NODE=node"

echo ==================================================
echo   bgutil PO Token provider (yt-dlp plugin backend)
echo   Server: %SRV%\build\main.js
echo   Port  : 127.0.0.1:4416
echo ==================================================
echo.

if not exist "%SRV%\build\main.js" goto :nobuild
where node >nul 2>nul || goto :nonode

netstat -ano | find ":4416" | find "LISTENING" >nul 2>nul
if not errorlevel 1 goto :already

echo Starting server in background ...
start "" /b %NODE% "%SRV%\build\main.js"
ping -n 4 127.0.0.1 >nul
netstat -ano | find ":4416" | find "LISTENING" >nul 2>nul
if errorlevel 1 goto :failed

echo   [OK] server is listening on 127.0.0.1:4416
echo   yt-dlp will now generate PO tokens automatically.
echo   Keep this session open? No - the server keeps running in the background.
echo   Stop it later with  taskkill /IM node.exe  (or reboot).
echo.
pause
exit /b 0

:already
echo   [OK] server already running on port 4416. Nothing to do.
echo.
pause
exit /b 0

:failed
echo   [X] server did not start. Try manually:
echo       node "%SRV%\build\main.js"
echo.
pause
exit /b 1

:nobuild
echo   [X] build not found. Rebuild with:
echo       cd /d "%SRV%"
echo       npm ci
echo       npx tsc
echo.
pause
exit /b 1

:nonode
echo   [X] node not found in PATH.
echo.
pause
exit /b 1
