using System.Net;
using System.Security.Cryptography.X509Certificates;
using Microsoft.AspNetCore.Builder;
using TapMyPC.Api;
using TapMyPC.Core.Audio;
using TapMyPC.Core.Bluetooth;
using TapMyPC.Core.Devices;
using TapMyPC.Core.Display;
using TapMyPC.Core.Shortcuts;
using TapMyPC.Core.Timers;
using TapMyPC.Windows.Bluetooth;
using TapMyPC.Windows.Settings;

namespace TapMyPC.Desktop.Connections;

/// <summary>Composes the existing command API and a Bluetooth byte transport. No Windows command behavior.</summary>
public sealed class BluetoothConnectionHost(LocalSettings settings, PairingService pairing, PowerScheduler scheduler,
    IDeviceController device, IBluetoothController? bluetooth, IAudioOutputController? outputs,
    ShortcutCatalog? shortcuts, IMonitorController? monitors, Func<TapMyPC.Core.Networking.NetworkConnectionInfo?>? networkConnection = null)
{
    private WebApplication? api;
    private WindowsRfcommServer? transport;
    private X509Certificate2? certificate;
    public BluetoothConnectionInfo Info { get; private set; } = new(false, null, BluetoothConnectionInfo.ServiceUuid, "Bluetooth is stopped.");

    public async Task EnsureAsync()
    {
        try
        {
            if (!await WindowsRfcommServer.RadioReadyAsync())
            {
                await StopAsync();
                Info = new(false, null, BluetoothConnectionInfo.ServiceUuid, "Turn on PC Bluetooth to connect without Wi-Fi.");
                return;
            }
            if (transport is not null && certificate is not null &&
                !HostCertificate.NeedsRenewal(certificate) && settings.ReadIdentity()?.CertificateThumbprint == certificate.Thumbprint) return;
            await StopAsync();
            certificate = new CertificateIdentity(settings, pairing).Load(IPAddress.Loopback);
            api = await ApiHost.StartAsync(IPAddress.Loopback, 0, certificate, device, pairing, scheduler,
                bluetooth: bluetooth, outputs: outputs, shortcuts: shortcuts, monitors: monitors, bluetoothConnection: () => Info, transport: RemoteTransport.Bluetooth, networkConnection: networkConnection);
            var uri = new Uri(api.Urls.Single());
            transport = await WindowsRfcommServer.StartAsync(new IPEndPoint(IPAddress.Loopback, uri.Port));
            Info = transport.Info;
        }
        catch (Exception ex)
        {
            await StopAsync();
            Info = new(false, null, BluetoothConnectionInfo.ServiceUuid, "Bluetooth unavailable: " + ex.Message);
        }
    }

    public async Task StopAsync()
    {
        if (transport is not null) { await transport.DisposeAsync(); transport = null; }
        if (api is not null) { await api.StopAsync(); await api.DisposeAsync(); api = null; }
        certificate?.Dispose(); certificate = null;
        Info = new(false, null, BluetoothConnectionInfo.ServiceUuid, "Bluetooth is stopped.");
    }
}
