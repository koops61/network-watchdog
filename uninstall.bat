@echo off
chcp 65001 >nul
title Desinstallation de Network Watchdog
echo ==============================================================================
echo        DESINSTALLATION DU DEMARRAGE AUTOMATIQUE - NETWORK WATCHDOG
echo ==============================================================================
echo.

net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [INFO] Demande d'elevation des privileges Administrateur requise...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -WorkingDirectory '%~dp0' -Verb RunAs"
    exit /b
)

cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1"

echo.
pause
