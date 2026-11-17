@echo off
chcp 65001 >nul
setlocal
rem add known install dirs to PATH (Explorer launches may miss them)
if exist "%LOCALAPPDATA%\Programs\yt-dlp\yt-dlp.exe" set "PATH=%LOCALAPPDATA%\Programs\yt-dlp;%PATH%"
if exist "%LOCALAPPDATA%\Programs\ffmpeg\bin\ffmpeg.exe" set "PATH=%LOCALAPPDATA%\Programs\ffmpeg\bin;%PATH%"
if exist "%LOCALAPPDATA%\Programs\deno\deno.exe" set "PATH=%LOCALAPPDATA%\Programs\deno;%PATH%"
title scrapling - environment check
set "VENV=%LOCALAPPDATA%\Programs\scrapling\venv"
set "SCP=%VENV%\Scripts\scrapling.exe"
set "PY=%VENV%\Scripts\python.exe"
set "PW=%LOCALAPPDATA%\ms-playwright"

echo ==================================================
echo   Scrapling environment check
echo ==================================================
echo.

echo [1/4] scrapling
if not exist "%SCP%" (
  echo    [X] not installed at %VENV%
  goto :end
)
echo    [OK] version:
"%SCP%" --version
echo.

echo [2/4] python and key packages
"%PY%" -c "import sys, scrapling, curl_cffi, lxml, playwright, patchright; print('   python', sys.version.split()[0]); print('   scrapling', scrapling.__version__); print('   curl_cffi', curl_cffi.__version__); print('   lxml', lxml.__version__); print('   playwright', playwright.__version__ if hasattr(playwright,'__version__') else 'ok'); print('   patchright', 'ok')"
echo.

echo [3/4] browsers (patchright needs chromium-1248, playwright uses chromium-1255)
if exist "%PW%\chromium-1248" (echo    [OK] chromium-1248  ^(patchright / StealthyFetcher^)) else (echo    [X] chromium-1248 missing: run  patchright install chromium)
if exist "%PW%\chromium-1255" (echo    [OK] chromium-1255  ^(playwright^)) else (echo    [-] chromium-1255 missing)
echo.

echo [4/4] disk usage
for /f "usebackq" %%s in (`powershell -NoProfile -Command "'{0:N0}' -f ((Get-ChildItem '%PW%' -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum/1MB)"`) do echo    browsers: %%s MB
echo    note: browser mode is optional; HTTP mode needs no browser at all.
echo.

:end
echo If something is missing: reinstall with
echo    python -m venv "%VENV%"
echo    "%VENV%\Scripts\python.exe" -m pip install "scrapling[fetchers,shell]"
echo    "%VENV%\Scripts\scrapling.exe" install
echo    "%VENV%\Scripts\python.exe" -m patchright install chromium
echo.
pause
