using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Net;
using System.Runtime.CompilerServices;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Windows;
using System.Windows.Threading;
using Microsoft.AspNetCore.Builder;
using TapMyPC.Api;
using TapMyPC.Core.Devices;
using TapMyPC.Core.Feedback;
using TapMyPC.Core.Networking;
using TapMyPC.Core.Timers;
using TapMyPC.Windows.Settings;

namespace TapMyPC.Desktop.Features.Settings;

public sealed class SettingsViewModel : INotifyPropertyChanged
{
    private readonly IDeviceController device;
    private readonly LocalSettings settings;
    private readonly PairingService pairing;
    private readonly PowerScheduler scheduler;
    private readonly DispatcherTimer refreshTimer;
    private readonly Dispatcher dispatcher = Dispatcher.CurrentDispatcher;
    private WebApplication? server;
    private X509Certificate2? certificate;
    private string address;
    private string port;
    private string message = "Your network address is selected automatically. Start the host, then open the link on your phone.";
    private string pairingCode = "— — — — — —";
    private string pairingExpiry = "Generate a code when your phone is ready.";
    private string fingerprint = "Available after starting the host.";
    private string remoteUrl = "Start the host to get your phone link";
    private string networkSummary = "Detecting your network…";
    private DateTimeOffset? pairingExpires;
    private string pending = "No power action scheduled";
    private bool startupEnabled;
    private bool showNotifications;
    private bool isChangingHost;

    public SettingsViewModel(IDeviceController device, LocalSettings settings, PairingService pairing, PowerScheduler scheduler)
    {
        this.device = device;
        this.settings = settings;
        this.pairing = pairing;
        this.scheduler = scheduler;
        var saved = settings.ReadHost();
        address = saved.Address;
        port = saved.Port.ToString();
        showNotifications = saved.ShowNotifications;
        startupEnabled = StartupRegistration.Enabled;
        ToggleHost = new AsyncCommand(ToggleHostAsync);
        OpenPairing = new RelayCommand(() =>
        {
            var window = pairing.OpenPairing();
            pairingCode = window.Code;
            pairingExpires = window.ExpiresAt;
            Message = "Enter this one-time code on your phone. It works once and expires after five minutes.";
            Tick();
            Notify(nameof(PairingCode));
        });
        CopyUrl = new RelayCommand(() =>
        {
            try
            {
                if (server is null) { Message = "Start the host first to copy its phone link."; return; }
                Clipboard.SetText(RemoteUrl);
                Message = "Phone link copied. Open it on a device connected to the same Wi-Fi.";
            }
            catch (Exception ex) { Message = ex.Message; }
        });
        ExportCertificate = new RelayCommand(ExportPublicCertificate);
        RevokeDevice = new RelayCommand(() =>
        {
            try
            {
                if (SelectedDevice is null) { Message = "Select a paired device to revoke."; return; }
                pairing.Revoke(SelectedDevice.Id);
                Message = "Device access revoked.";
                Tick();
            }
            catch (Exception ex) { Message = ex.Message; }
        });
        CancelTimer = new RelayCommand(() =>
        {
            var item = scheduler.State.Pending;
            if (item is not null) scheduler.Cancel(item.Id);
            Tick();
        });
        RefreshNetwork = new RelayCommand(DetectNetwork);
        DetectNetwork();
        scheduler.Activity.Published += OnActivity;
        refreshTimer = new DispatcherTimer(TimeSpan.FromSeconds(1), DispatcherPriority.Background, (_, _) => Tick(), dispatcher);
        Tick();
    }

    public ObservableCollection<NetworkAddress> NetworkChoices { get; } = [];
    public ObservableCollection<PairedClient> Devices { get; } = [];
    public ObservableCollection<ActionNotice> Activity { get; } = [];
    public PairedClient? SelectedDevice { get; set; }
    public string Address { get => address; set { address = value; Notify(); } }
    public string Port { get => port; set { port = value; Notify(); } }
    public string Message { get => message; private set { message = value; Notify(); } }
    public string PairingCode => pairingCode;
    public string PairingExpiry => pairingExpiry;
    public string Fingerprint => fingerprint;
    public string RemoteUrl => remoteUrl;
    public string NetworkSummary => networkSummary;
    public string Pending => pending;
    public bool HasPending => scheduler.State.Pending is not null;
    public string HostStatus => isChangingHost ? "Updating host…" : server is null ? "Offline" : "Ready for your phone";
    public string HostButtonText => isChangingHost ? "Please wait…" : server is null ? "Start host" : "Stop host";
    public bool CanEditConnection => server is null && !isChangingHost;
    public bool IsHosting => server is not null && !isChangingHost;
    public bool StartupEnabled
    {
        get => startupEnabled;
        set
        {
            try { StartupRegistration.SetEnabled(value); startupEnabled = value; Message = value ? "TapMyPC will start in the tray when you sign in." : "Sign-in startup disabled."; }
            catch (Exception ex) { Message = ex.Message; }
            Notify();
        }
    }
    public bool ShowNotifications
    {
        get => showNotifications;
        set
        {
            showNotifications = value;
            try { SavePreferences(); }
            catch (Exception ex) { Message = ex.Message; }
            Notify();
        }
    }
    public AsyncCommand ToggleHost { get; }
    public RelayCommand OpenPairing { get; }
    public RelayCommand CopyUrl { get; }
    public RelayCommand ExportCertificate { get; }
    public RelayCommand RevokeDevice { get; }
    public RelayCommand CancelTimer { get; }
    public RelayCommand RefreshNetwork { get; }

