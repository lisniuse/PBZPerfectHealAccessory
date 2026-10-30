@echo off
chcp 65001 >nul
title PBZ Perfect Heal - Install
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\install.ps1"
echo.
pause
