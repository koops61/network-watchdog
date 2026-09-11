// ==============================================================================
// Network Watchdog - Frontend Application Bridge (WebView2 <-> C# Engine)
// ==============================================================================

// UI Elements
const globalStatusBadge = document.getElementById('globalStatusBadge');
const globalStatusText = document.getElementById('globalStatusText');
const minimizeBtn = document.getElementById('minimizeBtn');
const versionBadge = document.getElementById('versionBadge');
const updateAlertBtn = document.getElementById('updateAlertBtn');
const updateAlertText = document.getElementById('updateAlertText');

const updateModal = document.getElementById('updateModal');
const closeUpdateModalBtn = document.getElementById('closeUpdateModalBtn');
const modalCurrentVer = document.getElementById('modalCurrentVer');
const modalLatestVer = document.getElementById('modalLatestVer');
const modalReleaseNotes = document.getElementById('modalReleaseNotes');
const modalLaterBtn = document.getElementById('modalLaterBtn');
const modalDownloadBtn = document.getElementById('modalDownloadBtn');

let currentReleaseUrl = 'https://github.com/koops61/network-watchdog/releases';

const downloadSpeed = document.getElementById('downloadSpeed');
const downloadUnit = document.getElementById('downloadUnit');
const totalDownload = document.getElementById('totalDownload');
const downloadActivityBar = document.getElementById('downloadActivityBar');

const uploadSpeed = document.getElementById('uploadSpeed');
const uploadUnit = document.getElementById('uploadUnit');
const totalUpload = document.getElementById('totalUpload');
const uploadActivityBar = document.getElementById('uploadActivityBar');

const gatewayIpShort = document.getElementById('gatewayIpShort');
const pingGatewayBadge = document.getElementById('pingGatewayBadge');
const pingCloudflareBadge = document.getElementById('pingCloudflareBadge');
const pingGoogleBadge = document.getElementById('pingGoogleBadge');

const adapterNameText = document.getElementById('adapterNameText');
const adapterDescText = document.getElementById('adapterDescText');
const adapterSpeedBadge = document.getElementById('adapterSpeedBadge');
const specLocalIp = document.getElementById('specLocalIp');
const specSubnet = document.getElementById('specSubnet');
const specGateway = document.getElementById('specGateway');
const specDns = document.getElementById('specDns');
const specMac = document.getElementById('specMac');
const specPublicIp = document.getElementById('specPublicIp');

const sparkBarsContainer = document.getElementById('sparkBarsContainer');
const packetLossVal = document.getElementById('packetLossVal');
const flappingVal = document.getElementById('flappingVal');
const antiBootloopVal = document.getElementById('antiBootloopVal');
const antiBootloopSub = document.getElementById('antiBootloopSub');

const repairAdapterBtn = document.getElementById('repairAdapterBtn');
const toggleWatchdogBtn = document.getElementById('toggleWatchdogBtn');
const toggleWatchdogText = document.getElementById('toggleWatchdogText');
const cancelRebootBtn = document.getElementById('cancelRebootBtn');
const terminalConsole = document.getElementById('terminalConsole');

const toast = document.getElementById('toast');
const toastTitle = document.getElementById('toastTitle');
const toastMessage = document.getElementById('toastMessage');

let isWatchdogActive = true;

function showToast(title, message) {
  toastTitle.textContent = title;
  toastMessage.textContent = message;
  toast.classList.remove('hidden');
  setTimeout(() => toast.classList.add('hidden'), 3500);
}

// Format speeds nicely (Ko/s -> Mo/s if >= 1000)
function formatSpeedValue(kbps) {
  if (kbps >= 1024) {
    return { val: (kbps / 1024).toFixed(2), unit: 'Mo/s' };
  }
  return { val: kbps.toFixed(1), unit: 'Ko/s' };
}

function updatePingBadge(badgeEl, ms) {
  if (ms < 0) {
    badgeEl.textContent = 'Échec';
    badgeEl.style.color = 'var(--red)';
  } else {
    badgeEl.textContent = `${ms} ms`;
    if (ms < 30) {
      badgeEl.style.color = 'var(--green)';
    } else if (ms < 80) {
      badgeEl.style.color = 'var(--cyan)';
    } else {
      badgeEl.style.color = 'var(--amber)';
    }
  }
}

