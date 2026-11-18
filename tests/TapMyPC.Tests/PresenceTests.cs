using Microsoft.Extensions.Time.Testing;
using TapMyPC.Core.Devices;

namespace TapMyPC.Tests;

public class PresenceTests
{
    [Fact]
    public void PairingAndRejectedCredentialsDoNotImplyPresence()
    {
        var store = new MemoryStore();
        var clock = new FakeTimeProvider();
        var pairing = new PairingService(store, clock);
        var token = pairing.Pair(pairing.OpenPairing().Code, "Phone");
        Assert.Empty(pairing.ActiveClients);
        Assert.False(pairing.Authorize("invalid"));
        Assert.False(pairing.Authorize(new string('0', 64)));
        Assert.Empty(pairing.ActiveClients);
        Assert.True(pairing.Authorize(token));
        Assert.Equal("Phone", Assert.Single(pairing.ActiveClients).Name);
        Assert.Empty(new PairingService(store, clock).ActiveClients);
    }

    [Fact]
    public void SuccessfulAuthenticationRefreshesPresenceUntilTimeout()
    {
        var clock = new FakeTimeProvider();
        var pairing = new PairingService(new MemoryStore(), clock);
        var token = pairing.Pair(pairing.OpenPairing().Code, "Phone");
        Assert.True(pairing.Authorize(token));
        clock.Advance(PairingService.PresenceTimeout - TimeSpan.FromSeconds(1));
        Assert.Single(pairing.ActiveClients);
        Assert.True(pairing.Authorize(token));
        clock.Advance(PairingService.PresenceTimeout - TimeSpan.FromSeconds(1));
        Assert.Single(pairing.ActiveClients);
        clock.Advance(TimeSpan.FromSeconds(1));
        Assert.Empty(pairing.ActiveClients);
    }

    [Fact]
    public void RevocationAndHostStopClearPresenceWithoutForgettingOtherPairings()
    {
        var pairing = new PairingService(new MemoryStore(), new FakeTimeProvider());
        var first = pairing.Pair(pairing.OpenPairing().Code, "First");
        var second = pairing.Pair(pairing.OpenPairing().Code, "Second");
        Assert.True(pairing.Authorize(first));
        Assert.True(pairing.Authorize(second));
        Assert.Equal(2, pairing.ActiveClients.Count);
        pairing.Revoke(pairing.Clients.Single(c => c.Name == "First").Id);
        Assert.False(pairing.Authorize(first));
        Assert.Equal("Second", Assert.Single(pairing.ActiveClients).Name);
        pairing.ClearPresence();
        Assert.Empty(pairing.ActiveClients);
        Assert.Single(pairing.Clients);
        Assert.True(pairing.Authorize(second));
        Assert.Single(pairing.ActiveClients);
    }
}
