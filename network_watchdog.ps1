# ==============================================================================
# Network Watchdog - Surveillance Réseau et Auto-Réparation pour Windows
# ==============================================================================
[CmdletBinding()]
param (
    [switch]$Interactive,
    [string]$ConfigPath = "$PSScriptRoot\config.json"
)

# Forcer l'encodage UTF-8 pour les logs et la console
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# ------------------------------------------------------------------------------
# 1. Chargement de la configuration
# ------------------------------------------------------------------------------
if (-not (Test-Path $ConfigPath)) {
    Write-Error "Fichier de configuration introuvable : $ConfigPath"
    exit 1
}

try {
    $Config = Get-Content -Path $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
} catch {
    Write-Error "Erreur lors de la lecture du fichier JSON de configuration : $_"
    exit 1
}

# Dossiers et chemins
$LogsDir = Join-Path $PSScriptRoot "logs"
if (-not (Test-Path $LogsDir)) {
    New-Item -ItemType Directory -Path $LogsDir -Force | Out-Null
}

$LogFilePath = Join-Path $PSScriptRoot $Config.log_file
$StateFilePath = Join-Path $PSScriptRoot "state.json"
$StatusFilePath = Join-Path $PSScriptRoot "status.json"

# ------------------------------------------------------------------------------
# 2. Fonctions Utilitaires
# ------------------------------------------------------------------------------
function Write-Log {
    param (
        [string]$Message,
        [string]$Level = "INFO",
        [ConsoleColor]$Color = [ConsoleColor]::White
    )

    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $FormattedMessage = "[$Timestamp] [$Level] $Message"

    # Rotation du log si taille superieure a max_log_size_mb
    if (Test-Path $LogFilePath) {
        $FileSizeMB = (Get-Item $LogFilePath).Length / 1MB
        if ($FileSizeMB -ge $Config.max_log_size_mb) {
            $RotatedName = Join-Path $LogsDir ("network_watchdog_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".log")
            Move-Item -Path $LogFilePath -Destination $RotatedName -Force
        }
    }

    [System.IO.File]::AppendAllText($LogFilePath, "$FormattedMessage`r`n", [System.Text.Encoding]::UTF8)

    if ($Interactive -or [Environment]::UserInteractive) {
        $OriginalColor = $host.UI.RawUI.ForegroundColor
        $host.UI.RawUI.ForegroundColor = $Color
        Write-Host $FormattedMessage
        $host.UI.RawUI.ForegroundColor = $OriginalColor
    }
}

function Show-Notification {
    param (
        [string]$Title,
        [string]$Message,
        [string]$Icon = "Warning"
    )

    if (-not $Config.enable_desktop_notifications) { return }

    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        $NotifyIcon = New-Object System.Windows.Forms.NotifyIcon
        $NotifyIcon.Icon = [System.Drawing.SystemIcons]::Information
        $NotifyIcon.BalloonTipIcon = $Icon
        $NotifyIcon.BalloonTipTitle = $Title
        $NotifyIcon.BalloonTipText = $Message
        $NotifyIcon.Visible = $true
        $NotifyIcon.ShowBalloonTip(5000)
    } catch {
        # Silencieux si pas de session graphique active
    }
}

function Play-AlertSound {
    if ($Config.enable_sound_alert) {
        try {
            [System.Media.SystemSounds]::Exclamation.Play()
        } catch {}
    }
}

function Get-State {
    if (Test-Path $StateFilePath) {
        try {
            return Get-Content -Path $StateFilePath -Raw -Encoding UTF8 | ConvertFrom-Json
        } catch {}
    }
    return [PSCustomObject]@{
        last_reboot_time = $null
        reboot_count = 0
        last_adapter_restart = $null
        adapter_restart_count = 0
        last_status = "UNKNOWN"
    }
}

function Save-State {
    param ($StateObj)
    $StateObj | ConvertTo-Json -Depth 4 | Set-Content -Path $StateFilePath -Encoding UTF8 -Force
}

function Save-LiveStatus {
    param (
        [string]$Status,
        [int]$LatencyMs,
        [string]$AdapterName,
        [int]$ConsecutiveFails,
        [int]$FlappingCount,
        [array]$RecentHistory
    )

    $LiveObj = [PSCustomObject]@{
        updated_at = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        status = $Status
        latency_ms = $LatencyMs
        active_adapter = $AdapterName
        consecutive_failures = $ConsecutiveFails
        flapping_score = $FlappingCount
        recent_history = $RecentHistory
    }

    try {
        $LiveObj | ConvertTo-Json -Depth 4 | Set-Content -Path $StatusFilePath -Encoding UTF8 -Force
    } catch {}
}

