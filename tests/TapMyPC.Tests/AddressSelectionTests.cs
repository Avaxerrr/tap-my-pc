using TapMyPC.Core.Networking;

namespace TapMyPC.Tests;

public class AddressSelectionTests
{
    private static readonly NetworkAddress[] Addresses =
    [
        new("10.0.0.2", "Virtual adapter", false, false),
        new("192.168.1.10", "Ethernet", false, true),
        new("192.168.0.20", "Wi-Fi", true, true)
    ];

    [Fact]
    public void AutomaticPrefersAnActiveGatewayAndWifi()
    {
        Assert.Equal("192.168.0.20", AddressSelection.Resolve("auto", Addresses));
        Assert.Equal("192.168.1.10", AddressSelection.Resolve("auto", Addresses.Take(2)));
    }

    [Fact]
    public void ManualAndDebugOverridesAreRespectedAndStaleAddressesFallBack()
    {
        Assert.Equal("192.168.1.10", AddressSelection.Resolve("192.168.1.10", Addresses));
        Assert.Equal("127.0.0.1", AddressSelection.Resolve("127.0.0.1", []));
        Assert.Equal("192.168.0.20", AddressSelection.Resolve("192.168.99.99", Addresses));
    }

    [Fact]
    public void NoNetworkNeverSilentlyFallsBackToLocalhost()
    {
        Assert.Throws<InvalidOperationException>(() => AddressSelection.Resolve("auto", []));
    }
}
