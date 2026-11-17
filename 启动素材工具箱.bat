@echo off
chcp 65001 >nul
setlocal
title 素材工具包 · 工作台
set "HERE=%~dp0"
set "PY1=%LOCALAPPDATA%\Programs\whisper\venv\Scripts\python.exe"
set "PY2=%LOCALAPPDATA%\Programs\scrapling\venv\Scripts\python.exe"
if exist "%PY1%" (
    "%PY1%" "%HERE%toolkit_app.py" %*
    goto :end
)
if exist "%PY2%" (
    "%PY2%" "%HERE%toolkit_app.py" %*
    goto :end
)
python "%HERE%toolkit_app.py" %*
:end
