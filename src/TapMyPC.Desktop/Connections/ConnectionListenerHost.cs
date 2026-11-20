using System.Net;
using System.Net.NetworkInformation;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using Microsoft.AspNetCore.Builder;
using Microsoft.Win32;
using TapMyPC.Api;
using TapMyPC.Core.Audio;
using TapMyPC.Core.Bluetooth;
using TapMyPC.Core.Devices;
using TapMyPC.Core.Display;
using TapMyPC.Core.Monitoring;
using TapMyPC.Core.Networking;
using TapMyPC.Core.Shortcuts;
using TapMyPC.Core.Timers;
using TapMyPC.Windows.Audio;
using TapMyPC.Windows.Settings;

namespace TapMyPC.Desktop.Connections;

/// <summary>Owns transport listeners, local discovery, and the HTTPS identity used by the network listeners.</summary>
internal sealed class ConnectionListenerHost
{
    private readonly LocalSettings settings;
    private readonly PairingService pairing;
    private readonly PowerScheduler scheduler;
    private readonly IDeviceController device;
    private readonly IBluetoothController? bluetooth;
    private readonly IAudioOutputController? outputs;
    private readonly ShortcutCatalog? shortcuts;
    private readonly IMonitorController? monitors;
    private readonly IMonitoringSource monitoring;
    private readonly Func<IReadOnlyList<NetworkAddress>> readNetworkAddresses;
    private readonly Func<string> readPort;
    private readonly BluetoothConnectionHost? bluetoothHost;
    private readonly IRemoteDesktopAudioSource remoteDesktopAudio = new WindowsRemoteDesktopAudio();

    private WebApplication? lanServer;
    private WebApplication? tailscaleServer;
    private IPAddress? listeningAddress;
    private IPAddress? listeningTailscaleAddress;
    private volatile WakeOnLanInfo? listeningWakeOnLan;
    private X509Certificate2? certificate;
    private ConnectionAdvertisement? advertisement;
    private int remoteDesktopRevision;

    public ConnectionListenerHost(
        LocalSettings settings,
        PairingService pairing,
        PowerScheduler scheduler,
        IDeviceController device,
        IBluetoothController? bluetooth,
        IAudioOutputController? outputs,
        ShortcutCatalog? shortcuts,
        IMonitorController? monitors,
        IMonitoringSource monitoring,
        Func<IReadOnlyList<NetworkAddress>> readNetworkAddresses,
        Func<string> readPort,
        bool enableBluetoothTransport)
    {
        this.settings = settings;
        this.pairing = pairing;
        this.scheduler = scheduler;
        this.device = device;
        this.bluetooth = bluetooth;
        this.outputs = outputs;
        this.shortcuts = shortcuts;
        this.monitors = monitors;
        this.monitoring = monitoring;
        this.readNetworkAddresses = readNetworkAddresses;
        this.readPort = readPort;
        if (enableBluetoothTransport)
        {
            bluetoothHost = new(
                settings, pairing, scheduler, device, bluetooth, outputs, shortcuts, monitors,
                () => NetworkConnection, monitoring);
        }
    }

    public bool HasLanListener => lanServer is not null;
    public bool HasTailscaleListener => tailscaleServer is not null;
    public bool HasNetworkListener => HasLanListener || HasTailscaleListener;
    public BluetoothConnectionInfo? BluetoothInfo => bluetoothHost?.Info;
    public bool HasCertificate => certificate is not null;
    public (string Fingerprint, DateTime NotAfter)? Identity =>
        certificate is { } identity ? Describe(identity) : null;
    public string DiscoverySummary { get; private set; } = "";
    public string TailscaleUrl =>
        listeningTailscaleAddress is null ? "" : $"https://{listeningTailscaleAddress}:{readPort()}";

    public NetworkConnectionInfo NetworkConnection => new(
        HasLanListener ? $"https://{listeningAddress}:{readPort()}" : null,
        HasTailscaleListener ? TailscaleUrl : null,
        HasLanListener ? listeningWakeOnLan : null);

    // The caller marshals these events to the UI dispatcher and serializes listener operations.
    public event Action<bool>? RecheckRequested;

    public void WatchChanges()
    {
        NetworkChange.NetworkAddressChanged += OnNetworkChanged;
        SystemEvents.SessionSwitch += OnDesktopSessionSwitch;
        if (bluetoothHost is not null) SystemEvents.PowerModeChanged += OnPowerModeChanged;
    }

    public void StopWatchingChanges()
    {
        NetworkChange.NetworkAddressChanged -= OnNetworkChanged;
        SystemEvents.SessionSwitch -= OnDesktopSessionSwitch;
        if (bluetoothHost is not null) SystemEvents.PowerModeChanged -= OnPowerModeChanged;
    }

    private void OnNetworkChanged(object? sender, EventArgs e) => RecheckRequested?.Invoke(false);

    private void OnPowerModeChanged(object sender, PowerModeChangedEventArgs e)
    {
        if (e.Mode == PowerModes.Resume) RecheckRequested?.Invoke(true);
    }

    private void OnDesktopSessionSwitch(object sender, SessionSwitchEventArgs e)
    {
        if (e.Reason is SessionSwitchReason.SessionLock or SessionSwitchReason.SessionUnlock)
            Interlocked.Increment(ref remoteDesktopRevision);
    }

    public async Task EnsureBluetoothAsync(bool afterResume)
    {
        if (afterResume) pairing.ClearPresence(RemoteTransport.Bluetooth);
        if (bluetoothHost is not null) await bluetoothHost.EnsureAsync(restart: afterResume);
    }

