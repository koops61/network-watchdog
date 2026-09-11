using System;
using System.Threading;
using System.Windows.Forms;

namespace NetworkWatchdog
{
    internal static class Program
    {
        private static Mutex? _mutex;

        [STAThread]
        private static void Main(string[] args)
        {
            // Empêcher l'exécution de doublons (Instance unique)
            const string appName = "Global\\NetworkWatchdog_Unique_Instance_Mutex";
            _mutex = new Mutex(true, appName, out bool createdNew);

            if (!createdNew)
            {
                MessageBox.Show("Network Watchdog est déjà en cours d'exécution.\nVérifiez dans la zone de notification (près de l'horloge) !", 
                                "Network Watchdog", 
                                MessageBoxButtons.OK, 
                                MessageBoxIcon.Information);
                return;
            }

            bool startMinimized = false;
            foreach (var arg in args)
            {
                if (arg.Equals("--tray", StringComparison.OrdinalIgnoreCase) || 
                    arg.Equals("-minimized", StringComparison.OrdinalIgnoreCase))
                {
                    startMinimized = true;
                    break;
                }
            }

            ApplicationConfiguration.Initialize();
            Application.Run(new MainForm(startMinimized));
        }
    }
}