# ------------------------------------------------------------------------------
# 3. Détection de la carte réseau
# ------------------------------------------------------------------------------
function Find-ActiveAdapter {
    param ([string]$ConfiguredName)

    # 1. Si un nom est spécifié dans config.json et existe
    if ($ConfiguredName -and ($ConfiguredName.Trim() -ne "")) {
        $adapter = Get-NetAdapter -Name $ConfiguredName -ErrorAction SilentlyContinue
        if ($adapter) { return $adapter }
    }

    # 2. Chercher la carte associée à la route par défaut (passerelle 0.0.0.0/0)
    try {
        $DefaultRoute = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
            Sort-Object -Property RouteMetric |
            Select-Object -First 1

        if ($DefaultRoute) {
            $adapter = Get-NetAdapter -InterfaceIndex $DefaultRoute.InterfaceIndex -ErrorAction SilentlyContinue
            if ($adapter) { return $adapter }
        }
    } catch {}

    # 3. Prendre la première carte physique connectée (Ethernet ou Wi-Fi)
    $ConnectedAdapter = Get-NetAdapter -ErrorAction SilentlyContinue |
        Where-Object { $_.Status -eq "Up" -and $_.Virtual -ne $true } |
        Select-Object -First 1

    if ($ConnectedAdapter) { return $ConnectedAdapter }

    # 4. Repli : première carte physique existante même si déconnectée
    $AnyPhysical = Get-NetAdapter -ErrorAction SilentlyContinue |
        Where-Object { $_.Virtual -ne $true } |
        Select-Object -First 1

    return $AnyPhysical
}

# ------------------------------------------------------------------------------
# 4. Test Ping Haute Performance (.NET Ping)
# ------------------------------------------------------------------------------
$PingSender = New-Object System.Net.NetworkInformation.Ping
$PingOptions = New-Object System.Net.NetworkInformation.PingOptions
$PingOptions.DontFragment = $true
$PingBuffer = [System.Text.Encoding]::ASCII.GetBytes("netwatchdog32bytespingbuffer1234")

function Test-InternetConnection {
    param (
        [string[]]$Targets,
        [int]$TimeoutMs
    )

    $Success = $false
    $LowestLatency = 9999

    foreach ($target in $Targets) {
        try {
            $reply = $PingSender.Send($target, $TimeoutMs, $PingBuffer, $PingOptions)
            if ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) {
                $Success = $true
                if ($reply.RoundtripTime -lt $LowestLatency) {
                    $LowestLatency = [int]$reply.RoundtripTime
                }
                break # Au moins une cible répond, internet est fonctionnel
            }
        } catch {
            # Échec vers cette cible, on teste la suivante
        }
    }

    return [PSCustomObject]@{
        IsOnline = $Success
        LatencyMs = if ($Success) { $LowestLatency } else { -1 }
    }
}

# ------------------------------------------------------------------------------
# 5. Actions d'Auto-Réparation
# ------------------------------------------------------------------------------
function Restart-TargetAdapter {
    param ($Adapter)

    if (-not $Adapter) {
        Write-Log "Impossible de redémarrer la carte réseau : aucun adaptateur identifié." "ERROR" ([ConsoleColor]::Red)
        return $false
    }

    $AdapterName = $Adapter.Name
    Write-Log "Tentative de redémarrage de la carte réseau : '$AdapterName'..." "WARN" ([ConsoleColor]::Yellow)
    Play-AlertSound
    Show-Notification "Watchdog Réseau" "Redémarrage de la carte réseau '$AdapterName' suite à une coupure." "Warning"

    try {
        # Méthode robuste : Disable puis Enable
        Disable-NetAdapter -Name $AdapterName -Confirm:$false -ErrorAction Stop
        Start-Sleep -Seconds 3
        Enable-NetAdapter -Name $AdapterName -Confirm:$false -ErrorAction Stop

        Write-Log "Carte '$AdapterName' redémarrée avec succès. Attente de négociation IP ($($Config.adapter_restart_wait_seconds)s)..." "INFO" ([ConsoleColor]::Cyan)
        Start-Sleep -Seconds $Config.adapter_restart_wait_seconds
        return $true
    } catch {
        Write-Log "Échec lors du redémarrage de la carte '$AdapterName' : $_" "ERROR" ([ConsoleColor]::Red)
        return $false
    }
}

