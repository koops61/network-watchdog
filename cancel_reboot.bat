@echo off
chcp 65001 >nul
title Network Watchdog - Annuler le Redémarrage
echo ==============================================================================
echo             ANNULATION DU REDEMARRAGE DU PC
echo ==============================================================================
echo.
echo Tentative d'annulation du redemarrage en cours...
shutdown.exe /a

if %errorlevel% equ 0 (
    echo.
    echo [SUCCES] Le redemarrage du PC a ete annule avec succes !
) else (
    echo.
    echo [INFO] Aucun redemarrage n'etait planifie ou deja annule.
)

echo.
pause
