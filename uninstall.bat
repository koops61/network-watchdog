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
    powershell -Command "Start-Process cmd -ArgumentList '/c \"\"%~dp0uninstall.bat\"\"' -Verb RunAs"
    exit /b
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1"

echo.
pause