// ------------------------------------------------------------------------------
// WebView2 Message Handler (From C# Engine)
// ------------------------------------------------------------------------------
if (window.chrome && window.chrome.webview) {
  window.chrome.webview.addEventListener('message', event => {
    try {
      const data = typeof event.data === 'string' ? JSON.parse(event.data) : event.data;
      renderMetrics(data);
    } catch (err) {
      console.error('Error parsing snapshot from C#:', err);
    }
  });
} else {
  // Fallback demo for preview outside WebView2
  console.log('Running in browser preview mode');
}

function renderMetrics(data) {
  if (data.type === 'updateCheckResult') {
    showToast('Mise à jour', data.message);
    return;
  }

  // 0. Version & Mises à jour
  if (data.AppVersion && versionBadge) {
    versionBadge.textContent = `v${data.AppVersion}`;
  }

  if (data.UpdateAvailable) {
    if (updateAlertBtn) updateAlertBtn.classList.remove('hidden');
    if (updateAlertText && data.LatestVersion) {
      updateAlertText.textContent = `Mise à jour ${data.LatestVersion} disponible`;
    }
    if (modalLatestVer && data.LatestVersion) modalLatestVer.textContent = data.LatestVersion;
    if (modalCurrentVer && data.AppVersion) modalCurrentVer.textContent = `v${data.AppVersion}`;
    if (modalReleaseNotes && data.ReleaseNotes) {
      modalReleaseNotes.textContent = data.ReleaseNotes;
    }
    if (data.ReleaseUrl) currentReleaseUrl = data.ReleaseUrl;
  } else {
    if (updateAlertBtn) updateAlertBtn.classList.add('hidden');
  }

  // 1. Global Status Badge
  globalStatusBadge.className = 'status-pill';
  if (data.Status === 'UP') {
    globalStatusBadge.classList.add('status-online');
    globalStatusText.textContent = 'EN LIGNE (STABLE)';
  } else if (data.Status === 'UNSTABLE') {
    globalStatusBadge.classList.add('status-unstable');
    globalStatusText.textContent = `INSTABLE (${data.FlappingScore} DÉCO/RECO)`;
  } else {
    globalStatusBadge.classList.add('status-offline');
    globalStatusText.textContent = `HORS LIGNE (${data.ConsecutiveFailures} ÉCHECS)`;
  }

  // 2. Download Speed
  const dl = formatSpeedValue(data.DownloadSpeedKBps);
  downloadSpeed.textContent = dl.val;
  downloadUnit.textContent = dl.unit;
  totalDownload.textContent = `Total : ${data.TotalReceivedFormatted}`;
  const dlPct = Math.min(Math.max((data.DownloadSpeedKBps / 10240) * 100, 4), 100);
  downloadActivityBar.style.width = `${dlPct}%`;

  // 3. Upload Speed
  const ul = formatSpeedValue(data.UploadSpeedKBps);
  uploadSpeed.textContent = ul.val;
  uploadUnit.textContent = ul.unit;
  totalUpload.textContent = `Total : ${data.TotalSentFormatted}`;
  const ulPct = Math.min(Math.max((data.UploadSpeedKBps / 5120) * 100, 4), 100);
  uploadActivityBar.style.width = `${ulPct}%`;

  // 4. Triple Pings
  gatewayIpShort.textContent = data.GatewayIp || 'Passerelle';
  updatePingBadge(pingGatewayBadge, data.PingGatewayMs);
  updatePingBadge(pingCloudflareBadge, data.PingCloudflareMs);
  updatePingBadge(pingGoogleBadge, data.PingGoogleMs);

  // 5. Network Identity Card
  adapterNameText.textContent = data.AdapterName;
  adapterDescText.textContent = data.AdapterDescription;
  adapterSpeedBadge.textContent = data.LinkSpeed;
  specLocalIp.textContent = data.LocalIp;
  specSubnet.textContent = data.SubnetMask;
  specGateway.textContent = data.GatewayIp;
  specDns.textContent = data.DnsServers;
  specMac.textContent = data.MacAddress;
  specPublicIp.textContent = data.PublicIp;

  // 6. Health & Diagnostic
  packetLossVal.textContent = `${data.PacketLossPercent}%`;
  packetLossVal.style.color = data.PacketLossPercent > 5 ? 'var(--red)' : 'var(--green)';
  
  flappingVal.textContent = data.FlappingScore;
  flappingVal.style.color = data.FlappingScore > 2 ? 'var(--amber)' : 'var(--text-main)';

  antiBootloopSub.textContent = data.AntiBootloopMessage || 'Sécurité anti-boucle active';
  antiBootloopVal.textContent = data.AntiBootloopSafe ? 'ACTIF' : 'COOLDOWN';

  // Watchdog toggle sync
  isWatchdogActive = data.WatchdogEnabled;
  if (isWatchdogActive) {
    toggleWatchdogBtn.classList.add('active');
    toggleWatchdogText.textContent = 'Surveillance Auto : ACTIVE';
  } else {
    toggleWatchdogBtn.classList.remove('active');
    toggleWatchdogText.textContent = 'Surveillance Auto : EN PAUSE';
  }

  // 7. Latency Chart Bars
  renderLatencyChart(data.LatencyHistory || []);

  // 8. Terminal Logs
  renderTerminalLogs(data.RecentLogs || []);
}

