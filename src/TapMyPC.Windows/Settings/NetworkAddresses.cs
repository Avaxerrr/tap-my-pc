using System.Net.NetworkInformation;
using System.Net.Sockets;
using TapMyPC.Core.Networking;

namespace TapMyPC.Windows.Settings;

public static class NetworkAddresses
{
    public static IReadOnlyList<NetworkAddress> Read()
    {
        var result = new List<NetworkAddress>();
        foreach (var nic in NetworkInterface.GetAllNetworkInterfaces().Where(n => n.OperationalStatus == OperationalStatus.Up && n.NetworkInterfaceType != NetworkInterfaceType.Loopback))
        {
            var properties = nic.GetIPProperties();
            var gateway = properties.GatewayAddresses.Any(g => g.Address.AddressFamily == AddressFamily.InterNetwork && !g.Address.Equals(System.Net.IPAddress.Any));
            foreach (var entry in properties.UnicastAddresses.Where(a => a.Address.AddressFamily == AddressFamily.InterNetwork))
            {
                var bytes = entry.Address.GetAddressBytes();
                var tailscale = TailscaleNetwork.IsAdapter(entry.Address.ToString(), nic.Name, nic.Description);
                if (tailscale || bytes[0] == 10 || bytes[0] == 192 && bytes[1] == 168 || bytes[0] == 172 && bytes[1] is >= 16 and <= 31)
                    result.Add(new(entry.Address.ToString(), nic.Name, nic.NetworkInterfaceType == NetworkInterfaceType.Wireless80211, gateway, tailscale));
            }
        }
        return result.DistinctBy(a => a.Address).ToArray();
    }
}
