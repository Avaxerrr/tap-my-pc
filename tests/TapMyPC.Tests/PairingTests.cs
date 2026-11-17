using Microsoft.Extensions.Time.Testing;
using TapMyPC.Core.Devices;

namespace TapMyPC.Tests;

public class PairingTests
{
    [Fact]
    public void CredentialSurvivesReloadAndRevocationInvalidatesIt()
    {
        var store = new MemoryStore(); var clock = new FakeTimeProvider(); var pairing = new PairingService(store, clock);
        var token = pairing.Pair(pairing.OpenPairing().Code, "Android");
        Assert.True(pairing.Authorize(token));
        Assert.DoesNotContain(token, store.Devices.Select(d => d.TokenHash));
        var reloaded = new PairingService(store, clock);
        Assert.True(reloaded.Authorize(token));
        reloaded.Revoke(Assert.Single(reloaded.Clients).Id);
        Assert.False(reloaded.Authorize(token));
    }

    [Fact]
    public void PairingCodeIsSingleUseAndExpires()
    {
        var clock = new FakeTimeProvider(); var pairing = new PairingService(new MemoryStore(), clock);
        var code = pairing.OpenPairing().Code; pairing.Pair(code, "Phone");
        Assert.Throws<UnauthorizedAccessException>(() => pairing.Pair(code, "Other"));
        code = pairing.OpenPairing().Code; clock.Advance(TimeSpan.FromMinutes(5));
        Assert.Throws<UnauthorizedAccessException>(() => pairing.Pair(code, "Phone"));
    }

    [Fact]
    public void FiveWrongAttemptsClosePairingWindow()
    {
        var pairing = new PairingService(new MemoryStore(), new FakeTimeProvider()); var code = pairing.OpenPairing().Code;
        for (var i = 0; i < 5; i++) Assert.Throws<UnauthorizedAccessException>(() => pairing.Pair("wrong", "Phone"));
        Assert.Throws<UnauthorizedAccessException>(() => pairing.Pair(code, "Phone"));
        Assert.NotEmpty(pairing.Pair(pairing.OpenPairing().Code, "Phone"));
    }
}
