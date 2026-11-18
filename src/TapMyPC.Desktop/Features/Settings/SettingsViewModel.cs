using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Net;
using System.Net.NetworkInformation;
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Windows;
using System.Windows.Threading;
using Microsoft.AspNetCore.Builder;
using TapMyPC.Api;
using TapMyPC.Api.Contracts;
using System.Windows.Media.Imaging;
using TapMyPC.Core.Devices;
using TapMyPC.Core.Bluetooth;
using TapMyPC.Core.Audio;
using TapMyPC.Core.Display;
using TapMyPC.Core.Shortcuts;
using TapMyPC.Core.Feedback;
using TapMyPC.Core.Networking;
using TapMyPC.Core.Timers;
using TapMyPC.Windows.Settings;

namespace TapMyPC.Desktop.Features.Settings;

public sealed class SettingsViewModel : INotifyPropertyChanged
{
    private readonly IDeviceController device;
    private readonly IBluetoothController? bluetooth;
    private readonly IAudioOutputController? outputs;
    private readonly ShortcutCatalog? shortcuts;
    private readonly IMonitorController? monitors;
    private readonly LocalSettings settings;
    private readonly PairingService pairing;
    private readonly PowerScheduler scheduler;
    private readonly DispatcherTimer refreshTimer;
    private readonly Dispatcher dispatcher = Dispatcher.CurrentDispatcher;
    private readonly SemaphoreSlim hostGate = new(1, 1);
    private ConnectionAdvertisement? advertisement;
    private IPAddress? listeningAddress;
    private bool connectionsEnabled;
    private bool shuttingDown;
    private int networkCheck;
    private string discoverySummary = "";
    private WebApplication? server;
    private X509Certificate2? certificate;
    private string address;
    private string port;
    private string message = "Your network address is selected automatically. Start connections, then select Pair a Phone to scan a pairing QR.";
    private BitmapSource? pairingQrImage;
    private string pairingCode = "— — — — — —";
    private string pairingExpiry = "Generate a QR when your phone is ready.";
    private string fingerprint = "Available after starting the host.";
    private string remoteUrl = "Start connections, then select Pair a Phone";
    private string networkSummary = "Detecting your network…";
    private DateTimeOffset? pairingExpires;
    private string pending = "No power action scheduled";
    private bool startupEnabled;
    private bool showNotifications;
    private bool isChangingHost;
    private IReadOnlyList<PairedClient> connectedClients = Array.Empty<PairedClient>();

