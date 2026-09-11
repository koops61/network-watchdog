# ==============================================================================
# Serveur Web Local Léger pour le Tableau de Bord Network Watchdog (Natif PowerShell)
# ==============================================================================
[CmdletBinding()]
param (
    [int]$Port = 8080
)

$WebRoot = Join-Path $PSScriptRoot "web"
$StatusFile = Join-Path $PSScriptRoot "status.json"
$ConfigFile = Join-Path $PSScriptRoot "config.json"
$LogFile = Join-Path $PSScriptRoot "logs\network_watchdog.log"

$Prefix = "http://localhost:$Port/"
$Listener = New-Object System.Net.HttpListener
$Listener.Prefixes.Add($Prefix)

try {
    $Listener.Start()
    Write-Host "==============================================================================" -ForegroundColor Cyan
    Write-Host "     TABLEAU DE BORD NETWORK WATCHDOG DEMARRE" -ForegroundColor Cyan
    Write-Host "==============================================================================" -ForegroundColor Cyan
    Write-Host "URL locale : $Prefix" -ForegroundColor Green
    Write-Host "Appuyez sur Ctrl+C dans cette fenetre pour arreter le serveur web." -ForegroundColor Yellow
    Write-Host ""

    # Ouvrir le navigateur automatiquement
    Start-Process $Prefix

    while ($Listener.IsListening) {
        $Context = $Listener.GetContext()
        $Request = $Context.Request
        $Response = $Context.Response

        $UrlPath = $Request.Url.AbsolutePath

        # En-têtes CORS et Cache
        $Response.Headers.Add("Access-Control-Allow-Origin", "*")
        $Response.Headers.Add("Cache-Control", "no-cache, no-store, must-revalidate")

        try {
            if ($UrlPath -eq "/api/status") {
                $Response.ContentType = "application/json; charset=utf-8"
                if (Test-Path $StatusFile) {
                    $Content = [System.IO.File]::ReadAllBytes($StatusFile)
                } else {
                    $DefaultJson = '{"status":"WAITING","latency_ms":-1,"active_adapter":"En attente...","consecutive_failures":0,"flapping_score":0,"recent_history":[]}'
                    $Content = [System.Text.Encoding]::UTF8.GetBytes($DefaultJson)
                }
                $Response.OutputStream.Write($Content, 0, $Content.Length)
            }
            elseif ($UrlPath -eq "/api/logs") {
                $Response.ContentType = "text/plain; charset=utf-8"
                if (Test-Path $LogFile) {
                    $Content = [System.IO.File]::ReadAllBytes($LogFile)
                } else {
                    $Content = [System.Text.Encoding]::UTF8.GetBytes("[En attente des premiers logs...]")
                }
                $Response.OutputStream.Write($Content, 0, $Content.Length)
            }
            elseif ($UrlPath -eq "/api/cancel-reboot" -and $Request.HttpMethod -eq "POST") {
                $Response.ContentType = "application/json; charset=utf-8"
                $CancelResult = Start-Process "shutdown.exe" -ArgumentList "/a" -Wait -PassThru -NoNewWindow
                $Success = ($CancelResult.ExitCode -eq 0)
                $Msg = if ($Success) { "Redémarrage annulé avec succès (shutdown /a)" } else { "Aucun redémarrage n'était planifié" }
                $Json = "{`"success`":$($Success.ToString().ToLower()), `"message`":`"$Msg`"}"
                $Content = [System.Text.Encoding]::UTF8.GetBytes($Json)
                $Response.OutputStream.Write($Content, 0, $Content.Length)
            }
            else {
                # Servir les fichiers statiques de web/
                $RequestedFile = if ($UrlPath -eq "/" -or $UrlPath -eq "") { "index.html" } else { $UrlPath.TrimStart('/') }
                $FilePath = Join-Path $WebRoot $RequestedFile

                if (Test-Path $FilePath) {
                    $Ext = [System.IO.Path]::GetExtension($FilePath).ToLower()
                    switch ($Ext) {
                        ".html" { $Response.ContentType = "text/html; charset=utf-8" }
                        ".css"  { $Response.ContentType = "text/css; charset=utf-8" }
                        ".js"   { $Response.ContentType = "application/javascript; charset=utf-8" }
                        ".json" { $Response.ContentType = "application/json; charset=utf-8" }
                        Default { $Response.ContentType = "application/octet-stream" }
                    }
                    $Content = [System.IO.File]::ReadAllBytes($FilePath)
                    $Response.OutputStream.Write($Content, 0, $Content.Length)
                } else {
                    $Response.StatusCode = 404
                    $NotFoundBytes = [System.Text.Encoding]::UTF8.GetBytes("404 Not Found")
                    $Response.OutputStream.Write($NotFoundBytes, 0, $NotFoundBytes.Length)
                }
            }
        } catch {
            $Response.StatusCode = 500
        } finally {
            $Response.Close()
        }
    }
} finally {
    if ($Listener.IsListening) { $Listener.Stop() }
    $Listener.Close()
}