    public async Task<IReadOnlyList<string>> ReconcileNetworkAsync(string address, int port, bool tailscaleEnabled)
    {
        var available = readNetworkAddresses();
        IPAddress? localIp = null;
        try
        {
            var candidate = IPAddress.Parse(AddressSelection.Resolve(address, available.Where(n => !n.IsTailscale)));
            if (NetworkTrust.IsTrusted(candidate)) localIp = candidate;
        }
        catch (InvalidOperationException) { }

        var tail = tailscaleEnabled ? available.FirstOrDefault(n => n.IsTailscale) : null;
        var tailIp = tail is null ? null : IPAddress.Parse(tail.Address);
        if (tailIp is not null && !NetworkTrust.IsTrusted(tailIp, allowTailscale: true)) tailIp = null;
        var errors = new List<string>();
        if (certificate is not null && HostCertificate.NeedsRenewal(certificate))
            await StopNetworkAsync();

        // The two listeners rebind independently when their selected adapters change.
        if (lanServer is not null && !Equals(localIp, listeningAddress))
        {
            advertisement?.Dispose();
            advertisement = null;
            await lanServer.StopAsync();
            await lanServer.DisposeAsync();
            lanServer = null;
            listeningAddress = null;
            listeningWakeOnLan = null;
            pairing.ClearPresence(RemoteTransport.WiFi);
        }
        if (tailscaleServer is not null && !Equals(tailIp, listeningTailscaleAddress))
        {
            await tailscaleServer.StopAsync();
            await tailscaleServer.DisposeAsync();
            tailscaleServer = null;
            listeningTailscaleAddress = null;
            pairing.ClearPresence(RemoteTransport.Tailscale);
        }

        if (certificate is null && (localIp ?? tailIp) is { } identityIp)
            certificate = new CertificateIdentity(settings, pairing).Load(identityIp);
        if (certificate is not null)
        {
            if (lanServer is null && localIp is not null)
            {
                try
                {
                    lanServer = await StartNetworkApiAsync(localIp, port, RemoteTransport.WiFi);
                    listeningAddress = localIp;
                    if (!IPAddress.IsLoopback(localIp))
                    {
                        try
                        {
                            advertisement = new(
                                localIp, port, certificate.GetCertHashString(HashAlgorithmName.SHA256),
                                HostCertificate.KeyFingerprint(certificate));
                        }
                        catch
                        {
                            DiscoverySummary = " Local discovery is unavailable; saved addresses still work.";
                        }
                    }
                }
                catch (Exception ex) { errors.Add("Local network: " + ex.Message); }
            }
            if (tailscaleServer is null && tailIp is not null)
            {
                try
                {
                    tailscaleServer = await StartNetworkApiAsync(tailIp, port, RemoteTransport.Tailscale);
                    listeningTailscaleAddress = tailIp;
                }
                catch (Exception ex) { errors.Add("Tailscale: " + ex.Message); }
            }
        }

        listeningWakeOnLan = listeningAddress is null ? null
            : available.FirstOrDefault(n => !n.IsTailscale && n.Address == listeningAddress.ToString())?.WakeOnLan;
        return errors;
    }

    private Task<WebApplication> StartNetworkApiAsync(IPAddress ip, int port, RemoteTransport transport) =>
        ApiHost.StartAsync(ip, port, certificate!, device, pairing, scheduler,
            bluetooth: bluetooth,
            outputs: outputs,
            shortcuts: shortcuts,
            monitors: monitors,
            bluetoothConnection: () => BluetoothInfo,
            transport: transport,
            networkConnection: () => NetworkConnection,
            monitoring: monitoring,
            remoteDesktopPort: 5900,
            remoteDesktopRevision: () => Volatile.Read(ref remoteDesktopRevision),
            remoteDesktopAudio: remoteDesktopAudio);

    public Task StopBluetoothAsync() => bluetoothHost?.StopAsync() ?? Task.CompletedTask;

    public async Task StopNetworkAsync()
    {
        advertisement?.Dispose();
        advertisement = null;
        if (lanServer is not null)
        {
            await lanServer.StopAsync();
            await lanServer.DisposeAsync();
            lanServer = null;
        }
        if (tailscaleServer is not null)
        {
            await tailscaleServer.StopAsync();
            await tailscaleServer.DisposeAsync();
            tailscaleServer = null;
        }
        listeningAddress = null;
        listeningTailscaleAddress = null;
        listeningWakeOnLan = null;
        certificate?.Dispose();
        certificate = null;
        pairing.ClearPresence(RemoteTransport.WiFi);
        pairing.ClearPresence(RemoteTransport.Tailscale);
    }

    public (string Fingerprint, DateTime NotAfter) ResetIdentity(string address)
    {
        // Recovery remains available even when no usable network is active.
        IPAddress ip;
        try { ip = IPAddress.Parse(AddressSelection.Resolve(address, readNetworkAddresses())); }
        catch { ip = IPAddress.Loopback; }
        using var replacement = new CertificateIdentity(settings, pairing).Reset(ip);
        return Describe(replacement);
    }

    public byte[] ExportPublicCertificate() =>
        (certificate ?? throw new InvalidOperationException("Start the host before exporting its certificate."))
        .Export(X509ContentType.Cert);

    private static (string Fingerprint, DateTime NotAfter) Describe(X509Certificate2 identity) =>
        (identity.GetCertHashString(HashAlgorithmName.SHA256), identity.NotAfter);
}