    private void DetectNetwork()
    {
        try
        {
            var available = NetworkAddresses.Read();
            // Reassign after rebuilding the list, because ComboBox selection can transiently become null.
            var previous = address;
            NetworkChoices.Clear();
            NetworkChoices.Add(new(AddressSelection.Automatic, "Automatic", false, false));
            foreach (var item in available) NetworkChoices.Add(item);
            NetworkChoices.Add(new("127.0.0.1", "Localhost", false, false));
            Address = previous == "127.0.0.1" || previous == AddressSelection.Automatic || available.Any(n => n.Address == previous)
                ? previous : AddressSelection.Automatic;
            var resolved = AddressSelection.Resolve(Address, available);
            var network = available.FirstOrDefault(n => n.Address == resolved);
            networkSummary = network is null ? "Localhost · only this PC can connect" : $"{network.Name} · {resolved}";
        }
        catch (Exception ex) { networkSummary = ex.Message; }
        Notify(nameof(NetworkSummary));
    }

    private async Task ToggleHostAsync()
    {
        isChangingHost = true;
        NotifyHost();
        try
        {
            if (server is not null)
            {
                await server.StopAsync();
                await server.DisposeAsync();
                server = null;
                certificate?.Dispose();
                certificate = null;
                remoteUrl = "Start the host to get your phone link";
                Message = "Host stopped. Pending power timers still run until canceled or the app exits.";
            }
            else
            {
                DetectNetwork();
                var ip = IPAddress.Parse(AddressSelection.Resolve(Address, NetworkAddresses.Read()));
                if (!int.TryParse(Port, out var number) || number is < 1024 or > 65535)
                    throw new ArgumentException("Port must be between 1024 and 65535.");
                Message = "Starting the secure host…";
                certificate?.Dispose();
                certificate = HostCertificate.GetOrCreate(ip);
                server = await ApiHost.StartAsync(ip, number, certificate, device, pairing, scheduler);
                remoteUrl = $"https://{ip}:{number}";
                fingerprint = certificate.GetCertHashString(HashAlgorithmName.SHA256);
                SavePreferences();
                Message = IPAddress.IsLoopback(ip)
                    ? "Debugging mode: this link works only on this PC. Select Automatic in Advanced settings for phone access."
                    : "Ready. Open the phone link on the same Wi-Fi, then generate a pairing code below.";
            }
        }
        catch (Exception ex) { Message = ex.Message; }
        finally { isChangingHost = false; NotifyHost(); }
    }

    private void NotifyHost()
    {
        foreach (var name in new[] { nameof(RemoteUrl), nameof(Fingerprint), nameof(HostButtonText), nameof(CanEditConnection), nameof(IsHosting), nameof(HostStatus) }) Notify(name);
    }

    private void SavePreferences()
    {
        if (!int.TryParse(Port, out var number) || number is < 1024 or > 65535) throw new ArgumentException("Port must be between 1024 and 65535.");
        settings.SaveHost(new(Address, number, ShowNotifications));
    }

    private void ExportPublicCertificate()
    {
        try
        {
            if (certificate is null) { Message = "Start the host before exporting its certificate."; return; }
            var dialog = new Microsoft.Win32.SaveFileDialog { FileName = "TapMyPC.cer", Filter = "Public certificate (*.cer)|*.cer" };
            if (dialog.ShowDialog() == true)
            {
                System.IO.File.WriteAllBytes(dialog.FileName, certificate.Export(X509ContentType.Cert));
                Message = "Public certificate exported. No private key was included.";
            }
        }
        catch (Exception ex) { Message = ex.Message; }
    }

    private void OnActivity(ActionNotice item) => dispatcher.BeginInvoke(() =>
    {
        Message = item.Message;
        RefreshActivity();
    });

    private void RefreshActivity()
    {
        var recent = scheduler.Activity.Recent.Take(6).ToArray();
        if (Activity.FirstOrDefault()?.Sequence == recent.FirstOrDefault()?.Sequence) return;
        Activity.Clear();
        foreach (var item in recent) Activity.Add(item);
    }

    private void Tick()
    {
        if (pairingExpires is { } expiry)
        {
            var remaining = expiry - DateTimeOffset.UtcNow;
            pairingExpiry = remaining > TimeSpan.Zero ? $"One use · expires in {Math.Ceiling(remaining.TotalSeconds)} seconds" : "Expired. Generate a new code.";
            if (remaining <= TimeSpan.Zero) { pairingCode = "— — — — — —"; pairingExpires = null; Notify(nameof(PairingCode)); }
            Notify(nameof(PairingExpiry));
        }
        var clients = pairing.Clients;
        if (!Devices.Select(d => d.Id).SequenceEqual(clients.Select(d => d.Id)))
        {
            Devices.Clear();
            foreach (var client in clients) Devices.Add(client);
            if (pairingExpires is not null && clients.Count > pairedCount)
            {
                pairingExpires = null;
                pairingCode = "Connected";
                pairingExpiry = "Phone paired. Generate another code to add a different device.";
                Notify(nameof(PairingCode)); Notify(nameof(PairingExpiry));
            }
        }
        pairedCount = clients.Count;
        pending = scheduler.State.Pending is { } item
            ? $"{item.Action} in {Math.Max(0, Math.Ceiling((item.DueAt - DateTimeOffset.UtcNow).TotalSeconds))} seconds"
            : "No power action scheduled";
        Notify(nameof(Pending)); Notify(nameof(HasPending));
        RefreshActivity();
    }
    private int pairedCount;

    public async Task ShutdownAsync()
    {
        refreshTimer.Stop();
        scheduler.Activity.Published -= OnActivity;
        scheduler.Dispose();
        if (server is not null) { await server.StopAsync(); await server.DisposeAsync(); server = null; }
        certificate?.Dispose();
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    private void Notify([CallerMemberName] string? name = null) => PropertyChanged?.Invoke(this, new(name));
}
