using Microsoft.Extensions.Time.Testing;
using TapMyPC.Core.Devices;

namespace TapMyPC.Tests;

public sealed class QrPairingTests
{
    [Fact]
    public void QrSecretIsStrongAndSharedWindowIsSingleUse()
    {
        var service = new PairingService(new MemoryStore(), new FakeTimeProvider());
        var window = service.OpenPairingSession();
        Assert.Equal(32, Convert.FromHexString(window.QrSecret).Length);
        Assert.NotEqual(window.Code, window.QrSecret);
        Assert.Throws<UnauthorizedAccessException>(() => service.PairQr(window.Code, "Phone"));
        var token = service.PairQr(window.QrSecret, "Phone");
        Assert.True(service.Authorize(token));
        Assert.False(service.IsPairingOpen);
        Assert.Throws<UnauthorizedAccessException>(() => service.PairQr(window.QrSecret, "Other"));
        Assert.Throws<UnauthorizedAccessException>(() => service.Pair(window.Code, "Other"));
    }

    [Fact]
    public void ManualPairingAlsoConsumesQr()
    {
        var service = new PairingService(new MemoryStore(), new FakeTimeProvider());
        var window = service.OpenPairingSession();
        service.Pair(window.Code, "Browser");
        Assert.Throws<UnauthorizedAccessException>(() => service.PairQr(window.QrSecret, "Phone"));
    }

    [Fact]
    public void ExpiryRegenerationAndClosureInvalidateQr()
    {
        var clock = new FakeTimeProvider();
        var service = new PairingService(new MemoryStore(), clock);
        var old = service.OpenPairingSession();
        var current = service.OpenPairingSession();
        Assert.Throws<UnauthorizedAccessException>(() => service.PairQr(old.QrSecret, "Phone"));
        clock.Advance(TimeSpan.FromMinutes(5));
        Assert.False(service.IsPairingOpen);
        Assert.Throws<UnauthorizedAccessException>(() => service.PairQr(current.QrSecret, "Phone"));
        current = service.OpenPairingSession();
        service.ClosePairing();
        Assert.Throws<UnauthorizedAccessException>(() => service.PairQr(current.QrSecret, "Phone"));
    }

    [Fact]
    public void FailedQrAttemptsCloseBothEnrollmentPaths()
    {
        var service = new PairingService(new MemoryStore(), new FakeTimeProvider());
        var window = service.OpenPairingSession();
        for (var i = 0; i < 5; i++) Assert.Throws<UnauthorizedAccessException>(() => service.PairQr("wrong", "Phone"));
        Assert.False(service.IsPairingOpen);
        Assert.Throws<UnauthorizedAccessException>(() => service.Pair(window.Code, "Browser"));
    }

    [Fact]
    public async Task ConcurrentRedemptionsIssueOnlyOneCredential()
    {
        var service = new PairingService(new MemoryStore(), new FakeTimeProvider());
        var window = service.OpenPairingSession();
        var outcomes = await Task.WhenAll(Enumerable.Range(0, 12).Select(i => Task.Run(() =>
        {
            try { return service.PairQr(window.QrSecret, $"Phone {i}"); }
            catch (UnauthorizedAccessException) { return null; }
        })));
        Assert.Single(outcomes, x => x is not null);
        Assert.Single(service.Clients);
    }
}
