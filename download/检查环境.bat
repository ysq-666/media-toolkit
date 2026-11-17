@echo off
setlocal
rem add known install dirs to PATH (Explorer launches may miss them)
if exist "%LOCALAPPDATA%\Programs\yt-dlp\yt-dlp.exe" set "PATH=%LOCALAPPDATA%\Programs\yt-dlp;%PATH%"
if exist "%LOCALAPPDATA%\Programs\ffmpeg\bin\ffmpeg.exe" set "PATH=%LOCALAPPDATA%\Programs\ffmpeg\bin;%PATH%"
if exist "%LOCALAPPDATA%\Programs\deno\deno.exe" set "PATH=%LOCALAPPDATA%\Programs\deno;%PATH%"
title yt-dlp - environment check
echo ==================================================
echo   yt-dlp environment check
echo ==================================================
echo.

echo [1/4] yt-dlp
where yt-dlp >nul 2>nul
if errorlevel 1 (
  echo    [X] yt-dlp not in PATH
  if exist "%LOCALAPPDATA%\Programs\yt-dlp\yt-dlp.exe" (
    echo        but the exe exists, calling it directly:
    "%LOCALAPPDATA%\Programs\yt-dlp\yt-dlp.exe" --version
  )
) else (
  echo    [OK] version:
  yt-dlp --version
)
echo.

echo [2/4] ffmpeg
where ffmpeg >nul 2>nul
if errorlevel 1 goto :noffmpeg
ffmpeg -version > "%TEMP%\ytdlp_ffver.txt" 2>&1
set "FFVER="
set /p "FFVER=" < "%TEMP%\ytdlp_ffver.txt"
del /q "%TEMP%\ytdlp_ffver.txt" >nul 2>nul
if not defined FFVER goto :noffmpegver
echo    [OK] %FFVER%
goto :js

:noffmpegver
echo    [X] ffmpeg exists but call failed
goto :js

:noffmpeg
echo    [X] ffmpeg not in PATH - merging audio+video will fail

:js
echo.
echo [3/4] JavaScript runtime (needed for high-quality YouTube)
where node >nul 2>nul
if errorlevel 1 (echo    [-] node not found) else (echo    [OK] node & node --version)
where deno >nul 2>nul
if errorlevel 1 (echo    [-] deno not found, optional) else (echo    [OK] deno & deno --version)
echo.

echo [4/4] config and folders
if exist "%APPDATA%\yt-dlp\config" (echo    [OK] global config active: %APPDATA%\yt-dlp\config) else (echo    [-] no global config, run install-config script to enable)
if exist "%~dp0cookies.txt" (echo    [OK] cookies.txt found, scripts will use it) else (echo    [-] no cookies.txt, YouTube bot-check may block some videos)
set "OD="
if not exist "%~dp0OUT.txt" goto :defout
set /p "OD=" < "%~dp0OUT.txt"
echo    [OK] custom output folder: %OD%
goto :outhint

:defout
echo    [-] default output folder: %USERPROFILE%\Videos\yt-dlp

:outhint
echo.

echo If any [X] shows up: close this window and open it again.
echo Still broken? See section 7 of the manual.
echo.
pause
