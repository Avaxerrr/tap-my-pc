using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography.X509Certificates;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using TapMyPC.Core.Devices;
using TapMyPC.Core.Timers;
using TapMyPC.Desktop;
using TapMyPC.Desktop.Features.Settings;
using TapMyPC.Windows.Settings;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        var app = new Application();
        app.Dispatcher.InvokeAsync(async () => {
            try { await Run(); app.Shutdown(0); }
            catch (Exception ex) { Console.Error.WriteLine(ex); app.Shutdown(1); }
        });
        app.Run();
    }
    private static void Check(bool condition, string description) {
        if (!condition) throw new InvalidOperationException(description);
    }
    private static IEnumerable<T> Descendants<T>(DependencyObject parent) where T : DependencyObject
    {
        for (var i = 0; i < VisualTreeHelper.GetChildrenCount(parent); i++) {
            var child = VisualTreeHelper.GetChild(parent, i);
            if (child is T found) yield return found;
            foreach (var nested in Descendants<T>(child)) yield return nested;
        }
    }
    private static async Task Run()
    {
        var directory = Path.Combine(Path.GetTempPath(), "TapMyPC-cert-ui-" + Guid.NewGuid().ToString("N"));
        var settings = new LocalSettings(directory);
        using var initial = HostCertificate.CreateNew(IPAddress.Loopback);
        var owned = new List<string> { initial.Thumbprint };
        settings.SaveIdentity(new(initial.Thumbprint));
        var portProbe = new TcpListener(IPAddress.Loopback, 0); portProbe.Start();
        var port = ((IPEndPoint)portProbe.LocalEndpoint).Port; portProbe.Stop();
        settings.SaveHost(new("127.0.0.1", port));
        var pairing = new PairingService(settings, TimeProvider.System);
        var oldToken = pairing.Pair(pairing.OpenPairing().Code, "UI test phone");
        var device = new SimulatedDevice();
        using var scheduler = new PowerScheduler(device, TimeProvider.System);
        var pending = scheduler.Schedule(PowerAction.Sleep, 1800);
        var vm = new SettingsViewModel(device, settings, pairing, scheduler, enableBluetoothTransport: Environment.GetCommandLineArgs().Contains("--bluetooth"));
        var window = new MainWindow { DataContext = vm, Left = -10000, Top = -10000, ShowActivated = false, ShowInTaskbar = false };
        try {
            window.Show();
            await vm.InitializeAsync();
            Check(vm.IsHosting, "Initial test listener");
            if (Environment.GetCommandLineArgs().Contains("--bluetooth")) Check(vm.BluetoothConnectionSummary.StartsWith("Bluetooth ready"), "Bluetooth transport starts with global connections");
            vm.RequestIdentityReset.Execute(null);
            Check(vm.IdentityResetRequested, "Reset confirmation opens");
            vm.CancelIdentityReset.Execute(null);
            Check(!vm.IdentityResetRequested && settings.ReadIdentity()!.CertificateThumbprint == initial.Thumbprint &&
                pairing.Authorize(oldToken), "Cancel preserves identity and authorization");
            vm.RequestIdentityReset.Execute(null);
            ((System.Windows.Controls.Primitives.ToggleButton)window.FindName("SettingsDrawerToggle")).IsChecked = true;
            await Task.Delay(350);
            var advanced = Descendants<Expander>(window).Single(e => e.Header?.ToString() == "Advanced Network & Security");
            advanced.IsExpanded = true; window.UpdateLayout();
            var confirm = Descendants<Button>(window).Single(b => b.Content?.ToString() == "Reset and revoke all phones");
            confirm.BringIntoView(); await Task.Delay(100); window.UpdateLayout();
            Check(confirm.IsVisible, "Reset confirmation is visible");
            var bitmap = new RenderTargetBitmap((int)window.ActualWidth, (int)window.ActualHeight, 96, 96, PixelFormats.Pbgra32);
            bitmap.Render(window);
            Directory.CreateDirectory("artifacts/certificate-ui-check");
            var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
            using (var output = File.Create("artifacts/certificate-ui-check/confirmation.png")) encoder.Save(output);
            vm.ConfirmIdentityReset.Execute(null);
            for (var attempt = 0; attempt < 100 && !vm.ConfirmIdentityReset.CanExecute(null); attempt++) await Task.Delay(50);
            owned.Add(settings.ReadIdentity()!.CertificateThumbprint);
            Check(vm.ConfirmIdentityReset.CanExecute(null) && !vm.IdentityResetRequested, "Reset completes");
            Check(vm.IsHosting && vm.HasPairingQr, "Reset restarts host with a fresh QR");
            if (Environment.GetCommandLineArgs().Contains("--bluetooth")) Check(vm.BluetoothConnectionSummary.StartsWith("Bluetooth ready"), "Bluetooth restarts after identity reset");
            Check(!pairing.Authorize(oldToken), "Reset revokes previous phone");
            Check(settings.ReadIdentity()!.CertificateThumbprint != initial.Thumbprint, "Replacement identity is saved");
            Check(scheduler.State.Pending?.Id == pending.Id, "Pending timer is preserved");
            vm.ToggleHost.Execute(null);
            for (var attempt = 0; attempt < 100 && !vm.ToggleHost.CanExecute(null); attempt++) await Task.Delay(50);
            Check(!vm.IsHosting && !settings.ReadHost().ConnectionsEnabled, "Pause is persisted");
            vm.RequestIdentityReset.Execute(null); vm.ConfirmIdentityReset.Execute(null);
            for (var attempt = 0; attempt < 100 && !vm.ConfirmIdentityReset.CanExecute(null); attempt++) await Task.Delay(50);
            owned.Add(settings.ReadIdentity()!.CertificateThumbprint);
            Check(!vm.IsHosting && !settings.ReadHost().ConnectionsEnabled && !vm.HasPairingQr,
                "Offline reset retains pause without exposing a listener or QR");
            Check(scheduler.State.Pending?.Id == pending.Id, "Offline recovery preserves timer");
            vm.ToggleHost.Execute(null);
            for (var attempt = 0; attempt < 100 && !vm.ToggleHost.CanExecute(null); attempt++) await Task.Delay(50);
            Check(vm.IsHosting && vm.HasPairingQr, "Explicit resume displays recovery QR");
            if (Environment.GetCommandLineArgs().Contains("--bluetooth")) Check(vm.BluetoothConnectionSummary.StartsWith("Bluetooth ready"), "Bluetooth resumes after pause");
            Console.WriteLine("PASS: WPF cancel/confirm, active and paused recovery, listener restart, fresh QR, revocation, and pending timer preservation.");
        }
        finally {
            var saved = settings.ReadIdentity();
            if (saved is not null) owned.Add(saved.CertificateThumbprint);
            await vm.ShutdownAsync(); window.Hide();
            using var store = new X509Store(StoreName.My, StoreLocation.CurrentUser); store.Open(OpenFlags.ReadWrite);
            foreach (var cert in store.Certificates.Cast<X509Certificate2>().Where(c => owned.Contains(c.Thumbprint)))
                { using (cert) store.Remove(cert); }
            if (Directory.Exists(directory)) Directory.Delete(directory, true);
        }
    }
    private sealed class SimulatedDevice : IDeviceController
    {
        public DeviceCapabilities Capabilities => new(true, true, true, true, true);
        public AudioState ReadAudio() => new(40, false);
        public void SetVolume(int percent) { }
        public void SetMute(bool muted) { }
        public void StepVolume(VolumeDirection direction) { }
        public void SendMedia(MediaAction action) { }
        public void TurnOffDisplays() { }
        public void ExecutePower(PowerAction action) => throw new InvalidOperationException("Native power disabled in UI tests.");
    }
}
