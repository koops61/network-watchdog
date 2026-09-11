// ==============================================================================
// Network Watchdog - Frontend Application Logic
// ==============================================================================

const connectionBadge = document.getElementById('connectionBadge');
const badgeText = document.getElementById('badgeText');
const activeAdapterName = document.getElementById('activeAdapterName');
const adapterStatusDetail = document.getElementById('adapterStatusDetail');
const latencyValue = document.getElementById('latencyValue');
const latencyRating = document.getElementById('latencyRating');
const flappingScore = document.getElementById('flappingScore');
const flappingSubtext = document.getElementById('flappingSubtext');
const antiBootloopStatus = document.getElementById('antiBootloopStatus');
const antiBootloopDetail = document.getElementById('antiBootloopDetail');
const lastUpdatedTime = document.getElementById('lastUpdatedTime');
const barsContainer = document.getElementById('barsContainer');
const logsTerminal = document.getElementById('logsTerminal');
const cancelRebootBtn = document.getElementById('cancelRebootBtn');
const refreshLogsBtn = document.getElementById('refreshLogsBtn');
const toastAlert = document.getElementById('toastAlert');
const toastTitle = document.getElementById('toastTitle');
const toastMessage = document.getElementById('toastMessage');
const versionBadge = document.getElementById('versionBadge');
const updateLinkBtn = document.getElementById('updateLinkBtn');
const updateLinkText = document.getElementById('updateLinkText');

function showToast(title, message, isError = false) {
  toastTitle.textContent = title;
  toastMessage.textContent = message;
  toastAlert.classList.remove('hidden');
  setTimeout(() => {
    toastAlert.classList.add('hidden');
  }, 4000);
}

// 1. Fetch & Render Live Status
async function updateStatus() {
  try {
    const res = await fetch('/api/status?t=' + Date.now());
    if (!res.ok) throw new Error('Status unavailable');
    const data = await res.json();

    // Version & Updates
    if (data.app_version && versionBadge) {
      versionBadge.textContent = `v${data.app_version}`;
    }
    if (data.update_available && updateLinkBtn) {
      updateLinkBtn.classList.remove('hidden');
      if (data.release_url) updateLinkBtn.href = data.release_url;
      if (data.latest_version && updateLinkText) {
        updateLinkText.textContent = `Mise à jour ${data.latest_version}`;
      }
    } else if (updateLinkBtn) {
      updateLinkBtn.classList.add('hidden');
    }

    // Adapter
    activeAdapterName.textContent = data.active_adapter || 'Détecté';
    adapterStatusDetail.textContent = data.active_adapter ? 'Interface surveillée active' : 'Recherche de carte...';

    // Status Badge
    connectionBadge.className = 'status-badge';
    if (data.status === 'UP') {
      connectionBadge.classList.add('status-online');
      badgeText.textContent = 'En Ligne';
    } else if (data.status === 'UNSTABLE') {
      connectionBadge.classList.add('status-unstable');
      badgeText.textContent = 'Réseau Instable';
    } else if (data.status === 'DOWN') {
      connectionBadge.classList.add('status-offline');
      badgeText.textContent = `Hors Ligne (${data.consecutive_failures} échecs)`;
    } else {
      connectionBadge.classList.add('status-loading');
      badgeText.textContent = 'Démarrage...';
    }

    // Latency
    if (data.latency_ms >= 0) {
      latencyValue.innerHTML = `${data.latency_ms} <small>ms</small>`;
      if (data.latency_ms < 30) {
        latencyRating.textContent = 'Connexion Ultra-Rapide (Fibre/LAN)';
        latencyRating.style.color = 'var(--color-green)';
      } else if (data.latency_ms < 80) {
        latencyRating.textContent = 'Latence Normale';
        latencyRating.style.color = 'var(--color-cyan)';
      } else {
        latencyRating.textContent = 'Latence Élevée';
        latencyRating.style.color = 'var(--color-amber)';
      }
    } else {
      latencyValue.innerHTML = `-- <small>ms</small>`;
      latencyRating.textContent = 'Aucune réponse aux pings';
      latencyRating.style.color = 'var(--color-red)';
    }

    // Flapping & Instability
    flappingScore.textContent = data.flapping_score || 0;
    if (data.flapping_score > 0) {
      flappingSubtext.textContent = `${data.flapping_score} transition(s) déco/reco récentes`;
      flappingScore.style.color = 'var(--color-amber)';
    } else {
      flappingSubtext.textContent = 'Connexion continue et stable';
      flappingScore.style.color = 'var(--text-main)';
    }

    // Updated Time
    lastUpdatedTime.textContent = `Dernière mesure : ${data.updated_at || '--:--:--'}`;

    // Render Bars Chart
    renderChart(data.recent_history || []);

  } catch (err) {
    console.warn('Erreur de synchronisation du statut:', err);
    connectionBadge.className = 'status-badge status-loading';
    badgeText.textContent = 'En attente du watchdog';
  }
}

