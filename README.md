# 🛡️ Network Watchdog - Application Bureau & Auto-Réparation pour Windows

**Network Watchdog** est une application Windows complète dotée d'une interface graphique moderne (Dark Glassmorphism) et d'un moteur d'auto-réparation automatique :
1. **Surveillance & Télémétrie en direct** : Débit en temps réel (**Download/Upload** en Ko/s ou Mo/s), carte d'identité réseau (IP locale, MAC, Vitesse 2.5 Gbps, Passerelle, DNS, IP publique), triple test ping simultané (Box, Cloudflare, Google), perte de paquets et score d'instabilité (« déco/reco »).
2. **Auto-Réparation Niveau 1** : Redémarrage logiciel de la carte réseau active en cas de perte de réseau ou d'instabilité avérée.
3. **Auto-Réparation Niveau 2** : Si le problème persiste après 2 tentatives, redémarrage propre du PC avec compte à rebours de prévenance de 60 secondes et **protection inviolable contre les boucles de redémarrage (Anti-Bootloop)**.
4. **Zone de Notification (System Tray)** : Réduction discrète près de l'horloge Windows avec menu contextuel clic droit.

---

## 🚀 Démarrage Rapide

| Action | Fichier à exécuter | Description |
| :--- | :--- | :--- |
| **Lancer l'Application Bureau** | `NetworkWatchdog.exe` | **Double-clic pour lancer** la superbe interface graphique de surveillance avec métriques en temps réel. |
| **Activer le démarrage auto avec Windows** | `install.bat` | *(Clic droit -> Exécuter en tant qu'admin)* Configure la tâche planifiée pour démarrer automatiquement avec le PC avec privilèges élevés. |
| **Annuler un redémarrage d'urgence** | `cancel_reboot.bat` | Exécute immédiatement `shutdown /a` pour annuler le redémarrage du PC. |
| **Recompiler l'application (si besoin)** | `build.bat` | Recompile le projet C# .NET 10 en mode Single-File Release et met à jour `NetworkWatchdog.exe`. |
| **Désinstaller le démarrage auto** | `uninstall.bat` | *(Clic droit -> Exécuter en tant qu'admin)* Supprime la tâche planifiée Windows. |

---

## ⚙️ Configuration (`config.json`)

Vous pouvez personnaliser tous les seuils en ouvrant le fichier `config.json` avec le Bloc-notes ou votre éditeur :

```json
{
  "ping_targets": ["1.1.1.1", "1.0.0.1"],
  "ping_timeout_ms": 1000,
  "check_interval_seconds": 5,
  "history_window_size": 30,
  "unstable_flapping_threshold": 3,
  "consecutive_failures_before_adapter_reset": 3,
  "adapter_restart_wait_seconds": 20,
  "max_adapter_retries_before_reboot": 2,
  "reboot_countdown_seconds": 60,
  "anti_bootloop_cooldown_minutes": 20,
  "target_adapter_name": "",
  "enable_desktop_notifications": true,
  "enable_sound_alert": true,
  "log_file": "logs/network_watchdog.log",
  "max_log_size_mb": 10
}
```

### Explication des paramètres :
- `ping_targets` : Adresses IP ultra-rapides et fiables interrogées pour tester l'accès internet.
- `check_interval_seconds` : Période de test (par défaut toutes les 5 secondes).
- `unstable_flapping_threshold` : Seuil de détections « déco/reco » dans la fenêtre récente au-delà duquel la connexion est déclarée « instable ».
- `consecutive_failures_before_adapter_reset` : Nombre d'échecs consécutifs avant de relancer la carte réseau (3 échecs × 5s = 15 secondes d'indisponibilité).
- `adapter_restart_wait_seconds` : Temps accordé à la carte pour négocier son IP et sa passerelle DHCP (20 secondes).
- `max_adapter_retries_before_reboot` : Nombre de redémarrages de carte tentés avant de décider du reboot du PC (par défaut : 2).
- `reboot_countdown_seconds` : Temps de prévenance avec message à l'écran avant le redémarrage effectif (60 secondes).
- `anti_bootloop_cooldown_minutes` : **Sécurité critique** : temps minimal obligatoire (20 min) entre deux reboots automatiques pour éviter toute boucle infinie si la panne vient de la box ou d'un câble débranché.
- `target_adapter_name` : Laissez vide `""` pour la détection automatique ou indiquez le nom de votre carte (ex: `"Ethernet"`, `"Wi-Fi"`).

---

## 🔒 Sécurité Anti-Boucle de Redémarrage (Anti-Bootloop)

Si votre box internet s'éteint ou si votre câble réseau est accidentellement arraché, un outil mal configuré redémarrerait votre ordinateur indéfiniment. 

**Network Watchdog intègre un mécanisme de sécurité inviolable** :
- L'état est mémorisé sur disque dans `state.json`.
- Si le PC a déjà redémarré suite à une panne réseau dans les **20 dernières minutes** (`anti_bootloop_cooldown_minutes`) et que le réseau est toujours absent au redémarrage, **le redémarrage automatique est immédiatement bloqué**.
- Une alerte critique est consignée dans les logs invitant à vérifier le matériel (routeur, box, câble).

---

## 📊 Tableau de bord Web

Pour une expérience visuelle moderne, lancez `start_dashboard.bat`. Le tableau de bord affiche :
- L'état de connexion en direct (En Ligne, Hors Ligne, Instable) avec indicateurs lumineux.
- La latence mesurée et l'historique sous forme de barres graphiques interactives.
- Le nom de la carte réseau active détectée dynamiquement.
- L'état de la sécurité Anti-Bootloop.
- Le flux des journaux d'événements et des réparations effectuées.
- Un bouton d'annulation immédiate du redémarrage.
