@echo off
chcp 65001 >nul
title Compilation de NetworkWatchdog.exe
echo ==============================================================================
echo        COMPILATION DE L'APPLICATION EXECUTABLE - NETWORK WATCHDOG
echo ==============================================================================
echo.

cd /d "%~dp0"

echo [1/3] Compilation du projet .NET 10 (Single-File Release)...
dotnet publish .\src-app\NetworkWatchdog.csproj -c Release -r win-x64 --self-contained false -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o .\dist_single

if %errorlevel% neq 0 (
    echo.
    echo [ERREUR] La compilation a echoue.
    pause
    exit /b 1
)

echo [2/3] Deploiement de NetworkWatchdog.exe et des ressources...
copy /y ".\dist_single\NetworkWatchdog.exe" ".\NetworkWatchdog.exe" >nul
xcopy /s /e /y /i ".\src-app\ui" ".\ui" >nul

echo [3/3] Nettoyage...
rmdir /s /q ".\dist_single" 2>nul
rmdir /s /q ".\dist" 2>nul

echo.
echo ==============================================================================
echo [SUCCES] NetworkWatchdog.exe a ete genere avec succes !
echo Double-cliquez sur NetworkWatchdog.exe pour lancer l'application.
echo ==============================================================================
echo.
if "%1" neq "--no-pause" pause
