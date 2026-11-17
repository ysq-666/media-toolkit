@echo off
chcp 65001 >nul
setlocal
rem add known install dirs to PATH (Explorer launches may miss them)
if exist "%LOCALAPPDATA%\Programs\yt-dlp\yt-dlp.exe" set "PATH=%LOCALAPPDATA%\Programs\yt-dlp;%PATH%"
if exist "%LOCALAPPDATA%\Programs\ffmpeg\bin\ffmpeg.exe" set "PATH=%LOCALAPPDATA%\Programs\ffmpeg\bin;%PATH%"
if exist "%LOCALAPPDATA%\Programs\deno\deno.exe" set "PATH=%LOCALAPPDATA%\Programs\deno;%PATH%"
title scrapling - fetch a web page
set "HERE=%~dp0"
set "SCP=%LOCALAPPDATA%\Programs\scrapling\venv\Scripts\scrapling.exe"
set "OUTDIR=%HERE%output"

if not exist "%SCP%" goto :noinstall
if not exist "%OUTDIR%" mkdir "%OUTDIR%" >nul 2>nul

echo ==================================================
echo   Scrapling page fetcher
echo   Output folder: %OUTDIR%
echo   Modes: 1 = fast HTTP (TLS impersonation, no browser)
echo          2 = browser / JavaScript rendering
echo          3 = browser + solve Cloudflare (slow, 1-3 min)
echo ==================================================
echo.

if not "%~1"=="" goto :args

:ask
set "URL="
set /p "URL=Paste URL (empty = quit): "
if not defined URL goto :end
set "MODE="
set /p "MODE=Mode [1/2/3] (default 1): "
if not defined MODE set "MODE=1"
set "SEL="
set /p "SEL=CSS selector (optional, e.g. .quote): "
set "LOOP=1"
goto :run

:args
set "URL=%~1"
set "MODE=%~2"
if not defined MODE set "MODE=1"
set "SEL=%~3"
set "LOOP=0"

:run
set "OUTFILE=%OUTDIR%\page_%RANDOM%.md"
echo.
echo Fetching: %URL%
if "%MODE%"=="3" goto :cf
if "%MODE%"=="2" goto :browser

:fast
if defined SEL (
  "%SCP%" extract get "%URL%" "%OUTFILE%" --css-selector "%SEL%"
) else (
  "%SCP%" extract get "%URL%" "%OUTFILE%"
)
goto :done

:browser
if defined SEL (
  "%SCP%" extract fetch "%URL%" "%OUTFILE%" --css-selector "%SEL%" --network-idle
) else (
  "%SCP%" extract fetch "%URL%" "%OUTFILE%" --network-idle
)
goto :done

:cf
if defined SEL (
  "%SCP%" extract fetch "%URL%" "%OUTFILE%" --css-selector "%SEL%" --solve-cloudflare --network-idle --timeout 180000
) else (
  "%SCP%" extract fetch "%URL%" "%OUTFILE%" --solve-cloudflare --network-idle --timeout 180000
)

:done
echo.
if not exist "%OUTFILE%" goto :failed
echo   [OK] saved: %OUTFILE%
echo.
if "%LOOP%"=="1" goto :ask
goto :end

:failed
echo   [X] no output produced. Check the URL / selector, or run the env-check script.
goto :end

:end
echo Done.
pause
exit /b 0

:noinstall
echo   [X] scrapling not found at:
echo       %SCP%
echo       Run the installer again, or check the README.
pause
exit /b 1
