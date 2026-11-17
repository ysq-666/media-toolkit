@echo off
setlocal
rem add known install dirs to PATH (Explorer launches may miss them)
if exist "%LOCALAPPDATA%\Programs\yt-dlp\yt-dlp.exe" set "PATH=%LOCALAPPDATA%\Programs\yt-dlp;%PATH%"
if exist "%LOCALAPPDATA%\Programs\ffmpeg\bin\ffmpeg.exe" set "PATH=%LOCALAPPDATA%\Programs\ffmpeg\bin;%PATH%"
if exist "%LOCALAPPDATA%\Programs\deno\deno.exe" set "PATH=%LOCALAPPDATA%\Programs\deno;%PATH%"
title yt-dlp - set save folder

set "CFG=%~dp0OUT.txt"

echo ==================================================
echo   Set the save folder used by the .bat scripts
echo   Config file: %CFG%
echo ==================================================
echo.

if "%~1"=="" goto :ask
set "DIR=%~1"
goto :save

:ask
if exist "%CFG%" (
  set "CUR="
  set /p "CUR=" < "%CFG%"
  echo   Current folder: %CUR%
  echo.
)
echo   Tip: you can also drag a folder icon onto this .bat file.
echo        To go back to defaults, just delete OUT.txt
echo.
set "DIR="
set /p "DIR=New folder path (empty = cancel): "
if not defined DIR goto :cancel

:save
echo.
echo   Target: %DIR%
if not exist "%DIR%" mkdir "%DIR%" >nul 2>nul
if not exist "%DIR%" goto :badpath
set "DIRW=%DIR:&=^&%"
> "%CFG%" echo %DIRW%
if errorlevel 1 goto :badpath
echo   [OK] saved.
echo   All download scripts will now save into:
echo        %DIR%
echo.
echo   Undo: delete OUT.txt, or set YTDLP_OUT env var to override per-run.
echo.
pause
exit /b 0

:badpath
echo   [X] Cannot create or write that folder.
echo       Check the path, or pick another one (e.g. D:\Videos).
echo.
pause
exit /b 1

:cancel
echo.
echo   Cancelled, nothing changed.
echo.
pause
exit /b 0
