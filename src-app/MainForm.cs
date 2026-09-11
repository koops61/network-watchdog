using System;
using System.Drawing;
using System.IO;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows.Forms;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

namespace NetworkWatchdog
{
    public class MainForm : Form
    {
        private readonly WebView2 _webView;
        private readonly NetworkEngine _engine;
        private readonly NotifyIcon _trayIcon;
        private readonly ContextMenuStrip _trayMenu;
        private readonly bool _startMinimized;
        private bool _isClosing = false;

        private ToolStripMenuItem? _itemUpdate;
        private string _updateUrl = "";

        public MainForm(bool startMinimized = false)
        {
            _startMinimized = startMinimized;
            Text = $"Network Watchdog v{NetworkEngine.AppVersion} - Tableau de Bord Réseau";
            Width = 1180;
            Height = 820;
            MinimumSize = new Size(950, 680);
            StartPosition = FormStartPosition.CenterScreen;
            BackColor = Color.FromArgb(10, 13, 20);

            // Initialisation du moteur réseau
            var baseDir = AppDomain.CurrentDomain.BaseDirectory;
            _engine = new NetworkEngine(baseDir);
            _engine.OnMetricsUpdated += Engine_OnMetricsUpdated;
            _engine.OnUpdateDetected += Engine_OnUpdateDetected;
            _engine.OnManualCheckCompleted += Engine_OnManualCheckCompleted;

            // Icône et System Tray
            _trayMenu = new ContextMenuStrip();
            var titleItem = new ToolStripMenuItem($"🛡️ Network Watchdog v{NetworkEngine.AppVersion}") { Enabled = false };
            _trayMenu.Items.Add(titleItem);
            _trayMenu.Items.Add("-");

            _itemUpdate = new ToolStripMenuItem("⭐ Télécharger la mise à jour...", null, (s, e) =>
            {
                if (!string.IsNullOrEmpty(_updateUrl))
                {
                    try { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(_updateUrl) { UseShellExecute = true }); } catch {}
                }
            })
            {
                Visible = false,
                Font = new Font(Font, FontStyle.Bold)
            };
            _trayMenu.Items.Add(_itemUpdate);

            _trayMenu.Items.Add("Ouvrir le Tableau de Bord", null, (s, e) => RestoreFromTray());
            _trayMenu.Items.Add("Vérifier les mises à jour...", null, async (s, e) =>
            {
                if (_engine != null)
                {
                    _trayIcon?.ShowBalloonTip(2000, "Mise à jour", "Recherche de mise à jour sur GitHub...", ToolTipIcon.Info);
                    await _engine.CheckForUpdatesAsync(true);
                }
            });
            _trayMenu.Items.Add("-");
            var itemRestart = new ToolStripMenuItem("Redémarrer Carte Réseau");
            itemRestart.Click += async (s, e) => { if (_engine != null) await _engine.RestartAdapterManualAsync(); };
            _trayMenu.Items.Add(itemRestart);

            var itemCancel = new ToolStripMenuItem("Annuler Reboot PC (shutdown /a)");
            itemCancel.Click += (s, e) => { _engine?.CancelReboot(); };
            _trayMenu.Items.Add(itemCancel);

            _trayMenu.Items.Add("-");
            _trayMenu.Items.Add("Quitter", null, (s, e) => { _isClosing = true; Close(); });

            _trayIcon = new NotifyIcon
            {
                Text = $"Network Watchdog v{NetworkEngine.AppVersion}",
                Icon = SystemIcons.Shield,
                ContextMenuStrip = _trayMenu,
                Visible = true
            };
            _trayIcon.DoubleClick += (s, e) => RestoreFromTray();

            // Charger l'icône personnalisée pour la fenêtre et le System Tray
            var iconPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "app.ico");
            if (File.Exists(iconPath))
            {
                try
                {
                    var customIcon = new Icon(iconPath);
                    Icon = customIcon;
                    _trayIcon.Icon = customIcon;
                }
                catch {}
            }

            // WebView2 Control
            _webView = new WebView2
            {
                Dock = DockStyle.Fill
            };
            Controls.Add(_webView);

