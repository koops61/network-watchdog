using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace NetworkWatchdog
{
    public class NetworkMetricsSnapshot
    {
        public string Timestamp { get; set; } = "";
        public bool IsOnline { get; set; }
        public string Status { get; set; } = "UP"; // UP, DOWN, UNSTABLE
        
        // Adapter info
        public string AdapterName { get; set; } = "N/A";
        public string AdapterDescription { get; set; } = "N/A";
        public string AdapterType { get; set; } = "N/A";
        public string LinkSpeed { get; set; } = "N/A";
        public string MacAddress { get; set; } = "N/A";
        public string LocalIp { get; set; } = "N/A";
        public string SubnetMask { get; set; } = "N/A";
        public string GatewayIp { get; set; } = "N/A";
        public string DnsServers { get; set; } = "N/A";
        public string PublicIp { get; set; } = "Détection...";

        // Bandwidth (Real-time speed)
        public double DownloadSpeedKBps { get; set; }
        public double UploadSpeedKBps { get; set; }
        public string TotalReceivedFormatted { get; set; } = "0 Mo";
        public string TotalSentFormatted { get; set; } = "0 Mo";

        // Latencies
        public int PingGatewayMs { get; set; } = -1;
        public int PingCloudflareMs { get; set; } = -1;
        public int PingGoogleMs { get; set; } = -1;
        public int PrimaryPingMs { get; set; } = -1;

        // Stability & Watchdog stats
        public double PacketLossPercent { get; set; }
        public int FlappingScore { get; set; }
        public int ConsecutiveFailures { get; set; }
        public int AdapterRestartCount { get; set; }
        public bool WatchdogEnabled { get; set; } = true;
        public bool AntiBootloopSafe { get; set; } = true;
        public string AntiBootloopMessage { get; set; } = "Protection active (20 min)";

        // Recent latency chart samples
        public List<LatencyPoint> LatencyHistory { get; set; } = new();
        public List<string> RecentLogs { get; set; } = new();
    }

    public class LatencyPoint
    {
        public string Time { get; set; } = "";
        public int Latency { get; set; }
        public bool Online { get; set; }
    }

    public class NetworkEngine
    {
        private readonly System.Threading.Timer _timer;
        private readonly Ping _pingGateway = new();
        private readonly Ping _pingCloudflare = new();
        private readonly Ping _pingGoogle = new();

        private long _lastBytesReceived = -1;
        private long _lastBytesSent = -1;
        private DateTime _lastCheckTime = DateTime.UtcNow;

        private readonly List<bool> _pingSuccessHistory = new();
        private readonly List<LatencyPoint> _chartHistory = new();
        private readonly ConcurrentQueue<string> _logs = new();

        private int _consecutiveFailures = 0;
        private int _adapterRestartCount = 0;
        private bool _isRepairing = false;
        private bool _watchdogEnabled = true;

        private string _cachedPublicIp = "Recherche...";
        private DateTime _lastPublicIpCheck = DateTime.MinValue;

        private readonly string _configFilePath;
        private readonly string _stateFilePath;
        private readonly string _logFilePath;
        private readonly string _statusFilePath;

        public event Action<NetworkMetricsSnapshot>? OnMetricsUpdated;

        public NetworkEngine(string baseDir)
        {
            _configFilePath = Path.Combine(baseDir, "config.json");
            _stateFilePath = Path.Combine(baseDir, "state.json");
            _logFilePath = Path.Combine(baseDir, "logs", "network_watchdog.log");
            _statusFilePath = Path.Combine(baseDir, "status.json");

            Directory.CreateDirectory(Path.Combine(baseDir, "logs"));

            AddLog("Network Watchdog démarré. Initialisation du moteur de surveillance...");

            // Timer de mise à jour toutes les 1.5 seconde
            _timer = new System.Threading.Timer(async _ => await UpdateLoopAsync(), null, 500, 1500);

            // Fetch public IP in background
            Task.Run(FetchPublicIpAsync);
        }

        public void ToggleWatchdog(bool enable)
        {
            _watchdogEnabled = enable;
            AddLog(_watchdogEnabled ? "Surveillance automatique ACTIVÉE" : "Surveillance automatique MISE EN PAUSE");
        }

        public void AddLog(string message, string level = "INFO")
        {
            var time = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss");
            var line = $"[{time}] [{level}] {message}";
            _logs.Enqueue(line);
            while (_logs.Count > 100) _logs.TryDequeue(out _);

            try
            {
                File.AppendAllText(_logFilePath, line + Environment.NewLine);
            }
            catch {}
        }

        private async Task FetchPublicIpAsync()
        {
            try
            {
                using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(5) };
                var ip = await client.GetStringAsync("https://api.ipify.org");
                if (!string.IsNullOrWhiteSpace(ip))
                {
                    _cachedPublicIp = ip.Trim();
                    _lastPublicIpCheck = DateTime.UtcNow;
                }
            }
            catch
            {
                // Retry with fallback
                try
                {
                    using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(5) };
                    var ip = await client.GetStringAsync("https://ifconfig.me/ip");
                    if (!string.IsNullOrWhiteSpace(ip))
                    {
                        _cachedPublicIp = ip.Trim();
                        _lastPublicIpCheck = DateTime.UtcNow;
                    }
                }
                catch
                {
                    _cachedPublicIp = "Indisponible (Hors ligne)";
                }
            }
        }

        private async Task UpdateLoopAsync()
        {
            try
            {
                var now = DateTime.UtcNow;
                var elapsedSec = (now - _lastCheckTime).TotalSeconds;
                if (elapsedSec <= 0) elapsedSec = 1;
                _lastCheckTime = now;

                var snapshot = new NetworkMetricsSnapshot
                {
                    Timestamp = DateTime.Now.ToString("HH:mm:ss"),
                    WatchdogEnabled = _watchdogEnabled
                };

                // 1. Trouver la carte réseau active
                var activeInterface = FindPrimaryInterface();
                if (activeInterface != null)
                {
                    snapshot.AdapterName = activeInterface.Name;
                    snapshot.AdapterDescription = activeInterface.Description;
                    snapshot.AdapterType = activeInterface.NetworkInterfaceType.ToString();
                    snapshot.LinkSpeed = FormatSpeed(activeInterface.Speed);
                    snapshot.MacAddress = string.Join(":", activeInterface.GetPhysicalAddress().GetAddressBytes().Select(b => b.ToString("X2")));

                    var ipProps = activeInterface.GetIPProperties();
                    var unicast = ipProps.UnicastAddresses.FirstOrDefault(a => a.Address.AddressFamily == AddressFamily.InterNetwork);
                    if (unicast != null)
                    {
                        snapshot.LocalIp = unicast.Address.ToString();
                        snapshot.SubnetMask = unicast.IPv4Mask?.ToString() ?? "255.255.255.0";
                    }

                    var gateway = ipProps.GatewayAddresses.FirstOrDefault(g => g.Address.AddressFamily == AddressFamily.InterNetwork);
                    if (gateway != null)
                    {
                        snapshot.GatewayIp = gateway.Address.ToString();
                    }

                    var dnsList = ipProps.DnsAddresses.Where(d => d.AddressFamily == AddressFamily.InterNetwork).Select(d => d.ToString());
                    snapshot.DnsServers = string.Join(", ", dnsList);

                    // Calcul de bande passante
                    var stats = activeInterface.GetIPv4Statistics();
                    if (_lastBytesReceived >= 0 && _lastBytesSent >= 0)
                    {
                        var rxDiff = stats.BytesReceived - _lastBytesReceived;
                        var txDiff = stats.BytesSent - _lastBytesSent;
                        if (rxDiff >= 0) snapshot.DownloadSpeedKBps = Math.Round((rxDiff / 1024.0) / elapsedSec, 1);
                        if (txDiff >= 0) snapshot.UploadSpeedKBps = Math.Round((txDiff / 1024.0) / elapsedSec, 1);
                    }
                    _lastBytesReceived = stats.BytesReceived;
                    _lastBytesSent = stats.BytesSent;

                    snapshot.TotalReceivedFormatted = FormatBytes(stats.BytesReceived);
                    snapshot.TotalSentFormatted = FormatBytes(stats.BytesSent);
                }

                // Refresh public IP periodically (every 10 minutes)
                if ((DateTime.UtcNow - _lastPublicIpCheck).TotalMinutes > 10)
                {
                    _ = FetchPublicIpAsync();
                }
                snapshot.PublicIp = _cachedPublicIp;

                // 2. Triple test de ping
                var tGateway = PingHostAsync(snapshot.GatewayIp, 1000);
                var tCloudflare = PingHostAsync("1.1.1.1", 1000);
                var tGoogle = PingHostAsync("8.8.8.8", 1000);

                await Task.WhenAll(tGateway, tCloudflare, tGoogle);

                snapshot.PingGatewayMs = tGateway.Result;
                snapshot.PingCloudflareMs = tCloudflare.Result;
                snapshot.PingGoogleMs = tGoogle.Result;

                // Ping principal vers l'extérieur (le meilleur entre Cloudflare et Google)
                int bestExternalPing = -1;
                if (snapshot.PingCloudflareMs >= 0 && snapshot.PingGoogleMs >= 0)
                    bestExternalPing = Math.Min(snapshot.PingCloudflareMs, snapshot.PingGoogleMs);
                else if (snapshot.PingCloudflareMs >= 0)
                    bestExternalPing = snapshot.PingCloudflareMs;
                else if (snapshot.PingGoogleMs >= 0)
                    bestExternalPing = snapshot.PingGoogleMs;

                snapshot.PrimaryPingMs = bestExternalPing;
                snapshot.IsOnline = (bestExternalPing >= 0);

                // 3. Historique & Perte de paquets
                _pingSuccessHistory.Add(snapshot.IsOnline);
                if (_pingSuccessHistory.Count > 50) _pingSuccessHistory.RemoveAt(0);

                int failedPings = _pingSuccessHistory.Count(s => !s);
                snapshot.PacketLossPercent = Math.Round(((double)failedPings / _pingSuccessHistory.Count) * 100.0, 1);

                // Détection de Flapping (déco/reco)
                int transitions = 0;
                for (int i = 1; i < _pingSuccessHistory.Count; i++)
                {
                    if (_pingSuccessHistory[i] != _pingSuccessHistory[i - 1]) transitions++;
                }
                snapshot.FlappingScore = transitions;

                // Statut général
                if (!snapshot.IsOnline)
                {
                    snapshot.Status = "DOWN";
                    _consecutiveFailures++;
                }
                else
                {
                    if (_consecutiveFailures > 0)
                    {
                        AddLog($"Connexion rétablie ! Latence : {snapshot.PrimaryPingMs} ms", "INFO");
                        _consecutiveFailures = 0;
                        _adapterRestartCount = 0;
                    }

                    if (transitions >= 3)
                    {
                        snapshot.Status = "UNSTABLE";
                    }
                    else
                    {
                        snapshot.Status = "UP";
                    }
                }

                snapshot.ConsecutiveFailures = _consecutiveFailures;
                snapshot.AdapterRestartCount = _adapterRestartCount;

                // Points du graphique
                var point = new LatencyPoint
                {
                    Time = DateTime.Now.ToString("HH:mm:ss"),
                    Latency = snapshot.PrimaryPingMs >= 0 ? snapshot.PrimaryPingMs : 0,
                    Online = snapshot.IsOnline
                };
                _chartHistory.Add(point);
                if (_chartHistory.Count > 30) _chartHistory.RemoveAt(0);
                snapshot.LatencyHistory = new List<LatencyPoint>(_chartHistory);
                snapshot.RecentLogs = _logs.Reverse().Take(30).ToList();

                // 4. Déclenchement de l'auto-réparation (Watchdog) si activé
                if (_watchdogEnabled && !_isRepairing)
                {
                    bool needsRepair = (_consecutiveFailures >= 3) || (snapshot.Status == "UNSTABLE" && transitions >= 6);
                    if (needsRepair)
                    {
                        _isRepairing = true;
                        _ = HandleAutoRepairAsync(snapshot.AdapterName);
                    }
                }

                OnMetricsUpdated?.Invoke(snapshot);
                WriteStatusJson(snapshot);
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"UpdateLoop error: {ex.Message}");
            }
        }

        private void WriteStatusJson(NetworkMetricsSnapshot snapshot)
        {
            try
            {
                var history = snapshot.LatencyHistory
                    .TakeLast(10)
                    .Select(h => new
                    {
                        time = h.Time,
                        online = h.Online,
                        latency = h.Latency
                    })
                    .ToList();

                var statusObj = new
                {
                    updated_at = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"),
                    status = snapshot.Status,
                    latency_ms = snapshot.PrimaryPingMs,
                    active_adapter = snapshot.AdapterName,
                    consecutive_failures = snapshot.ConsecutiveFailures,
                    flapping_score = snapshot.FlappingScore,
                    recent_history = history
                };

                var json = JsonSerializer.Serialize(statusObj, new JsonSerializerOptions { WriteIndented = true });
                File.WriteAllText(_statusFilePath, json);
            }
            catch {}
        }

        private async Task HandleAutoRepairAsync(string adapterName)
        {
            try
            {
                if (_adapterRestartCount < 2)
                {
                    _adapterRestartCount++;
                    AddLog($"[AUTO-RÉPARATION] Coupure confirmée. Tentative {_adapterRestartCount}/2 : Redémarrage de la carte '{adapterName}'...", "WARN");

                    await RestartAdapterInternalAsync(adapterName);

                    // Attente de négociation
                    await Task.Delay(15000);
                    _isRepairing = false;
                }
                else
                {
                    // Action niveau 2 : Reboot sécurisé
                    AddLog($"[AUTO-RÉPARATION] Échec après {_adapterRestartCount} relances de la carte réseau. Décision de redémarrage PC.", "FATAL");
                    TriggerSafeReboot();
                    await Task.Delay(30000);
                    _isRepairing = false;
                }
            }
            catch (Exception ex)
            {
                AddLog($"Erreur auto-réparation : {ex.Message}", "ERROR");
                _isRepairing = false;
            }
        }

        public async Task<bool> RestartAdapterManualAsync()
        {
            var iface = FindPrimaryInterface();
            if (iface == null) return false;
            AddLog($"[MANUEL] Redémarrage demandé pour la carte '{iface.Name}'...", "INFO");
            return await RestartAdapterInternalAsync(iface.Name);
        }

        private async Task<bool> RestartAdapterInternalAsync(string adapterName)
        {
            return await Task.Run(() =>
            {
                try
                {
                    var cmd = $"Restart-NetAdapter -Name '{adapterName}' -Confirm:$false";
                    var psi = new ProcessStartInfo("powershell.exe", $"-NoProfile -ExecutionPolicy Bypass -Command \"{cmd}\"")
                    {
                        CreateNoWindow = true,
                        UseShellExecute = false
                    };
                    var proc = Process.Start(psi);
                    proc?.WaitForExit(10000);
                    AddLog($"Carte réseau '{adapterName}' redémarrée avec succès.", "INFO");
                    return true;
                }
                catch (Exception ex)
                {
                    AddLog($"Échec redémarrage carte '{adapterName}' : {ex.Message}", "ERROR");
                    return false;
                }
            });
        }

        public bool CancelReboot()
        {
            try
            {
                var psi = new ProcessStartInfo("shutdown.exe", "/a")
                {
                    CreateNoWindow = true,
                    UseShellExecute = false
                };
                var proc = Process.Start(psi);
                proc?.WaitForExit(5000);
                AddLog("Commande d'annulation de redémarrage (shutdown /a) envoyée.", "WARN");
                return true;
            }
            catch (Exception ex)
            {
                AddLog($"Erreur annulation reboot : {ex.Message}", "ERROR");
                return false;
            }
        }

        private void TriggerSafeReboot()
        {
            try
            {
                // Vérification anti-bootloop
                if (File.Exists(_stateFilePath))
                {
                    var json = File.ReadAllText(_stateFilePath);
                    using var doc = JsonDocument.Parse(json);
                    if (doc.RootElement.TryGetProperty("last_reboot_time", out var prop) && prop.GetString() is string lastStr && DateTime.TryParse(lastStr, out var lastReboot))
                    {
                        if ((DateTime.Now - lastReboot).TotalMinutes < 20)
                        {
                            AddLog("SÉCURITÉ ANTI-BOOTLOOP DÉCLENCHÉE ! Le PC a déjà redémarré il y a moins de 20 minutes. Reboot automatique suspendu.", "FATAL");
                            return;
                        }
                    }
                }

                var stateObj = new
                {
                    last_reboot_time = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"),
                    reason = "Watchdog: Coupure réseau persistante après 2 relances carte."
                };
                File.WriteAllText(_stateFilePath, JsonSerializer.Serialize(stateObj));

                AddLog("REDÉMARRAGE DU PC PROGRAMMÉ DANS 60 SECONDES (shutdown /r /t 60).", "FATAL");
                var psi = new ProcessStartInfo("shutdown.exe", "/r /t 60 /c \"Network Watchdog: Coupure reseau persistante. Tapez shutdown /a pour annuler.\"")
                {
                    CreateNoWindow = true,
                    UseShellExecute = false
                };
                Process.Start(psi);
            }
            catch (Exception ex)
            {
                AddLog($"Erreur déclenchement reboot : {ex.Message}", "ERROR");
            }
        }

        private async Task<int> PingHostAsync(string host, int timeoutMs)
        {
            if (string.IsNullOrWhiteSpace(host) || host == "N/A") return -1;
            try
            {
                using var p = new Ping();
                var reply = await p.SendPingAsync(host, timeoutMs);
                return reply.Status == IPStatus.Success ? (int)reply.RoundtripTime : -1;
            }
            catch
            {
                return -1;
            }
        }

        private NetworkInterface? FindPrimaryInterface()
        {
            var interfaces = NetworkInterface.GetAllNetworkInterfaces()
                .Where(i => i.OperationalStatus == OperationalStatus.Up &&
                            i.NetworkInterfaceType != NetworkInterfaceType.Loopback &&
                            !i.Description.ToLower().Contains("virtual") &&
                            !i.Description.ToLower().Contains("pseudo") &&
                            !i.Description.ToLower().Contains("wsl"))
                .ToList();

            // 1. Chercher la carte avec passerelle IPv4 configurée
            foreach (var iface in interfaces)
            {
                var ipProps = iface.GetIPProperties();
                if (ipProps.GatewayAddresses.Any(g => g.Address.AddressFamily == AddressFamily.InterNetwork && !g.Address.Equals(IPAddress.Any)))
                {
                    return iface;
                }
            }

            return interfaces.FirstOrDefault();
        }

        private string FormatSpeed(long bitsPerSecond)
        {
            if (bitsPerSecond <= 0) return "Inconnue";
            if (bitsPerSecond >= 1_000_000_000) return $"{bitsPerSecond / 1_000_000_000.0:0.##} Gbps";
            if (bitsPerSecond >= 1_000_000) return $"{bitsPerSecond / 1_000_000.0:0.##} Mbps";
            return $"{bitsPerSecond / 1000.0:0.##} Kbps";
        }

        private string FormatBytes(long bytes)
        {
            if (bytes >= 1024L * 1024 * 1024) return $"{bytes / (1024.0 * 1024 * 1024):0.##} Go";
            if (bytes >= 1024L * 1024) return $"{bytes / (1024.0 * 1024):0.##} Mo";
            return $"{bytes / 1024.0:0.##} Ko";
        }
    }
}
