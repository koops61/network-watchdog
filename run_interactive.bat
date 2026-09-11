@echo off
chcp 65001 >nul
title Network Watchdog - Mode Interactif
echo ==============================================================================
echo             NETWORK WATCHDOG - SURVEILLANCE & REPARATION RESEAU
echo ==============================================================================
echo.

:: Vérifier si le script est lancé en tant qu'administrateur
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [ATTENTION] Ce script n'est pas lance en tant qu'administrateur.
    echo Pour pouvoir redemarrer la carte reseau ou le PC, les droits Admin sont requis.
    echo Relance automatique avec elevation des privileges...
    echo.
    powershell -Command "Start-Process cmd -ArgumentList '/c \"\"%~dp0run_interactive.bat\"\"' -Verb RunAs"
    exit /b
)

echo [OK] Execution en tant qu'Administrateur.
echo Lancement du watchdog en mode interactif...
echo Appuyez sur Ctrl+C a tout moment pour quitter.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0network_watchdog.ps1" -Interactive

pause
