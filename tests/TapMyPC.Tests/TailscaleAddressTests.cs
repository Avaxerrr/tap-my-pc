using TapMyPC.Core.Networking;

namespace TapMyPC.Tests;

public class TailscaleAddressTests
{
    private static readonly NetworkAddress Tailnet = new("100.80.90.100", "Tailscale", false, true, true);

    [Fact]
    public void TailscaleRequiresExplicitSelectionEvenWithGateway()
    {
        NetworkAddress[] addresses = [Tailnet, new("192.168.1.10", "Wi-Fi", true, false)];
        Assert.Equal("192.168.1.10", AddressSelection.Resolve("auto", addresses));
        Assert.Equal(Tailnet.Address, AddressSelection.Resolve(Tailnet.Address, addresses));
        Assert.Throws<InvalidOperationException>(() => AddressSelection.Resolve("auto", [Tailnet]));
    }

    [Fact]
    public void DisconnectedTailscaleNeverFallsBackToLan()
    {
        var error = Assert.Throws<InvalidOperationException>(() =>
            AddressSelection.Resolve(Tailnet.Address, [new("192.168.1.10", "Wi-Fi", true, true)]));
        Assert.Contains("Tailscale", error.Message);
    }

    [Theory]
    [InlineData("100.64.0.1", true)]
    [InlineData("100.127.255.254", true)]
    [InlineData("100.63.255.255", false)]
    [InlineData("100.128.0.0", false)]
    [InlineData("192.168.1.10", false)]
    [InlineData("::1", false)]
    [InlineData("not-an-ip", false)]
    public void RecognizesOnlyTheTailscaleIpv4Range(string address, bool expected) =>
        Assert.Equal(expected, TailscaleNetwork.IsAddress(address));

    [Theory]
    [InlineData("100.80.90.100", "Tailscale", "Tailscale Tunnel", true)]
    [InlineData("100.80.90.100", "Renamed", "Tailscale Tunnel", true)]
    [InlineData("100.80.90.100", "Ethernet", "Other VPN", false)]
    [InlineData("192.168.1.10", "Tailscale", "Tailscale Tunnel", false)]
    public void CgnatAloneDoesNotAuthorizeAnAdapter(string address, string name, string description, bool expected) =>
        Assert.Equal(expected, TailscaleNetwork.IsAdapter(address, name, description));
}