    public SettingsViewModel(IDeviceController device, LocalSettings settings, PairingService pairing, PowerScheduler scheduler, IBluetoothController? bluetooth = null, IAudioOutputController? outputs = null, ShortcutCatalog? shortcuts = null, IMonitorController? monitors = null)
    {
        this.device = device;
        this.bluetooth = bluetooth;
        this.outputs = outputs; this.shortcuts = shortcuts; this.monitors = monitors;
        ShortcutSettings = shortcuts is null ? null : new ShortcutsViewModel(shortcuts);
        this.settings = settings;
        Appearance = new AppearanceViewModel(settings);
        this.pairing = pairing;
        this.scheduler = scheduler;
        var saved = settings.ReadHost();
        address = saved.Address;
        port = saved.Port.ToString();
        showNotifications = saved.ShowNotifications;
        connectionsEnabled = saved.ConnectionsEnabled;
        startupEnabled = StartupRegistration.Enabled;
        ToggleHost = new AsyncCommand(ToggleHostAsync);
        OpenPairing = new RelayCommand(() =>
        {
            if (server is null || certificate is null) { Message = "Select Start connections before adding a phone."; return; }
            var window = pairing.OpenPairingSession();
            try
            {
                pairingQrImage = Features.Settings.PairingQrImage.Create(PairingInvitation.CreateJson(Environment.MachineName, RemoteUrl, Fingerprint, window));
            }
            catch
            {
                pairing.ClosePairing();
                ClearPairingQr();
                Message = "Could not generate pairing QR. Please try again.";
                return;
            }
            Notify(nameof(PairingQrImage)); Notify(nameof(HasPairingQr)); Notify(nameof(PairingHint)); Notify(nameof(PairingButtonText));
            pairingCode = window.Code;
            pairingExpires = window.ExpiresAt;
            Message = "Scan this QR in the TapMyPC Android app.\nThe code below also works for browser pairing.";
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
        NetworkChange.NetworkAddressChanged += OnNetworkChanged;
    }

    public AppearanceViewModel Appearance { get; }
    public ShortcutsViewModel? ShortcutSettings { get; }
    public ObservableCollection<NetworkAddress> NetworkChoices { get; } = [];
    public ObservableCollection<PairedClient> Devices { get; } = [];
    public ObservableCollection<ActionNotice> Activity { get; } = [];
    public PairedClient? SelectedDevice { get; set; }
    public string Address { get => address; set { address = value; Notify(); } }
    public string Port { get => port; set { port = value; Notify(); } }
    public string Message { get => message; private set { message = value; Notify(); } }
    public BitmapSource? PairingQrImage => pairingQrImage;
    public bool HasPairingQr => pairingQrImage is not null;
    public string VersionLabel => "v" + (typeof(SettingsViewModel).Assembly.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion ?? "unknown").Replace("+", " (build ") + ")";
    public string AppHeading => $"TAPMYPC    {VersionLabel}";
    public string PairingButtonText => HasPairingQr ? "Refresh pairing QR" : pairing.Clients.Count > 0 ? "Add another phone" : "Show pairing QR";
    public string PairingHint => !IsHosting
        ? "Connections are stopped. Start connections to pair or reconnect a phone."
        : HasPairingQr
            ? "On Android: Add PC → Scan PC QR. The QR hides automatically after successful pairing."
            : pairing.Clients.Count > 0
                ? "Your paired phones reconnect automatically. Use Add another phone only for a new device."
                : "Your pairing QR appears here. If it expired, select Show pairing QR to generate another.";
    public string PairingCode => pairingCode;
    public string PairingExpiry => pairingExpiry;
    public string Fingerprint => fingerprint;
    public string RemoteUrl => remoteUrl;
    public string NetworkSummary => networkSummary;
    public string Pending => pending;
    public bool HasPending => scheduler.State.Pending is not null;
    public bool HasConnectedClients => connectedClients.Count > 0;
    public string ConnectionSummary => connectedClients.Count == 0 ? "No active remote" : string.Join(", ", connectedClients.Select(c => c.Name));
    public string ConnectionHint => HasConnectedClients
        ? $"Recent authenticated activity from {ConnectionSummary}. Goes idle after 10 seconds without activity; availability checks also count."
        : "A saved pairing does not mean a remote is currently online. Open the phone app to connect.";
    public string HostStatus => isChangingHost ? "Updating host…" : server is null ? connectionsEnabled ? "Waiting for trusted network" : "Connections stopped" : HasConnectedClients ? connectedClients.Count == 1 ? "Remote connected" : $"{connectedClients.Count} remotes connected" : "Ready for your phone";
    public string HostButtonText => isChangingHost ? "Please wait…" : connectionsEnabled ? "Stop connections" : "Start connections";
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

    public async Task InitializeAsync()
    {
        await hostGate.WaitAsync();
        try { if (connectionsEnabled) await StartListenerAsync(); else Message = "Connections are stopped. Start connections when you are ready; paired phones are remembered."; }
        catch (Exception ex) { Message = ex.Message; }
        finally { hostGate.Release(); NotifyHost(); }
    }

    private async Task ToggleHostAsync()
    {
        await hostGate.WaitAsync();
        isChangingHost = true; NotifyHost();
        try
        {
            if (connectionsEnabled)
            {
                // Pause first and close the listener even if persisting the choice fails.
                connectionsEnabled = false;
                Exception? saveError = null;
                try { SavePreferences(); } catch (Exception ex) { saveError = ex; }
                await StopListenerAsync();
                Message = saveError is null
                    ? "Connections stopped and will stay stopped after restart. Paired phones are remembered. Pending timers continue."
                    : $"Connections stopped, but the pause could not be saved: {saveError.Message}";
            }
            else
            {
                connectionsEnabled = true;
                SavePreferences();
                await StartListenerAsync();
            }
        }
        catch (Exception ex) { Message = ex.Message; }
        finally { isChangingHost = false; hostGate.Release(); NotifyHost(); }
    }

    private async Task StartListenerAsync()
    {
        if (shuttingDown || !connectionsEnabled || server is not null) return;
        DetectNetwork();
        var ip = IPAddress.Parse(AddressSelection.Resolve(Address, NetworkAddresses.Read()));
        if (!NetworkTrust.IsTrusted(ip))
            throw new InvalidOperationException("Connections are waiting: Windows must mark this network Private or Domain. Use a trusted network; public networks are not enabled automatically.");
        if (!int.TryParse(Port, out var number) || number is < 1024 or > 65535)
            throw new ArgumentException("Port must be between 1024 and 65535.");
        var identity = settings.ReadIdentity();
        var nextCertificate = HostCertificate.GetOrCreate(ip, identity?.CertificateThumbprint);
        try
        {
            if (identity is null) settings.SaveIdentity(new(nextCertificate.Thumbprint));
            var nextServer = await ApiHost.StartAsync(ip, number, nextCertificate, device, pairing, scheduler,
                bluetooth: bluetooth, outputs: outputs, shortcuts: shortcuts, monitors: monitors);
            certificate = nextCertificate; server = nextServer; listeningAddress = ip;
        }
        catch { nextCertificate.Dispose(); throw; }
        remoteUrl = $"https://{ip}:{number}";
        fingerprint = certificate.GetCertHashString(HashAlgorithmName.SHA256);
        discoverySummary = "";
        if (!IPAddress.IsLoopback(ip))
        {
            try { advertisement = new ConnectionAdvertisement(ip, number, fingerprint); }
            catch { discoverySummary = " Discovery is unavailable; saved addresses and QR pairing still work."; }
        }
        Message = "Ready for paired phones. Open the Android app to reconnect." + discoverySummary;
        NotifyHost();
        if (pairing.Clients.Count == 0) OpenPairing.Execute(null);
    }

    private async Task StopListenerAsync()
    {
        pairing.ClosePairing(); ClearPairingQr();
        pairingCode = "— — — — — —"; pairingExpires = null;
        pairingExpiry = "Pairings are remembered. Start connections to reconnect.";
        advertisement?.Dispose(); advertisement = null;
        if (server is not null) { await server.StopAsync(); await server.DisposeAsync(); server = null; }
        pairing.ClearPresence();
        RefreshPresence();
        listeningAddress = null; certificate?.Dispose(); certificate = null;
        remoteUrl = "Browser address available when connections are running";
        Notify(nameof(PairingCode)); Notify(nameof(PairingExpiry));
    }

    private void OnNetworkChanged(object? sender, EventArgs e) =>
        dispatcher.BeginInvoke(() => _ = CheckNetworkAsync());

    private async Task CheckNetworkAsync()
    {
        if (shuttingDown || !connectionsEnabled || !await hostGate.WaitAsync(0)) return;
        try
        {
            IPAddress? current = null;
            try { current = IPAddress.Parse(AddressSelection.Resolve(Address, NetworkAddresses.Read())); } catch { }
            if (current is null || !NetworkTrust.IsTrusted(current))
            {
                if (server is not null) await StopListenerAsync();
                Message = "Waiting for a trusted Private/Domain network. Your saved pairings are unchanged.";
            }
            else if (server is null || !current.Equals(listeningAddress))
            {
                await StopListenerAsync();
                await StartListenerAsync();
            }
        }
        catch (Exception ex) { Message = ex.Message; }
        finally { hostGate.Release(); NotifyHost(); }
    }

    private void NotifyHost()
    {
        foreach (var name in new[] { nameof(RemoteUrl), nameof(Fingerprint), nameof(HostButtonText), nameof(CanEditConnection), nameof(IsHosting), nameof(HostStatus), nameof(PairingHint), nameof(PairingButtonText) }) Notify(name);
        RefreshPresence();
    }

    private void SavePreferences()
    {
        if (!int.TryParse(Port, out var number) || number is < 1024 or > 65535) throw new ArgumentException("Port must be between 1024 and 65535.");
        settings.SaveHost(new(Address, number, ShowNotifications, ConnectionsEnabled: connectionsEnabled));
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

    private void RefreshPresence()
    {
        var active = server is null || isChangingHost ? Array.Empty<PairedClient>() : pairing.ActiveClients;
        if (connectedClients.SequenceEqual(active)) return;
        connectedClients = active;
        foreach (var name in new[] { nameof(HasConnectedClients), nameof(ConnectionSummary), nameof(ConnectionHint), nameof(HostStatus) }) Notify(name);
    }

    private void Tick()
    {
        RefreshPresence();
        if (++networkCheck % 10 == 0) _ = CheckNetworkAsync();
        if (!pairing.IsPairingOpen) ClearPairingQr();
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
        if (clients.Count > 0 && pairingExpires is null && !pairing.IsPairingOpen)
        {
            pairingExpiry = "Paired phones reconnect automatically. No QR is needed for normal use.";
            Notify(nameof(PairingExpiry));
        }
        pairedCount = clients.Count;
        Notify(nameof(PairingHint)); Notify(nameof(PairingButtonText));
        pending = scheduler.State.Pending is { } item
            ? $"{item.Action} in {Math.Max(0, Math.Ceiling((item.DueAt - DateTimeOffset.UtcNow).TotalSeconds))} seconds"
            : "No power action scheduled";
        Notify(nameof(Pending)); Notify(nameof(HasPending));
        RefreshActivity();
    }
    private void ClearPairingQr()
    {
        if (pairingQrImage is null) return;
        pairingQrImage = null;
        Notify(nameof(PairingQrImage)); Notify(nameof(HasPairingQr)); Notify(nameof(PairingHint)); Notify(nameof(PairingButtonText));
    }
    private int pairedCount;

    public async Task ShutdownAsync()
    {
        shuttingDown = true;
        Appearance.Dispose();
        NetworkChange.NetworkAddressChanged -= OnNetworkChanged;
        refreshTimer.Stop();
        scheduler.Activity.Published -= OnActivity;
        await hostGate.WaitAsync();
        try { await StopListenerAsync(); scheduler.Dispose(); }
        finally { hostGate.Release(); }
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    private void Notify([CallerMemberName] string? name = null) => PropertyChanged?.Invoke(this, new(name));
}
