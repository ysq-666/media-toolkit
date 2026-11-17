@echo off
chcp 65001 >nul
setlocal
title 一键安装环境依赖
set "HERE=%~dp0"
echo ==================================================
echo   素材工具包 · 一键安装环境依赖（完整模式）
echo   缺什么装什么，已有的不动；全部装到当前用户目录，不需要管理员权限。
echo   完整模式约 2 GB、20 分钟以上；只要下载链可用，请改用：
echo     powershell -ExecutionPolicy Bypass -File "%HERE%一键安装环境依赖.ps1" -Mode Quick
echo ==================================================
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%一键安装环境依赖.ps1" -Mode Full
echo.
pause
