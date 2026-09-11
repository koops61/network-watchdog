@echo off
chcp 65001 >nul
title Network Watchdog - Journaux en Direct
echo ==============================================================================
echo             JOURNAUX EN DIRECT (LOGS) - NETWORK WATCHDOG
echo ==============================================================================
echo.

set LOG_FILE=%~dp0logs\network_watchdog.log

if not exist "%LOG_FILE%" (
    echo [INFO] Aucun fichier de log trouve pour le moment (%LOG_FILE%).
    echo Le fichier sera cree des le premier demarrage du watchdog.
    echo.
    pause
    exit /b
)

echo Lecture en continu des dernieres lignes (Appuyez sur Ctrl+C pour quitter)...
echo.
powershell.exe -NoProfile -Command "Get-Content -Path '%LOG_FILE%' -Tail 40 -Wait -Encoding UTF8"
