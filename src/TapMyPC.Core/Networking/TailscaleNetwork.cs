using System.Net;
using System.Net.Sockets;

namespace TapMyPC.Core.Networking;

public static class TailscaleNetwork
{
    public static bool IsAddress(string? value)
    {
        if (!IPAddress.TryParse(value, out var ip) || ip.AddressFamily != AddressFamily.InterNetwork) return false;
        var bytes = ip.GetAddressBytes();
        return bytes[0] == 100 && bytes[1] is >= 64 and <= 127;
    }

    // CGNAT addresses alone do not establish that an interface belongs to Tailscale.
    public static bool IsAdapter(string address, string name, string description) =>
        IsAddress(address) && (name.Equals("Tailscale", StringComparison.OrdinalIgnoreCase) ||
            description.Equals("Tailscale", StringComparison.OrdinalIgnoreCase) ||
            description.Equals("Tailscale Tunnel", StringComparison.OrdinalIgnoreCase));
}
