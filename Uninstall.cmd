@echo off
chcp 65001 >nul
title PBZ Perfect Heal - Uninstall
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\uninstall.ps1"
echo.
pause
