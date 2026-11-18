using System.Net;
using Makaretu.Dns;

namespace TapMyPC.Windows.Settings;

/// <summary>Discovery is a location hint only; credentials never appear in TXT records.</summary>
public sealed class ConnectionAdvertisement : IDisposable
{
    private readonly MulticastService mdns;
    private readonly ServiceDiscovery discovery;
    public ConnectionAdvertisement(IPAddress address, int port, string fingerprint, string? keyFingerprint = null)
    {
        mdns = new MulticastService(nics => nics.Where(n =>
            n.GetIPProperties().UnicastAddresses.Any(a => a.Address.Equals(address))))
        { UseIpv4 = true, UseIpv6 = false };
        discovery = new ServiceDiscovery(mdns);
        try
        {
            var service = new ServiceProfile("TapMyPC-" + fingerprint[..12], "_tapmypc._tcp", (ushort)port, new[] { address });
            service.AddProperty("v", "1");
            service.AddProperty("fp", fingerprint);
            if (keyFingerprint is not null) service.AddProperty("pk", keyFingerprint);
            service.AddProperty("name", Environment.MachineName);
            mdns.Start();
            discovery.Advertise(service);
            discovery.Announce(service);
        }
        catch { discovery.Dispose(); mdns.Dispose(); throw; }
    }
    public void Dispose()
    {
        try { discovery.Unadvertise(); } catch { /* Listener still closes if multicast is unavailable. */ }
        discovery.Dispose(); mdns.Dispose();
    }
}
