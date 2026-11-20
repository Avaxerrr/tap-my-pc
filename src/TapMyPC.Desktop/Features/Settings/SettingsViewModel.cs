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
using Microsoft.Win32;
using TapMyPC.Api;
using TapMyPC.Desktop.Connections;
using TapMyPC.Api.Contracts;
using System.Windows.Media.Imaging;
using TapMyPC.Core.Devices;
using TapMyPC.Core.Bluetooth;
using TapMyPC.Core.Audio;
using TapMyPC.Core.Display;
using TapMyPC.Core.Shortcuts;
using TapMyPC.Core.Feedback;
using TapMyPC.Core.Networking;
using TapMyPC.Core.Monitoring;
using TapMyPC.Core.Timers;
using TapMyPC.Windows.Settings;
using TapMyPC.Windows.Audio;
using TapMyPC.Windows.Monitoring;

namespace TapMyPC.Desktop.Features.Settings;

public sealed class SettingsViewModel : INotifyPropertyChanged
{
    private readonly IDeviceController device;
    private readonly IBluetoothController? bluetooth;
    private readonly IAudioOutputController? outputs;
    private readonly ShortcutCatalog? shortcuts;
    private readonly IMonitorController? monitors;
    private readonly IMonitoringSource monitoring = new PcStatsTraySource();
    private readonly IRemoteDesktopAudioSource remoteDesktopAudio = new WindowsRemoteDesktopAudio();
    private CancellationTokenSource? monitoringRead;
    private bool monitoringVisible;
    private readonly LocalSettings settings;
    private readonly Func<IReadOnlyList<NetworkAddress>> readNetworkAddresses;
    private readonly BluetoothConnectionHost? bluetoothHost;
    private readonly PairingService pairing;
    private readonly PowerScheduler scheduler;
    private readonly DispatcherTimer refreshTimer;
    private readonly Dispatcher dispatcher = Dispatcher.CurrentDispatcher;
    private readonly SemaphoreSlim hostGate = new(1, 1);
    private ConnectionAdvertisement? advertisement;
    private IPAddress? listeningAddress;
    private IPAddress? listeningTailscaleAddress;
    private WebApplication? tailscaleServer;
    private bool tailscaleEnabled;
    private bool connectionsEnabled;
    private bool shuttingDown;
    private int networkCheck;
    private int remoteDesktopRevision;
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
    private bool identityResetRequested;
    private string certificateSummary = "Certificate details appear when connections start.";
    private PairedClient? selectedDevice;
    private string deviceName = "";
    private IReadOnlyList<PairedClient> connectedClients = Array.Empty<PairedClient>();

