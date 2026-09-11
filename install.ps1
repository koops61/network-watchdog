# ==============================================================================
# Script d'Installation de la Tâche Planifiée Network Watchdog
# ==============================================================================
[CmdletBinding()]
param()

Set-Location $PSScriptRoot

$TaskName = "NetworkWatchdog"
$ScriptPath = Join-Path $PSScriptRoot "network_watchdog.ps1"

# Vérification des privilèges Administrateur
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
    Write-Host "[ERREUR] Vous devez executer ce script en tant qu'Administrateur !" -ForegroundColor Red
    Write-Host "Faites un clic droit sur install.bat ou install.ps1 -> Executer en tant qu'administrateur." -ForegroundColor Yellow
    exit 1
}

Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "     INSTALLATION DU SERVICE DE DEMARRAGE : NETWORK WATCHDOG" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host ""

# 1. Vérifier que le script existe
if (-not (Test-Path $ScriptPath)) {
    Write-Host "[ERREUR] Fichier network_watchdog.ps1 introuvable a l'emplacement : $ScriptPath" -ForegroundColor Red
    exit 1
}

# 2. Supprimer la tâche si elle existe déjà et arrêter les processus en cours
$ExistingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($ExistingTask) {
    Write-Host "[INFO] Une tâche existante '$TaskName' a ete detectee. Mise a jour..." -ForegroundColor Yellow
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}
Get-Process -Name "NetworkWatchdog" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

# 3. Définir l'action
$ExePath = Join-Path $PSScriptRoot "NetworkWatchdog.exe"
if (Test-Path $ExePath) {
    Write-Host "[INFO] Configuration de la tâche avec l'application NetworkWatchdog.exe..." -ForegroundColor Cyan
    $Action = New-ScheduledTaskAction `
        -Execute $ExePath `
        -Argument "--tray" `
        -WorkingDirectory $PSScriptRoot
} else {
    Write-Host "[INFO] Configuration de la tâche avec le script PowerShell de fond..." -ForegroundColor Cyan
    $Action = New-ScheduledTaskAction `
        -Execute "powershell.exe" `
        -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptPath`"" `
        -WorkingDirectory $PSScriptRoot
}

# 4. Définir les déclencheurs (À l'ouverture de session de l'utilisateur avec privilèges élevés)
$CurrentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$TriggerLogon = New-ScheduledTaskTrigger -AtLogOn -User $CurrentUser
# Décalage de 10 secondes au logon pour laisser le système charger
$TriggerLogon.Delay = "PT10S"

# 5. Définir les paramètres d'exécution
$Settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit (New-TimeSpan -Days 0) `
    -Priority 4

# 6. Définir le principal (Privilèges Administrateurs les plus élevés, sans popup UAC)
$Principal = New-ScheduledTaskPrincipal `
    -UserId $CurrentUser `
    -LogonType Interactive `
    -RunLevel Highest

# 7. Enregistrer la tâche
try {
    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $Action `
        -Trigger $TriggerLogon `
        -Settings $Settings `
        -Principal $Principal `
        -Description "Surveille la connexion reseau au demarrage du PC, redemarre la carte reseau en cas d'instabilite ou perte et redemarre le PC avec protection anti-bootloop si la coupure persiste." | Out-Null

    Write-Host "[SUCCES] La tâche planifiee '$TaskName' a ete creee avec succes !" -ForegroundColor Green
    Write-Host "Utilisateur cible   : $CurrentUser" -ForegroundColor Cyan
    Write-Host "Niveau d'execution  : Administrateur maximal (RunLevel Highest, aucun popup UAC)" -ForegroundColor Cyan
    Write-Host "Declencheur         : Ouverture de session (AtLogOn, delai 10s)" -ForegroundColor Cyan
    Write-Host ""
    
    # 8. Démarrer la tâche immédiatement
    Write-Host "Demarrage immediat du watchdog en arriere-plan..." -ForegroundColor Cyan
    Start-ScheduledTask -TaskName $TaskName
    Start-Sleep -Seconds 2
    
    $RunningProc = Get-Process -Name "NetworkWatchdog" -ErrorAction SilentlyContinue
    if ($RunningProc) {
        Write-Host "[OK] Network Watchdog est maintenant actif en arriere-plan (PID: $($RunningProc.Id)) !" -ForegroundColor Green
        Write-Host "[ASTUCE] L'application tourne dans la zone de notification (pres de l'horloge)." -ForegroundColor Yellow
        Write-Host "         Si vous ne la voyez pas directement, cliquez sur la petite fleche '^' de la barre des tâches." -ForegroundColor Yellow
    } else {
        Write-Host "[OK] Tâche planifiee demarree. Verifiez les logs avec 'view_logs.bat'." -ForegroundColor Green
    }
} catch {
    Write-Host "[ERREUR] Impossible de creer la tâche planifiee : $_" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Vous pouvez verifier les logs a tout moment en executant 'view_logs.bat'." -ForegroundColor Yellow
Write-Host "Pour desinstaller, executez 'uninstall.bat'." -ForegroundColor Yellow
Write-Host "==============================================================================" -ForegroundColor Cyan
