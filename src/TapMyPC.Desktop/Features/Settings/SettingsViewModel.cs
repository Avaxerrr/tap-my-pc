using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Threading;
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
using TapMyPC.Windows.Monitoring;

namespace TapMyPC.Desktop.Features.Settings;

public sealed class SettingsViewModel : INotifyPropertyChanged
{
    private readonly IMonitoringSource monitoring = new PcStatsTraySource();
    private CancellationTokenSource? monitoringRead;
    private bool monitoringVisible;
    private readonly LocalSettings settings;
    private readonly Func<IReadOnlyList<NetworkAddress>> readNetworkAddresses;
    private readonly ConnectionListenerHost listenerHost;
    private readonly PairingService pairing;
    private readonly PowerScheduler scheduler;
    private readonly DispatcherTimer refreshTimer;
    private readonly Dispatcher dispatcher = Dispatcher.CurrentDispatcher;
    private readonly SemaphoreSlim hostGate = new(1, 1);
    private bool tailscaleEnabled;
    private bool connectionsEnabled;
    private bool shuttingDown;
    private int networkCheck;
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

    public SettingsViewModel(
        IDeviceController device,
        LocalSettings settings,
        PairingService pairing,
        PowerScheduler scheduler,
        IBluetoothController? bluetooth = null,
        IAudioOutputController? outputs = null,
        ShortcutCatalog? shortcuts = null,
        IMonitorController? monitors = null,
        bool enableBluetoothTransport = true,
        Func<IReadOnlyList<NetworkAddress>>? readNetworkAddresses = null)
    {
        ShortcutSettings = shortcuts is null ? null : new ShortcutsViewModel(shortcuts);
        this.settings = settings;
        this.readNetworkAddresses = readNetworkAddresses ?? NetworkAddresses.Read;
        Appearance = new AppearanceViewModel(settings);
        this.pairing = pairing;
        this.scheduler = scheduler;
        listenerHost = new(
            settings, pairing, scheduler, device, bluetooth, outputs, shortcuts, monitors,
            monitoring, this.readNetworkAddresses, () => Port, enableBluetoothTransport);
        var saved = settings.ReadHost();
        address = saved.Address;
        tailscaleEnabled = saved.TailscaleEnabled;
        port = saved.Port.ToString();
        showNotifications = saved.ShowNotifications;
        connectionsEnabled = saved.ConnectionsEnabled;
        startupEnabled = StartupRegistration.Enabled;
        ToggleHost = new AsyncCommand(ToggleHostAsync);
        ToggleTailscale = new AsyncCommand(ToggleTailscaleAsync);
        OpenPairing = new RelayCommand(OpenPairingSession);
        CopyUrl = new RelayCommand(() =>
        {
            try
            {
                if (!listenerHost.HasNetworkListener) { Message = "Start the host first to copy its phone link."; return; }
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
        listenerHost.RecheckRequested += OnListenerRecheckRequested;
        listenerHost.WatchChanges();
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
    public string VersionLabel { get; } = ReadVersionLabel();
    public string AppHeading => $"TAPMYPC    {VersionLabel}";

    private static string ReadVersionLabel()
    {
        var version = typeof(SettingsViewModel).Assembly
            .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion;
        if (string.IsNullOrWhiteSpace(version)) return "Version unavailable";

        var parts = version.Split('+', 2);
        return parts.Length == 2 ? $"v{parts[0]} (build {parts[1]})" : $"v{parts[0]}";
    }

    public string PairingButtonText => HasPairingQr ? "Refresh pairing QR" : pairing.Clients.Count > 0 ? "Add another phone" : "Show pairing QR";
    public string PairingHint => !IsHosting
        ? "Connections are stopped. Start connections to pair or reconnect a phone."
        : !listenerHost.HasNetworkListener ? "Paired phones can use Bluetooth. Connect to a trusted Wi-Fi network for first-time pairing."
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
    public string ConnectionSummary => connectedClients.Count == 0
        ? "No active remote"
        : string.Join(", ", connectedClients.Select(client =>
        {
            var transport = client.Transport switch
            {
                RemoteTransport.Bluetooth => "Bluetooth",
                RemoteTransport.Tailscale => "Tailscale",
                _ => "Wi-Fi"
            };
            return $"{client.Name} · {transport}";
        }));
    public string ConnectionHint => HasConnectedClients
        ? $"Recent authenticated activity from {ConnectionSummary}. Goes idle after 10 seconds without activity; availability checks also count."
        : "A saved pairing does not mean a remote is currently online. Open the phone app to connect.";
    public string HostStatus => isChangingHost ? "Updating host…" : IsHosting ? "No phone connected" :
        connectionsEnabled ? "Waiting for trusted network" : "Connections stopped";
    public string HostButtonText => isChangingHost ? "Please wait…" : connectionsEnabled ? "Stop connections" : "Start connections";
    public bool CanEditConnection => !listenerHost.HasNetworkListener && !isChangingHost;
    public bool IsHosting => (listenerHost.HasNetworkListener || listenerHost.BluetoothInfo?.Available == true) && !isChangingHost;
    public string BluetoothConnectionSummary => listenerHost.BluetoothInfo?.Available == true ? "Bluetooth ready · secondary connection" : listenerHost.BluetoothInfo?.Message ?? "Bluetooth transport disabled.";
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
    public bool HasTailscaleAddress => listenerHost.HasTailscaleListener;
    public string TailscaleUrl => listenerHost.TailscaleUrl;
    public string TailscaleConnectionSummary => !tailscaleEnabled ? "Tailscale off · local access stays available"
        : listenerHost.HasTailscaleListener ? $"Tailscale ready · {TailscaleUrl}"
        : connectionsEnabled ? "Tailscale waiting · connect Tailscale on this PC"
        : "Tailscale enabled · connections stopped";
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
        try { if (connectionsEnabled) await RefreshConnectionsAsync(); else Message = "Connections are stopped. Start connections when you are ready; paired phones are remembered."; }
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
                await StopConnectionsAsync();
                Message = saveError is null
                    ? "Connections stopped and will stay stopped after restart. Paired phones are remembered. Pending timers continue."
                    : $"Connections stopped, but the pause could not be saved: {saveError.Message}";
            }
            else
            {
                connectionsEnabled = true;
                SavePreferences();
                await RefreshConnectionsAsync();
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
            if (connectionsEnabled) await RefreshConnectionsAsync();
        }
        catch (Exception ex) { Message = ex.Message; }
        finally { isChangingHost = false; hostGate.Release(); NotifyHost(); }
    }

    private async Task RefreshConnectionsAsync(bool afterResume = false)
    {
        if (shuttingDown || !connectionsEnabled) return;
        await listenerHost.EnsureBluetoothAsync(afterResume);
        Notify(nameof(BluetoothConnectionSummary));
        if (!int.TryParse(Port, out var number) || number is < 1024 or > 65535)
            throw new ArgumentException("Port must be between 1024 and 65535.");

        DetectNetwork();
        var previousFingerprint = fingerprint;
        var errors = await listenerHost.ReconcileNetworkAsync(Address, number, tailscaleEnabled);
        if (listenerHost.Identity is { } identity)
        {
            fingerprint = identity.Fingerprint;
            certificateSummary = $"Valid until {identity.NotAfter:d}. Renews automatically with the same PC identity key.";
            Notify(nameof(CertificateSummary));
        }
        var previousUrl = remoteUrl;
        remoteUrl = listenerHost.NetworkConnection.LocalAddress ?? listenerHost.NetworkConnection.TailscaleAddress ?? "Network address available when connections are ready";
        if ((previousUrl != remoteUrl || previousFingerprint != fingerprint) && HasPairingQr)
        {
            pairing.ClosePairing(); ClearPairingQr(); pairingExpires = null; pairingCode = "— — — — — —";
            Notify(nameof(PairingCode)); Notify(nameof(PairingExpiry));
        }
        networkSummary = !listenerHost.HasLanListener ? "Local network waiting · use a trusted Private/Domain network"
            : $"Local network ready · {listenerHost.NetworkConnection.LocalAddress}";
        if (errors.Count > 0) Message = string.Join(" ", errors);
        else if (listenerHost.HasNetworkListener)
            Message = "Ready. Automatic on your phone tries local network, Tailscale, then Bluetooth." + listenerHost.DiscoverySummary;
        else Message = "Network connections are waiting. Paired phones can still use Bluetooth when available.";
        NotifyHost();
        if (pairing.Clients.Count == 0 && listenerHost.HasNetworkListener && !pairing.IsPairingOpen)
            OpenPairing.Execute(null);
    }

    private async Task StopConnectionsAsync()
    {
        await listenerHost.StopBluetoothAsync();
        Notify(nameof(BluetoothConnectionSummary));
        pairing.ClosePairing(); ClearPairingQr();
        pairingCode = "— — — — — —"; pairingExpires = null;
        pairingExpiry = "Pairings are remembered. Start connections to reconnect.";
        await listenerHost.StopNetworkAsync();
        pairing.ClearPresence();
        RefreshPresence();
        remoteUrl = "Browser address available when connections are running";
        networkSummary = "Local network stopped";
        Notify(nameof(PairingCode)); Notify(nameof(PairingExpiry)); NotifyHost();
    }

    private void OnListenerRecheckRequested(bool afterResume) =>
        dispatcher.BeginInvoke(() => _ = CheckNetworkAsync(afterResume));

    private async Task CheckNetworkAsync(bool afterResume = false)
    {
        if (shuttingDown || !connectionsEnabled) return;
        // A resume must still rebuild the advertisement when a network check is already in progress.
        if (afterResume) await hostGate.WaitAsync();
        else if (!await hostGate.WaitAsync(0)) return;
        try { await RefreshConnectionsAsync(afterResume); }
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
            await StopConnectionsAsync();
            var replacement = listenerHost.ResetIdentity(Address);
            fingerprint = replacement.Fingerprint;
            certificateSummary = $"Identity reset. Certificate valid until {replacement.NotAfter:d}. Pair each phone again.";
            identityResetRequested = false;
            Notify(nameof(IdentityResetRequested)); Notify(nameof(CertificateSummary));
            const string recovered = "Connection identity reset and all previous phone access revoked. Pair each phone again using a new QR. Pending timers continue.";
            if (connectionsEnabled)
            {
                try { await RefreshConnectionsAsync(); }
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
        foreach (var name in new[]
        {
            nameof(RemoteUrl), nameof(Fingerprint), nameof(HostButtonText),
            nameof(CanEditConnection), nameof(IsHosting), nameof(HostStatus),
            nameof(PairingHint), nameof(PairingButtonText), nameof(CanResetIdentity),
            nameof(NetworkSummary), nameof(TailscaleEnabled), nameof(TailscaleUrl),
            nameof(HasTailscaleAddress), nameof(TailscaleConnectionSummary)
        })
        {
            Notify(name);
        }
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
            if (!listenerHost.HasCertificate) { Message = "Start the host before exporting its certificate."; return; }
            var dialog = new Microsoft.Win32.SaveFileDialog { FileName = "TapMyPC.cer", Filter = "Public certificate (*.cer)|*.cer" };
            if (dialog.ShowDialog() == true)
            {
                System.IO.File.WriteAllBytes(dialog.FileName, listenerHost.ExportPublicCertificate());
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
        var active = IsHosting ? pairing.ActiveClients : Array.Empty<PairedClient>();
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
        RemoteDesktop.UpdateViewer(pairing.RemoteDesktopViewer, listenerHost.HasNetworkListener);
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

    private void OpenPairingSession()
    {
        if (!listenerHost.HasNetworkListener || !listenerHost.HasCertificate)
        {
            Message = listenerHost.BluetoothInfo?.Available == true
                ? "Connect this PC to a trusted Wi-Fi network for first-time pairing. Paired phones can use Bluetooth."
                : "Select Start connections before adding a phone.";
            return;
        }
        var window = pairing.OpenPairingSession();
        try
        {
            var invitation = PairingInvitation.CreateJson(Environment.MachineName, RemoteUrl, Fingerprint, window);
            pairingQrImage = Features.Settings.PairingQrImage.Create(invitation);
        }
        catch
        {
            pairing.ClosePairing();
            ClearPairingQr();
            Message = "Could not generate pairing QR. Please try again.";
            return;
        }
        NotifyPairingQr();
        pairingCode = window.Code;
        pairingExpires = window.ExpiresAt;
        Message = "Scan this QR in the TapMyPC Android app.\nThe code below also works for browser pairing.";
        Tick();
        Notify(nameof(PairingCode));
    }

    private void ClearPairingQr()
    {
        if (pairingQrImage is null) return;
        pairingQrImage = null;
        NotifyPairingQr();
    }
    private void NotifyPairingQr()
    {
        Notify(nameof(PairingQrImage));
        Notify(nameof(HasPairingQr));
        Notify(nameof(PairingHint));
        Notify(nameof(PairingButtonText));
    }

    private int pairedCount;

    public async Task ShutdownAsync()
    {
        shuttingDown = true;
        SetMonitoringVisible(false);
        listenerHost.StopWatchingChanges();
        listenerHost.RecheckRequested -= OnListenerRecheckRequested;
        refreshTimer.Stop();
        scheduler.Activity.Published -= OnActivity;
        await hostGate.WaitAsync();
        try { await StopConnectionsAsync(); scheduler.Dispose(); }
        finally { hostGate.Release(); }
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    private void Notify([CallerMemberName] string? name = null) => PropertyChanged?.Invoke(this, new(name));
}