    public SettingsViewModel(IDeviceController device, LocalSettings settings, PairingService pairing, PowerScheduler scheduler, IBluetoothController? bluetooth = null, IAudioOutputController? outputs = null, ShortcutCatalog? shortcuts = null, IMonitorController? monitors = null, bool enableBluetoothTransport = true, Func<IReadOnlyList<NetworkAddress>>? readNetworkAddresses = null)
    {
        this.device = device;
        this.bluetooth = bluetooth;
        this.outputs = outputs; this.shortcuts = shortcuts; this.monitors = monitors;
        ShortcutSettings = shortcuts is null ? null : new ShortcutsViewModel(shortcuts);
        this.settings = settings;
        this.readNetworkAddresses = readNetworkAddresses ?? NetworkAddresses.Read;
        Appearance = new AppearanceViewModel(settings);
        this.pairing = pairing;
        this.scheduler = scheduler;
        if (enableBluetoothTransport) bluetoothHost = new(settings, pairing, scheduler, device, bluetooth, outputs, shortcuts, monitors, () => NetworkConnection, monitoring);
        var saved = settings.ReadHost();
        address = saved.Address;
        tailscaleEnabled = saved.TailscaleEnabled;
        port = saved.Port.ToString();
        showNotifications = saved.ShowNotifications;
        connectionsEnabled = saved.ConnectionsEnabled;
        startupEnabled = StartupRegistration.Enabled;
        ToggleHost = new AsyncCommand(ToggleHostAsync);
        ToggleTailscale = new AsyncCommand(ToggleTailscaleAsync);
        OpenPairing = new RelayCommand(() =>
        {
            if ((server is null && tailscaleServer is null) || certificate is null) { Message = bluetoothHost?.Info.Available == true ? "Connect this PC to a trusted Wi-Fi network for first-time pairing. Paired phones can use Bluetooth." : "Select Start connections before adding a phone."; return; }
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
                if (server is null && tailscaleServer is null) { Message = "Start the host first to copy its phone link."; return; }
                Clipboard.SetText(RemoteUrl);
                Message = "Phone link copied. Open it on a device connected to the selected network or tailnet.";
            }
            catch (Exception ex) { Message = ex.Message; }
        });
        ExportCertificate = new RelayCommand(ExportPublicCertificate);
        RequestIdentityReset = new RelayCommand(() => { identityResetRequested = true; Notify(nameof(IdentityResetRequested)); });
        CancelIdentityReset = new RelayCommand(() => { identityResetRequested = false; Notify(nameof(IdentityResetRequested)); });
        ConfirmIdentityReset = new AsyncCommand(ResetIdentityAsync);
        RenameDevice = new RelayCommand(() => {
            try {
                if (SelectedDevice is null) { Message = "Select a paired device to rename."; return; }
                pairing.Rename(SelectedDevice.Id, DeviceName);
                Message = "Phone name saved. This name takes priority over the phone’s reported name.";
                Tick();
            } catch (Exception ex) { Message = ex.Message; }
        });
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
        _ = RemoteDesktop.PollAsync();
        Tick();
        NetworkChange.NetworkAddressChanged += OnNetworkChanged;
        SystemEvents.SessionSwitch += OnDesktopSessionSwitch;
        if (bluetoothHost is not null) SystemEvents.PowerModeChanged += OnPowerModeChanged;
    }

    public AppearanceViewModel Appearance { get; }
    public ShortcutsViewModel? ShortcutSettings { get; }
    public string MonitoringStatus { get; private set; } = "Checking…";
    public string MonitoringDetails { get; private set; } = "";
    public ObservableCollection<NetworkAddress> NetworkChoices { get; } = [];
    public ObservableCollection<PairedClient> Devices { get; } = [];
    public ObservableCollection<ActionNotice> Activity { get; } = [];
    public PairedClient? SelectedDevice {
        get => selectedDevice;
        set
        {
            selectedDevice = value;
            deviceName = value?.Name ?? "";
            Notify(); Notify(nameof(DeviceName)); Notify(nameof(HasSelectedDevice)); Notify(nameof(SelectedRemoteDesktopEnabled));
            Notify(nameof(SelectedRemoteDesktopAudioEnabled));
        }
    }
    public bool HasSelectedDevice => selectedDevice is not null;
    public bool SelectedRemoteDesktopEnabled
    {
        get => selectedDevice?.RemoteDesktopEnabled == true;
        set
        {
            if (selectedDevice is null || selectedDevice.RemoteDesktopEnabled == value) return;
            try
            {
                pairing.SetRemoteDesktopAccess(selectedDevice.Id, value);
                Message = value
                    ? "Remote Desktop enabled for this phone. Use Set up Remote Desktop to prepare the local capture service."
                    : "Remote Desktop access removed for this phone.";
                Tick();
            }
            catch (Exception ex)
            {
                Message = ex.Message;
                dispatcher.BeginInvoke(() => Notify(nameof(SelectedRemoteDesktopEnabled)));
            }
        }
    }
    public bool SelectedRemoteDesktopAudioEnabled
    {
        get => selectedDevice?.RemoteDesktopAudioEnabled == true;
        set
        {
            if (selectedDevice is null || selectedDevice.RemoteDesktopAudioEnabled == value) return;
            try
            {
                pairing.SetRemoteDesktopAudioAccess(selectedDevice.Id, value);
                Message = value ? "Remote Desktop audio allowed for this phone." : "Remote Desktop audio access removed.";
                Tick();
            }
            catch (Exception ex)
            {
                Message = ex.Message;
                dispatcher.BeginInvoke(() => Notify(nameof(SelectedRemoteDesktopAudioEnabled)));
            }
        }
    }
    public string DeviceName { get => deviceName; set { deviceName = value; Notify(); } }
    public RelayCommand RenameDevice { get; }
    public RemoteDesktopViewModel RemoteDesktop { get; } = new();
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
        : server is null && tailscaleServer is null ? "Paired phones can use Bluetooth. Connect to a trusted Wi-Fi network for first-time pairing."
        : HasPairingQr
            ? "On Android: Add PC → Scan PC QR. The QR hides automatically after successful pairing."
            : pairing.Clients.Count > 0
                ? "Your paired phones reconnect automatically. Use Add another phone only for a new device."
                : "Your pairing QR appears here. If it expired, select Show pairing QR to generate another.";
    public string PairingCode => pairingCode;
    public string PairingExpiry => pairingExpiry;
    public string Fingerprint => fingerprint;
    public string CertificateSummary => certificateSummary;
    public bool IdentityResetRequested => identityResetRequested;
    public bool CanResetIdentity => !isChangingHost;
    public RelayCommand RequestIdentityReset { get; }
    public RelayCommand CancelIdentityReset { get; }
    public AsyncCommand ConfirmIdentityReset { get; }
    public string RemoteUrl => remoteUrl;
    public string NetworkSummary => networkSummary;
    public string Pending => pending;
    public bool HasPending => scheduler.State.Pending is not null;
    public IReadOnlyList<PairedClient> ConnectedClients => connectedClients;
    public bool HasConnectedClients => connectedClients.Count > 0;
    public string ConnectionSummary => connectedClients.Count == 0 ? "No active remote" : string.Join(", ", connectedClients.Select(c => $"{c.Name} · {(c.Transport switch { RemoteTransport.Bluetooth => "Bluetooth", RemoteTransport.Tailscale => "Tailscale", _ => "Wi-Fi" })}"));
    public string ConnectionHint => HasConnectedClients
        ? $"Recent authenticated activity from {ConnectionSummary}. Goes idle after 10 seconds without activity; availability checks also count."
        : "A saved pairing does not mean a remote is currently online. Open the phone app to connect.";
    public string HostStatus => isChangingHost ? "Updating host…" : IsHosting ? "No phone connected" :
        connectionsEnabled ? "Waiting for trusted network" : "Connections stopped";
    public string HostButtonText => isChangingHost ? "Please wait…" : connectionsEnabled ? "Stop connections" : "Start connections";
    public bool CanEditConnection => server is null && tailscaleServer is null && !isChangingHost;
    public bool IsHosting => (server is not null || tailscaleServer is not null || bluetoothHost?.Info.Available == true) && !isChangingHost;
    public string BluetoothConnectionSummary => bluetoothHost?.Info.Available == true ? "Bluetooth ready · secondary connection" : bluetoothHost?.Info.Message ?? "Bluetooth transport disabled.";
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
    public bool TailscaleEnabled => tailscaleEnabled;
    public AsyncCommand ToggleTailscale { get; }
    public bool HasTailscaleAddress => tailscaleServer is not null;
    public string TailscaleUrl => listeningTailscaleAddress is null ? "" : $"https://{listeningTailscaleAddress}:{Port}";
    public string TailscaleConnectionSummary => !tailscaleEnabled ? "Tailscale off · local access stays available"
        : tailscaleServer is not null ? $"Tailscale ready · {TailscaleUrl}"
        : connectionsEnabled ? "Tailscale waiting · connect Tailscale on this PC"
        : "Tailscale enabled · connections stopped";
    private volatile WakeOnLanInfo? listeningWakeOnLan;
    private NetworkConnectionInfo NetworkConnection => new(
        server is null ? null : $"https://{listeningAddress}:{Port}",
        tailscaleServer is null ? null : TailscaleUrl,
        server is null ? null : listeningWakeOnLan);
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
            var available = readNetworkAddresses();
            // Reassign after rebuilding the list, because ComboBox selection can transiently become null.
            var previous = address;
            NetworkChoices.Clear();
            NetworkChoices.Add(new(AddressSelection.Automatic, "Automatic", false, false));
            foreach (var item in available.Where(n => !n.IsTailscale)) NetworkChoices.Add(item);
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

    private async Task ToggleTailscaleAsync()
    {
        await hostGate.WaitAsync();
        isChangingHost = true; NotifyHost();
        var previous = tailscaleEnabled;
        try
        {
            tailscaleEnabled = !tailscaleEnabled;
            try { SavePreferences(); }
            catch { tailscaleEnabled = previous; throw; }
            if (connectionsEnabled) await StartListenerAsync();
        }
        catch (Exception ex) { Message = ex.Message; }
        finally { isChangingHost = false; hostGate.Release(); NotifyHost(); }
    }

    private async Task StartListenerAsync(bool afterResume = false)
    {
        if (shuttingDown || !connectionsEnabled) return;
        if (afterResume) pairing.ClearPresence(RemoteTransport.Bluetooth);
        if (bluetoothHost is not null) await bluetoothHost.EnsureAsync(restart: afterResume);
        Notify(nameof(BluetoothConnectionSummary));
        if (!int.TryParse(Port, out var number) || number is < 1024 or > 65535)
            throw new ArgumentException("Port must be between 1024 and 65535.");
        DetectNetwork();
        var available = readNetworkAddresses();
        var previousFingerprint = fingerprint;
        IPAddress? localIp = null;
        try
        {
            var candidate = IPAddress.Parse(AddressSelection.Resolve(Address, available.Where(n => !n.IsTailscale)));
            if (NetworkTrust.IsTrusted(candidate)) localIp = candidate;
        }
        catch (InvalidOperationException) { }
        var tail = tailscaleEnabled ? available.FirstOrDefault(n => n.IsTailscale) : null;
        var tailIp = tail is null ? null : IPAddress.Parse(tail.Address);
        if (tailIp is not null && !NetworkTrust.IsTrusted(tailIp, allowTailscale: true)) tailIp = null;
        var errors = new List<string>();
        if (certificate is not null && HostCertificate.NeedsRenewal(certificate))
            await StopNetworkListenersAsync();
        // Reconcile independently: losing a local adapter must not interrupt Tailscale, or vice versa.
        if (server is not null && !Equals(localIp, listeningAddress))
        {
            advertisement?.Dispose(); advertisement = null;
            await server.StopAsync(); await server.DisposeAsync(); server = null; listeningAddress = null; listeningWakeOnLan = null;
            pairing.ClearPresence(RemoteTransport.WiFi);
        }
        if (tailscaleServer is not null && !Equals(tailIp, listeningTailscaleAddress))
        {
            await tailscaleServer.StopAsync(); await tailscaleServer.DisposeAsync(); tailscaleServer = null; listeningTailscaleAddress = null;
            pairing.ClearPresence(RemoteTransport.Tailscale);
        }
        if (certificate is null && (localIp ?? tailIp) is { } identityIp)
            certificate = new CertificateIdentity(settings, pairing).Load(identityIp);
        if (certificate is not null)
        {
            if (server is null && localIp is not null)
            {
                try
                {
                    server = await StartNetworkApiAsync(localIp, number, RemoteTransport.WiFi);
                    listeningAddress = localIp;
                    if (!IPAddress.IsLoopback(localIp))
                    {
                        try { advertisement = new(localIp, number, certificate.GetCertHashString(HashAlgorithmName.SHA256), HostCertificate.KeyFingerprint(certificate)); }
                        catch { discoverySummary = " Local discovery is unavailable; saved addresses still work."; }
                    }
                }
                catch (Exception ex) { errors.Add("Local network: " + ex.Message); }
            }
            if (tailscaleServer is null && tailIp is not null)
            {
                try
                {
                    tailscaleServer = await StartNetworkApiAsync(tailIp, number, RemoteTransport.Tailscale);
                    listeningTailscaleAddress = tailIp;
                }
                catch (Exception ex) { errors.Add("Tailscale: " + ex.Message); }
            }
            fingerprint = certificate.GetCertHashString(HashAlgorithmName.SHA256);
            certificateSummary = $"Valid until {certificate.NotAfter:d}. Renews automatically with the same PC identity key.";
            Notify(nameof(CertificateSummary));
        }
        listeningWakeOnLan = listeningAddress is null ? null
            : available.FirstOrDefault(n => !n.IsTailscale && n.Address == listeningAddress.ToString())?.WakeOnLan;
        var previousUrl = remoteUrl;
        remoteUrl = NetworkConnection.LocalAddress ?? NetworkConnection.TailscaleAddress ?? "Network address available when connections are ready";
        if ((previousUrl != remoteUrl || previousFingerprint != fingerprint) && HasPairingQr)
        {
            pairing.ClosePairing(); ClearPairingQr(); pairingExpires = null; pairingCode = "— — — — — —";
            Notify(nameof(PairingCode)); Notify(nameof(PairingExpiry));
        }
        networkSummary = server is null ? "Local network waiting · use a trusted Private/Domain network"
            : $"Local network ready · {NetworkConnection.LocalAddress}";
        if (errors.Count > 0) Message = string.Join(" ", errors);
        else if (server is not null || tailscaleServer is not null)
            Message = "Ready. Automatic on your phone tries local network, Tailscale, then Bluetooth." + discoverySummary;
        else Message = "Network connections are waiting. Paired phones can still use Bluetooth when available.";
        NotifyHost();
        if (pairing.Clients.Count == 0 && (server is not null || tailscaleServer is not null) && !pairing.IsPairingOpen)
            OpenPairing.Execute(null);
    }

    private Task<WebApplication> StartNetworkApiAsync(IPAddress ip, int number, RemoteTransport transport) =>
        ApiHost.StartAsync(ip, number, certificate!, device, pairing, scheduler,
            bluetooth: bluetooth, outputs: outputs, shortcuts: shortcuts, monitors: monitors,
            bluetoothConnection: () => bluetoothHost?.Info, transport: transport, networkConnection: () => NetworkConnection, monitoring: monitoring,
            remoteDesktopPort: 5900, remoteDesktopRevision: () => Volatile.Read(ref remoteDesktopRevision), remoteDesktopAudio: remoteDesktopAudio);

    private void OnDesktopSessionSwitch(object sender, SessionSwitchEventArgs e)
    {
        if (e.Reason is SessionSwitchReason.SessionLock or SessionSwitchReason.SessionUnlock)
            Interlocked.Increment(ref remoteDesktopRevision);
    }

    private async Task StopNetworkListenersAsync()
    {
        advertisement?.Dispose(); advertisement = null;
        if (server is not null) { await server.StopAsync(); await server.DisposeAsync(); server = null; }
        if (tailscaleServer is not null) { await tailscaleServer.StopAsync(); await tailscaleServer.DisposeAsync(); tailscaleServer = null; }
        listeningAddress = null; listeningTailscaleAddress = null; listeningWakeOnLan = null;
        certificate?.Dispose(); certificate = null;
        pairing.ClearPresence(RemoteTransport.WiFi); pairing.ClearPresence(RemoteTransport.Tailscale);
    }

    private async Task StopListenerAsync(bool stopBluetooth = true)
    {
        if (stopBluetooth && bluetoothHost is not null) await bluetoothHost.StopAsync();
        Notify(nameof(BluetoothConnectionSummary));
        pairing.ClosePairing(); ClearPairingQr();
        pairingCode = "— — — — — —"; pairingExpires = null;
        pairingExpiry = "Pairings are remembered. Start connections to reconnect.";
        await StopNetworkListenersAsync();
        pairing.ClearPresence();
        RefreshPresence();
        remoteUrl = "Browser address available when connections are running";
        networkSummary = "Local network stopped";
        Notify(nameof(PairingCode)); Notify(nameof(PairingExpiry)); NotifyHost();
    }

    private void OnNetworkChanged(object? sender, EventArgs e) =>
        dispatcher.BeginInvoke(() => _ = CheckNetworkAsync());

    private void OnPowerModeChanged(object sender, PowerModeChangedEventArgs e)
    {
        if (e.Mode == PowerModes.Resume)
            dispatcher.BeginInvoke(() => _ = CheckNetworkAsync(afterResume: true));
    }

    private async Task CheckNetworkAsync(bool afterResume = false)
    {
        if (shuttingDown || !connectionsEnabled) return;
        // A resume must still rebuild the advertisement when a network check is already in progress.
        if (afterResume) await hostGate.WaitAsync();
        else if (!await hostGate.WaitAsync(0)) return;
        try { await StartListenerAsync(afterResume); }
        catch (Exception ex) { Message = ex.Message; }
        finally { hostGate.Release(); NotifyHost(); }
    }

    private async Task ResetIdentityAsync()
    {
        if (!identityResetRequested || shuttingDown) return;
        await hostGate.WaitAsync();
        isChangingHost = true; NotifyHost();
        try
        {
            await StopListenerAsync();
            // Recovery remains available offline or with a broken saved identity.
            IPAddress ip;
            try { ip = IPAddress.Parse(AddressSelection.Resolve(Address, readNetworkAddresses())); }
            catch { ip = IPAddress.Loopback; }
            using var replacement = new CertificateIdentity(settings, pairing).Reset(ip);
            fingerprint = replacement.GetCertHashString(HashAlgorithmName.SHA256);
            certificateSummary = $"Identity reset. Certificate valid until {replacement.NotAfter:d}. Pair each phone again.";
            identityResetRequested = false;
            Notify(nameof(IdentityResetRequested)); Notify(nameof(CertificateSummary));
            const string recovered = "Connection identity reset and all previous phone access revoked. Pair each phone again using a new QR. Pending timers continue.";
            if (connectionsEnabled)
            {
                try { await StartListenerAsync(); }
                catch (Exception ex) { Message = recovered + " Connections are waiting: " + ex.Message; Tick(); return; }
            }
            Message = connectionsEnabled ? recovered : recovered + " Connections remain paused; select Start connections when ready.";
            Tick();
        }
        catch (Exception ex) { Message = $"Identity recovery could not finish: {ex.Message}"; }
        finally { isChangingHost = false; hostGate.Release(); NotifyHost(); }
    }

    private void NotifyHost()
    {
        foreach (var name in new[] { nameof(RemoteUrl), nameof(Fingerprint), nameof(HostButtonText), nameof(CanEditConnection), nameof(IsHosting), nameof(HostStatus), nameof(PairingHint), nameof(PairingButtonText), nameof(CanResetIdentity), nameof(NetworkSummary), nameof(TailscaleEnabled), nameof(TailscaleUrl), nameof(HasTailscaleAddress), nameof(TailscaleConnectionSummary) }) Notify(name);
        RefreshPresence();
    }

    private void SavePreferences()
    {
        if (!int.TryParse(Port, out var number) || number is < 1024 or > 65535) throw new ArgumentException("Port must be between 1024 and 65535.");
        settings.SaveHost(new(Address, number, ShowNotifications, ConnectionsEnabled: connectionsEnabled, TailscaleEnabled: tailscaleEnabled));
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
        var active = (server is null && tailscaleServer is null && bluetoothHost?.Info.Available != true) || isChangingHost ? Array.Empty<PairedClient>() : pairing.ActiveClients;
        if (connectedClients.SequenceEqual(active)) return;
        connectedClients = active;
        Notify(nameof(ConnectedClients));
        Notify(nameof(HasConnectedClients));
        Notify(nameof(ConnectionSummary));
        Notify(nameof(ConnectionHint));
    }

    private void Tick()
    {
        _ = RefreshMonitoringAsync();
        RefreshPresence();
        RemoteDesktop.UpdateViewer(pairing.RemoteDesktopViewer, server is not null || tailscaleServer is not null);
        if (++networkCheck % 10 == 0)
        {
            _ = CheckNetworkAsync();
            _ = RemoteDesktop.PollAsync();
        }
        if (!pairing.IsPairingOpen) ClearPairingQr();
        if (pairingExpires is { } expiry)
        {
            var remaining = expiry - DateTimeOffset.UtcNow;
            pairingExpiry = remaining > TimeSpan.Zero ? $"One use · expires in {Math.Ceiling(remaining.TotalSeconds)} seconds" : "Expired. Generate a new code.";
            if (remaining <= TimeSpan.Zero) { pairingCode = "— — — — — —"; pairingExpires = null; Notify(nameof(PairingCode)); }
            Notify(nameof(PairingExpiry));
        }
        var clients = pairing.Clients;
        if (!Devices.SequenceEqual(clients))
        {
            var selectedId = SelectedDevice?.Id;
            Devices.Clear();
            foreach (var client in clients) Devices.Add(client);
            SelectedDevice = clients.FirstOrDefault(c => c.Id == selectedId);
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
    public void SetMonitoringVisible(bool visible)
    {
        if (monitoringVisible == visible) return;
        monitoringVisible = visible;
        if (!visible)
        {
            monitoringRead?.Cancel();
            return;
        }

        SetMonitoringStatus("Checking…", "");
        _ = RefreshMonitoringAsync();
    }

    private async Task RefreshMonitoringAsync()
    {
        if (shuttingDown || !monitoringVisible || monitoringRead is not null) return;

        using var read = new CancellationTokenSource();
        monitoringRead = read;
        try
        {
            var snapshot = await monitoring.ReadAsync(read.Token);
            if (read.IsCancellationRequested) return;

            if (snapshot is null)
            {
                SetMonitoringStatus("Stats unavailable", "Open PC Stats Tray and select Show Stats → Local apps.");
                return;
            }

            var status = snapshot.IsStaleAt(DateTimeOffset.UtcNow) ? "Stats out of date" : "Receiving stats";
            SetMonitoringStatus(status, $"Last updated at {snapshot.GeneratedAtUtc.ToLocalTime():T}");
        }
        catch (OperationCanceledException) when (read.IsCancellationRequested) { }
        finally { monitoringRead = null; }
    }

    private void SetMonitoringStatus(string status, string details)
    {
        if (MonitoringStatus != status)
        {
            MonitoringStatus = status;
            Notify(nameof(MonitoringStatus));
        }
        if (MonitoringDetails != details)
        {
            MonitoringDetails = details;
            Notify(nameof(MonitoringDetails));
        }
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
        SetMonitoringVisible(false);
        NetworkChange.NetworkAddressChanged -= OnNetworkChanged;
        SystemEvents.SessionSwitch -= OnDesktopSessionSwitch;
        if (bluetoothHost is not null) SystemEvents.PowerModeChanged -= OnPowerModeChanged;
        refreshTimer.Stop();
        scheduler.Activity.Published -= OnActivity;
        await hostGate.WaitAsync();
        try { await StopListenerAsync(); scheduler.Dispose(); }
        finally { hostGate.Release(); }
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    private void Notify([CallerMemberName] string? name = null) => PropertyChanged?.Invoke(this, new(name));
}
