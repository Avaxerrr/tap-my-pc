using System.Net;
using TapMyPC.Core.Networking;

namespace TapMyPC.Tests;

public sealed class WakeOnLanInfoTests
{
    [Theory]
    [InlineData("192.168.12.37", 24, "192.168.12.255")]
    [InlineData("192.168.12.150", 26, "192.168.12.191")]
    [InlineData("10.0.9.10", 20, "10.0.15.255")]
    public void UsesTheActualIpv4Subnet(string ip, int prefix, string broadcast)
    {
        var info = WakeOnLanInfo.FromAdapter(IPAddress.Parse(ip), prefix, [0x02, 0, 0, 0, 0, 1]);
        Assert.Equal(new WakeOnLanInfo("02:00:00:00:00:01", broadcast), info);
    }

    [Theory]
    [InlineData("127.0.0.1", 8)]
    [InlineData("192.168.12.37", 31)]
    [InlineData("192.168.12.37", 32)]
    [InlineData("::1", 64)]
    public void OmitsAddressesWithNoUsableBroadcast(string ip, int prefix) =>
        Assert.Null(WakeOnLanInfo.FromAdapter(IPAddress.Parse(ip), prefix, [0x02, 0, 0, 0, 0, 1]));
}
