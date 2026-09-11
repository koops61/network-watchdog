@echo off
chcp 65001 >nul
title Installation de Network Watchdog
echo ==============================================================================
echo        INSTALLATION DU DEMARRAGE AUTOMATIQUE - NETWORK WATCHDOG
echo ==============================================================================
echo.

:: Vérifier si le script est lancé en tant qu'administrateur
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [INFO] Demande d'elevation des privileges Administrateur requise...
    powershell -Command "Start-Process cmd -ArgumentList '/c \"\"%~dp0install.bat\"\"' -Verb RunAs"
    exit /b
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"

echo.
pause