function Trigger-SafeReboot {
    param ([string]$Reason)

    $State = Get-State
    $Now = Get-Date

    # Sécurité Anti-Bootloop : Vérifier si un reboot a déjà eu lieu récemment
    if ($State.last_reboot_time) {
        try {
            $LastReboot = [DateTime]$State.last_reboot_time
            $MinutesSinceLastReboot = ($Now - $LastReboot).TotalMinutes

            if ($MinutesSinceLastReboot -lt $Config.anti_bootloop_cooldown_minutes) {
                Write-Log "================================================================================" "FATAL" ([ConsoleColor]::Magenta)
                Write-Log "SÉCURITÉ ANTI-BOOTLOOP DÉCLENCHÉE !" "FATAL" ([ConsoleColor]::Magenta)
                Write-Log "Le PC a déjà redémarré il y a $([math]::Round($MinutesSinceLastReboot, 1)) minutes ($LastReboot)." "FATAL" ([ConsoleColor]::Magenta)
                Write-Log "Le réseau est toujours défaillant, mais le redémarrage automatique est BLOQUÉ." "FATAL" ([ConsoleColor]::Magenta)
                Write-Log "Cause probable : Panne de box/routeur, câble débranché ou problème FAI général." "FATAL" ([ConsoleColor]::Magenta)
                Write-Log "================================================================================" "FATAL" ([ConsoleColor]::Magenta)
                
                Show-Notification "Watchdog Réseau - Sécurité Anti-Boucle" "Redémarrage bloqué par sécurité. Vérifiez votre box ou câble internet." "Error"
                return
            }
        } catch {
            Write-Log "Avertissement : Erreur lors de l'analyse de last_reboot_time dans state.json : $_" "WARN" ([ConsoleColor]::Yellow)
        }
    }

    # Mise à jour du state avant le reboot
    $State.last_reboot_time = $Now.ToString("yyyy-MM-dd HH:mm:ss")
    $State.reboot_count = [int]$State.reboot_count + 1
    $State.last_reason = $Reason
    Save-State $State

    $Countdown = [int]$Config.reboot_countdown_seconds
    $Comment = "Watchdog Reseau : Panne persistante apres relance carte reseau. Redemarrage du PC dans $Countdown s. Tapez 'shutdown /a' pour annuler."

    Write-Log "DÉCLENCHEMENT DU REDÉMARRAGE DU PC ($Countdown secondes de prévenance)..." "FATAL" ([ConsoleColor]::Red)
    Play-AlertSound
    Show-Notification "Watchdog Réseau : REDÉMARRAGE DU PC" "Redémarrage dans $Countdown s ! Exécutez 'shutdown /a' pour annuler." "Error"

    # Déclencher le redémarrage Windows natif avec message et temporisation
    Start-Process -FilePath "shutdown.exe" -ArgumentList "/r /t $Countdown /c `"$Comment`"" -NoNewWindow
}

# ------------------------------------------------------------------------------
# 6. Boucle Principale de Surveillance
# ------------------------------------------------------------------------------
Write-Log "================================================================================" "INFO" ([ConsoleColor]::Green)
Write-Log "Démarrage de Network Watchdog (PID: $PID)" "INFO" ([ConsoleColor]::Green)
Write-Log "Cibles Ping : $($Config.ping_targets -join ', ') | Intervalle : $($Config.check_interval_seconds)s" "INFO" ([ConsoleColor]::Green)
Write-Log "================================================================================" "INFO" ([ConsoleColor]::Green)

# Vérification des droits administrateur
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
    Write-Log "ATTENTION : Le script n'est pas exécuté avec les privilèges Administrateur !" "WARN" ([ConsoleColor]::Yellow)
    Write-Log "Les actions de redémarrage de carte réseau et du PC risquent d'échouer sans droits élevés." "WARN" ([ConsoleColor]::Yellow)
}

# Variables d'état en mémoire
$ConsecutiveFailures = 0
$AdapterRetriesCount = 0
$History = [System.Collections.Generic.List[PSCustomObject]]::new()
$LastKnownAdapter = Find-ActiveAdapter -ConfiguredName $Config.target_adapter_name

if ($LastKnownAdapter) {
    Write-Log "Carte réseau sélectionnée : '$($LastKnownAdapter.Name)' ($($LastKnownAdapter.InterfaceDescription))" "INFO" ([ConsoleColor]::Cyan)
} else {
    Write-Log "Aucune carte réseau détectée au lancement. Recherche dynamique en cours..." "WARN" ([ConsoleColor]::Yellow)
}

try {
    while ($true) {
        # Actualiser la carte réseau active si nécessaire
        $CurrentAdapter = Find-ActiveAdapter -ConfiguredName $Config.target_adapter_name
        if ($CurrentAdapter) {
            $LastKnownAdapter = $CurrentAdapter
        }
        $AdapterName = if ($LastKnownAdapter) { $LastKnownAdapter.Name } else { "Inconnu" }

        # Test de connexion
        $TestResult = Test-InternetConnection -Targets $Config.ping_targets -TimeoutMs $Config.ping_timeout_ms
        $Timestamp = Get-Date

        # Ajouter à l'historique glissant
        $HistoryEntry = [PSCustomObject]@{
            time = $Timestamp.ToString("HH:mm:ss")
            online = $TestResult.IsOnline
            latency = $TestResult.LatencyMs
        }
        $History.Add($HistoryEntry)
        while ($History.Count -gt $Config.history_window_size) {
            $History.RemoveAt(0)
        }

        # Calculer le score d'instabilité (nombre de transitions UP<->DOWN)
        $FlappingTransitions = 0
        for ($i = 1; $i -lt $History.Count; $i++) {
            if ($History[$i].online -ne $History[$i - 1].online) {
                $FlappingTransitions++
            }
        }

        # Évaluation du statut
        $CurrentStatus = "UP"
        if (-not $TestResult.IsOnline) {
            $ConsecutiveFailures++
            $CurrentStatus = "DOWN"
            Write-Log "Échec connexion internet ($ConsecutiveFailures/$($Config.consecutive_failures_before_adapter_reset))" "WARN" ([ConsoleColor]::Red)
        } else {
            if ($ConsecutiveFailures -gt 0) {
                Write-Log "Connexion rétablie ! Latence : $($TestResult.LatencyMs) ms" "INFO" ([ConsoleColor]::Green)
                $ConsecutiveFailures = 0
                $AdapterRetriesCount = 0
            }
            if ($FlappingTransitions -ge $Config.unstable_flapping_threshold) {
                $CurrentStatus = "UNSTABLE"
                Write-Log "Réseau instable détecté ($FlappingTransitions transitions déco/reco récentes) !" "WARN" ([ConsoleColor]::Yellow)
            } else {
                if ($Interactive) {
                    Write-Host "[$($Timestamp.ToString('HH:mm:ss'))] [OK] En ligne ($($TestResult.LatencyMs) ms) | Carte: $AdapterName" -ForegroundColor DarkGreen
                }
            }
        }

        # Sauvegarde du statut en direct pour l'interface web / monitoring
        Save-LiveStatus -Status $CurrentStatus `
                        -LatencyMs $TestResult.LatencyMs `
                        -AdapterName $AdapterName `
                        -ConsecutiveFails $ConsecutiveFailures `
                        -FlappingCount $FlappingTransitions `
                        -RecentHistory ($History | Select-Object -Last 15)

        # ----------------------------------------------------------------------
        # Prise de Décision : Auto-Réparation
        # ----------------------------------------------------------------------
        $NeedsRepair = ($ConsecutiveFailures -ge $Config.consecutive_failures_before_adapter_reset) -or 
                       ($CurrentStatus -eq "UNSTABLE" -and $FlappingTransitions -ge ($Config.unstable_flapping_threshold * 2))

        if ($NeedsRepair) {
            Write-Log "Anomalie réseau confirmée. Début de la procédure d'auto-réparation." "WARN" ([ConsoleColor]::Yellow)

            if ($AdapterRetriesCount -lt $Config.max_adapter_retries_before_reboot) {
                # ACTION 1 : Redémarrer la carte réseau
                $AdapterRetriesCount++
                Write-Log "Tentative de réparation #$AdapterRetriesCount / $($Config.max_adapter_retries_before_reboot)" "INFO" ([ConsoleColor]::Cyan)
                
                $RestartSuccess = Restart-TargetAdapter -Adapter $LastKnownAdapter
                
                # Test immédiat après relance
                $VerifyResult = Test-InternetConnection -Targets $Config.ping_targets -TimeoutMs $Config.ping_timeout_ms
                if ($VerifyResult.IsOnline) {
                    Write-Log "SUCCÈS : Connexion rétablie après redémarrage de la carte réseau ! Latence : $($VerifyResult.LatencyMs) ms" "INFO" ([ConsoleColor]::Green)
                    $ConsecutiveFailures = 0
                    $AdapterRetriesCount = 0
                    $History.Clear()
                } else {
                    Write-Log "La connexion n'est toujours pas disponible après la relance de la carte réseau." "WARN" ([ConsoleColor]::Red)
                }
            } else {
                # ACTION 2 : Échec des relances de la carte réseau -> Déclencher le redémarrage du PC
                Write-Log "La carte réseau a été redémarrée $AdapterRetriesCount fois sans succès." "FATAL" ([ConsoleColor]::Red)
                Trigger-SafeReboot -Reason "Perte réseau persistante après $AdapterRetriesCount tentatives de réinitialisation de la carte."
                
                # Attendre le compte à rebours de redémarrage
                Start-Sleep -Seconds ($Config.reboot_countdown_seconds + 5)
            }
        }

        Start-Sleep -Seconds $Config.check_interval_seconds
    }
} finally {
    Write-Log "Arrêt du service Network Watchdog." "INFO" ([ConsoleColor]::Yellow)
    if ($PingSender) { $PingSender.Dispose() }
}