// 2. Render Latency Bar Chart
function renderChart(history) {
  barsContainer.innerHTML = '';
  if (!history || history.length === 0) {
    barsContainer.innerHTML = '<div style="color:var(--text-faint); font-size:0.8rem; margin:auto;">En attente des premiers échantillons...</div>';
    return;
  }

  const maxVal = Math.max(...history.map(h => h.latency > 0 ? h.latency : 0), 100);

  history.forEach(item => {
    const bar = document.createElement('div');
    bar.className = 'latency-bar';

    if (!item.online) {
      bar.classList.add('down');
      bar.style.height = '100%';
      bar.setAttribute('data-tooltip', `${item.time} : HORS LIGNE (0 ms)`);
    } else {
      const heightPercent = Math.min(Math.max((item.latency / maxVal) * 100, 15), 100);
      bar.style.height = `${heightPercent}%`;
      bar.setAttribute('data-tooltip', `${item.time} : ${item.latency} ms`);
    }

    barsContainer.appendChild(bar);
  });
}

// 3. Fetch Logs
async function updateLogs() {
  try {
    const res = await fetch('/api/logs?t=' + Date.now());
    if (!res.ok) return;
    const text = await res.text();
    const lines = text.trim().split(/\r?\n/).slice(-30); // 30 dernières lignes

    if (lines.length > 0 && lines[0].trim() !== '') {
      logsTerminal.innerHTML = '';
      lines.forEach(line => {
        const div = document.createElement('div');
        div.className = 'log-entry';

        if (line.includes('[FATAL]')) {
          div.classList.add('log-fatal');
        } else if (line.includes('[ERROR]')) {
          div.classList.add('log-error');
        } else if (line.includes('[WARN]')) {
          div.classList.add('log-warn');
        } else {
          div.classList.add('log-info');
        }

        div.textContent = line;
        logsTerminal.appendChild(div);
      });
      logsTerminal.scrollTop = logsTerminal.scrollHeight;
    }
  } catch (err) {
    console.warn('Erreur lecture logs:', err);
  }
}

// 4. Cancel Reboot Action
cancelRebootBtn.addEventListener('click', async () => {
  try {
    const res = await fetch('/api/cancel-reboot', { method: 'POST' });
    const data = await res.json();
    if (data.success) {
      showToast('Redémarrage Annulé', data.message || 'La commande shutdown /a a été exécutée avec succès.');
    } else {
      showToast('Information', data.message || 'Aucun redémarrage n\'était planifié.', true);
    }
  } catch (err) {
    showToast('Erreur', 'Impossible de contacter le serveur local.', true);
  }
});

refreshLogsBtn.addEventListener('click', () => {
  updateLogs();
  showToast('Actualisé', 'Les journaux ont été rechargés.');
});

// Periodic Poll
updateStatus();
updateLogs();
setInterval(updateStatus, 2500);
setInterval(updateLogs, 5000);
