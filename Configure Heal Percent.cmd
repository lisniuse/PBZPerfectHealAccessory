@echo off
chcp 65001 >nul
title PBZ Perfect Heal - Config
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\set-heal.ps1"
echo.
pause
