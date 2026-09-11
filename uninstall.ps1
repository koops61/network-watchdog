# ==============================================================================
# Script de Désinstallation de Network Watchdog
# ==============================================================================
[CmdletBinding()]
param()

Set-Location $PSScriptRoot

$TaskName = "NetworkWatchdog"

$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
    Write-Host "[ERREUR] Ce script necessite les privileges Administrateur." -ForegroundColor Red
    exit 1
}

Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "       DESINSTALLATION DE NETWORK WATCHDOG" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host ""

$ExistingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($ExistingTask) {
    Write-Host "Arret de la tâche planifiee..." -ForegroundColor Yellow
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    
    Write-Host "Suppression de la tâche planifiee..." -ForegroundColor Yellow
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "[SUCCES] La tâche planifiee a ete retiree de Windows." -ForegroundColor Green
} else {
    Write-Host "[INFO] Aucune tâche nommee '$TaskName' n'a ete trouvee." -ForegroundColor Gray
}

# Tuer tout processus powershell exécutant network_watchdog.ps1 ou NetworkWatchdog.exe
Get-Process -Name "NetworkWatchdog" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

$Procs = Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like "*network_watchdog.ps1*" }
if ($Procs) {
    Write-Host "Arret des processus residuels du watchdog..." -ForegroundColor Yellow
    foreach ($p in $Procs) {
        Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
    }
    Write-Host "[OK] Processus arretes." -ForegroundColor Green
}

Write-Host ""
Write-Host "[FIN] Desinstallation terminee avec succes." -ForegroundColor Green
Write-Host "==============================================================================" -ForegroundColor Cyan