function renderLatencyChart(history) {
  sparkBarsContainer.innerHTML = '';
  if (!history || history.length === 0) return;

  const maxVal = Math.max(...history.map(h => h.Latency > 0 ? h.Latency : 0), 80);

  history.forEach(item => {
    const bar = document.createElement('div');
    bar.className = 'spark-bar';

    if (!item.Online) {
      bar.classList.add('down');
      bar.style.height = '100%';
      bar.setAttribute('data-tip', `${item.Time} : HORS LIGNE`);
    } else {
      const heightPercent = Math.min(Math.max((item.Latency / maxVal) * 100, 8), 100);
      bar.style.height = `${heightPercent}%`;
      bar.setAttribute('data-tip', `${item.Time} : ${item.Latency} ms`);
    }

    sparkBarsContainer.appendChild(bar);
  });
}

function renderTerminalLogs(logs) {
  if (!logs || logs.length === 0) return;
  terminalConsole.innerHTML = '';
  logs.forEach(line => {
    const div = document.createElement('div');
    div.className = 'term-line';
    if (line.includes('[FATAL]')) div.classList.add('term-fatal');
    else if (line.includes('[ERROR]')) div.classList.add('term-error');
    else if (line.includes('[WARN]')) div.classList.add('term-warn');
    div.textContent = line;
    terminalConsole.appendChild(div);
  });
}

// ------------------------------------------------------------------------------
// Interactive Actions (JS -> C#)
// ------------------------------------------------------------------------------
repairAdapterBtn.addEventListener('click', () => {
  if (window.chrome && window.chrome.webview) {
    window.chrome.webview.postMessage({ action: 'restartAdapter' });
    showToast('Auto-Réparation', 'Redémarrage de la carte réseau en cours...');
  }
});

toggleWatchdogBtn.addEventListener('click', () => {
  isWatchdogActive = !isWatchdogActive;
  if (window.chrome && window.chrome.webview) {
    window.chrome.webview.postMessage({ action: 'toggleWatchdog', enabled: isWatchdogActive });
    showToast('Surveillance Réseau', isWatchdogActive ? 'Watchdog réactivé.' : 'Watchdog mis en pause.');
  }
});

cancelRebootBtn.addEventListener('click', () => {
  if (window.chrome && window.chrome.webview) {
    window.chrome.webview.postMessage({ action: 'cancelReboot' });
    showToast('Annulation', 'Commande shutdown /a envoyée.');
  }
});

minimizeBtn.addEventListener('click', () => {
  if (window.chrome && window.chrome.webview) {
    window.chrome.webview.postMessage({ action: 'minimizeToTray' });
  }
});

// Événements Mises à Jour
if (versionBadge) {
  versionBadge.addEventListener('click', () => {
    if (window.chrome && window.chrome.webview) {
      window.chrome.webview.postMessage({ action: 'checkUpdate' });
      showToast('Mise à jour', 'Recherche de nouvelle version sur GitHub...');
    }
  });
}

if (updateAlertBtn) {
  updateAlertBtn.addEventListener('click', () => {
    if (updateModal) updateModal.classList.remove('hidden');
  });
}

if (closeUpdateModalBtn) {
  closeUpdateModalBtn.addEventListener('click', () => {
    if (updateModal) updateModal.classList.add('hidden');
  });
}

if (modalLaterBtn) {
  modalLaterBtn.addEventListener('click', () => {
    if (updateModal) updateModal.classList.add('hidden');
  });
}

if (modalDownloadBtn) {
  modalDownloadBtn.addEventListener('click', () => {
    if (window.chrome && window.chrome.webview) {
      window.chrome.webview.postMessage({ action: 'openUrl', url: currentReleaseUrl });
    }
    if (updateModal) updateModal.classList.add('hidden');
  });
}
