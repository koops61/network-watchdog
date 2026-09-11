# ==============================================================================
# Script d'Installation de la Tâche Planifiée Network Watchdog
# ==============================================================================
[CmdletBinding()]
param()

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

# 2. Supprimer la tâche si elle existe déjà
$ExistingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($ExistingTask) {
    Write-Host "[INFO] Une tâche existante '$TaskName' a ete detectee. Mise a jour..." -ForegroundColor Yellow
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

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

# 4. Définir les déclencheurs (Au démarrage du système et à l'ouverture de session)
$TriggerLogon = New-ScheduledTaskTrigger -AtLogOn
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

# 6. Définir le principal (Privilèges Administrateurs les plus élevés)
$CurrentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
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
    Write-Host "Elle demarrera automatiquement avec Windows avec les privileges Administrateur (sans popup UAC)." -ForegroundColor Green
    Write-Host ""
    
    # 8. Proposer de démarrer la tâche immédiatement
    Write-Host "Demarrage immediat du watchdog en arriere-plan..." -ForegroundColor Cyan
    Start-ScheduledTask -TaskName $TaskName
    Write-Host "[OK] Network Watchdog est maintenant actif en arriere-plan !" -ForegroundColor Green
} catch {
    Write-Host "[ERREUR] Impossible de creer la tâche planifiee : $_" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Vous pouvez verifier les logs a tout moment en executant 'view_logs.bat'." -ForegroundColor Yellow
Write-Host "Pour desinstaller, executez 'uninstall.bat'." -ForegroundColor Yellow
Write-Host "==============================================================================" -ForegroundColor Cyan