            Load += MainForm_Load;
            FormClosing += MainForm_FormClosing;
        }

        protected override void OnShown(EventArgs e)
        {
            base.OnShown(e);
            if (_startMinimized)
            {
                WindowState = FormWindowState.Minimized;
                Hide();
                _trayIcon.ShowBalloonTip(3500, "Network Watchdog", "Surveillance réseau active en arrière-plan. Double-cliquez sur l'icône près de l'horloge pour ouvrir.", ToolTipIcon.Info);
            }
        }

        private async void MainForm_Load(object? sender, EventArgs e)
        {
            try
            {
                var uiDir = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "ui");
                var htmlPath = Path.Combine(uiDir, "index.html");

                // Initialiser l'environnement WebView2
                var env = await CoreWebView2Environment.CreateAsync(null, Path.Combine(Path.GetTempPath(), "NetworkWatchdog_WebView2"));
                await _webView.EnsureCoreWebView2Async(env);

                // Configurer la communication JS -> C#
                _webView.CoreWebView2.WebMessageReceived += CoreWebView2_WebMessageReceived;
                _webView.CoreWebView2.Settings.IsStatusBarEnabled = false;
                _webView.CoreWebView2.Settings.AreDevToolsEnabled = true;

                if (File.Exists(htmlPath))
                {
                    _webView.CoreWebView2.Navigate(htmlPath);
                }
                else
                {
                    _webView.CoreWebView2.NavigateToString("<h1>Erreur: ui/index.html introuvable</h1>");
                }
            }
            catch (Exception ex)
            {
                MessageBox.Show($"Erreur d'initialisation de WebView2 : {ex.Message}", "Erreur", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private void CoreWebView2_WebMessageReceived(object? sender, CoreWebView2WebMessageReceivedEventArgs e)
        {
            try
            {
                var msg = e.TryGetWebMessageAsString();
                using var doc = JsonDocument.Parse(msg);
                var action = doc.RootElement.GetProperty("action").GetString();

                switch (action)
                {
                    case "restartAdapter":
                        _ = _engine.RestartAdapterManualAsync();
                        break;
                    case "cancelReboot":
                        _engine.CancelReboot();
                        break;
                    case "toggleWatchdog":
                        if (doc.RootElement.TryGetProperty("enabled", out var enabledProp))
                        {
                            _engine.ToggleWatchdog(enabledProp.GetBoolean());
                        }
                        break;
                    case "minimizeToTray":
                        WindowState = FormWindowState.Minimized;
                        Hide();
                        _trayIcon.ShowBalloonTip(3000, "Network Watchdog", "L'application continue de surveiller votre réseau en arrière-plan.", ToolTipIcon.Info);
                        break;
                    case "openFolder":
                        System.Diagnostics.Process.Start("explorer.exe", AppDomain.CurrentDomain.BaseDirectory);
                        break;
                    case "checkUpdate":
                        _ = _engine.CheckForUpdatesAsync(true);
                        break;
                    case "openUrl":
                        if (doc.RootElement.TryGetProperty("url", out var urlProp))
                        {
                            var url = urlProp.GetString();
                            if (!string.IsNullOrEmpty(url))
                            {
                                try { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(url) { UseShellExecute = true }); } catch {}
                            }
                        }
                        break;
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"WebMessage error: {ex.Message}");
            }
        }

        private void Engine_OnUpdateDetected(string version, string releaseUrl)
        {
            if (InvokeRequired)
            {
                BeginInvoke(new Action(() => Engine_OnUpdateDetected(version, releaseUrl)));
                return;
            }

            _updateUrl = releaseUrl;
            if (_itemUpdate != null)
            {
                _itemUpdate.Text = $"⭐ Mise à jour {version} disponible !";
                _itemUpdate.Visible = true;
            }

            _trayIcon.ShowBalloonTip(5000, "Mise à jour disponible !", $"Network Watchdog {version} est disponible. Double-cliquez pour ouvrir.", ToolTipIcon.Info);
        }

        private void Engine_OnManualCheckCompleted(string status, string message)
        {
            if (InvokeRequired)
            {
                BeginInvoke(new Action(() => Engine_OnManualCheckCompleted(status, message)));
                return;
            }

            var notification = JsonSerializer.Serialize(new
            {
                type = "updateCheckResult",
                status = status,
                message = message
            });

            _webView?.CoreWebView2?.PostWebMessageAsJson(notification);
        }

        private void Engine_OnMetricsUpdated(NetworkMetricsSnapshot snapshot)
        {
            if (InvokeRequired)
            {
                BeginInvoke(new Action(() => SendSnapshotToWebView(snapshot)));
            }
            else
            {
                SendSnapshotToWebView(snapshot);
            }
        }

        private void SendSnapshotToWebView(NetworkMetricsSnapshot snapshot)
        {
            try
            {
                if (_webView?.CoreWebView2 != null)
                {
                    var json = JsonSerializer.Serialize(snapshot);
                    _webView.CoreWebView2.PostWebMessageAsJson(json);
                }
            }
            catch {}
        }

        private void RestoreFromTray()
        {
            Show();
            WindowState = FormWindowState.Normal;
            BringToFront();
            Activate();
        }

        private void MainForm_FormClosing(object? sender, FormClosingEventArgs e)
        {
            if (!_isClosing && e.CloseReason == CloseReason.UserClosing)
            {
                e.Cancel = true;
                WindowState = FormWindowState.Minimized;
                Hide();
                _trayIcon.ShowBalloonTip(3000, "Network Watchdog", "Réduit dans la zone de notification. Double-cliquez pour rouvrir.", ToolTipIcon.Info);
            }
            else
            {
                _trayIcon.Visible = false;
                _trayIcon.Dispose();
            }
        }
    }
}
