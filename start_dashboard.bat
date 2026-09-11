@echo off
chcp 65001 >nul
title Network Watchdog - Tableau de Bord
echo ==============================================================================
echo        LANCEMENT DU TABLEAU DE BORD WEB - NETWORK WATCHDOG
echo ==============================================================================
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0start_dashboard.ps1"

pause
