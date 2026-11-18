using System.Net;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using Microsoft.Extensions.Time.Testing;
using TapMyPC.Core.Devices;
using TapMyPC.Windows.Settings;

namespace TapMyPC.Tests;

public sealed class CertificateLifecycleTests : IDisposable
{
    private readonly List<string> owned = [];
    private readonly string directory = Path.Combine(Path.GetTempPath(), "TapMyPC-cert-tests-" + Guid.NewGuid().ToString("N"));
    private LocalSettings Settings => new(directory);

    [Fact]
    public void SavedIdentitySurvivesReopeningAndAddressChanges()
    {
        if (!OperatingSystem.IsWindows()) return;
        using var first = Track(HostCertificate.CreateNew(IPAddress.Loopback));
        Assert.True(first.HasPrivateKey);
        Assert.InRange(first.NotAfter.ToUniversalTime(), DateTime.UtcNow.AddDays(364), DateTime.UtcNow.AddDays(367));
        using var reopened = HostCertificate.GetOrCreate(IPAddress.Loopback, first.Thumbprint);
        using var moved = HostCertificate.GetOrCreate(IPAddress.Parse("127.0.0.2"), first.Thumbprint);
        Assert.Equal(first.Thumbprint, reopened.Thumbprint);
        Assert.Equal(first.Thumbprint, moved.Thumbprint);
    }

    [Theory]
    [InlineData(15)]
    [InlineData(-1)]
    public void NearExpiryAndExpiredCertificatesRenewWithSamePersistedPrivateKey(int remainingDays)
    {
        if (!OperatingSystem.IsWindows()) return;
        using var original = AddCertificate(remainingDays);
        Settings.SaveIdentity(new(original.Thumbprint));
        var pairing = new PairingService(Settings, TimeProvider.System);
        var token = pairing.Pair(pairing.OpenPairing().Code, "Phone");
        using var renewed = Track(new CertificateIdentity(Settings, pairing).Load(IPAddress.Loopback));
        Assert.NotEqual(original.Thumbprint, renewed.Thumbprint);
        Assert.Equal(HostCertificate.KeyFingerprint(original), HostCertificate.KeyFingerprint(renewed));
        Assert.Equal(renewed.Thumbprint, Settings.ReadIdentity()!.CertificateThumbprint);
        Assert.True(pairing.Authorize(token));
        using var reopened = new CertificateIdentity(Settings, pairing).Load(IPAddress.Loopback);
        Assert.Equal(renewed.Thumbprint, reopened.Thumbprint);
        using var privateKey = reopened.GetRSAPrivateKey()!;
        using var publicKey = original.GetRSAPublicKey()!;
        var challenge = RandomNumberGenerator.GetBytes(32);
        Assert.True(publicKey.VerifyData(challenge, privateKey.SignData(challenge, HashAlgorithmName.SHA256,
            RSASignaturePadding.Pkcs1), HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1));
    }

    [Fact]
    public void UnknownOrMissingKeyRequiresExplicitRecovery()
    {
        if (!OperatingSystem.IsWindows()) return;
        var missing = Convert.ToHexString(RandomNumberGenerator.GetBytes(20));
        var failure = Assert.Throws<InvalidOperationException>(() => HostCertificate.GetOrCreate(IPAddress.Loopback, missing));
        Assert.Contains("Reset connection identity", failure.Message);
        using var cert = AddCertificate(100);
        using var publicOnly = X509CertificateLoader.LoadCertificate(cert.RawData);
        using var store = OpenStore();
        store.Remove(cert);
        store.Add(publicOnly);
        Assert.Throws<InvalidOperationException>(() => HostCertificate.GetOrCreate(IPAddress.Loopback, cert.Thumbprint));
    }

    [Fact]
    public void ResetChangesKeyRevokesPersistedPhonesAndClosesOldInvitations()
    {
        if (!OperatingSystem.IsWindows()) return;
        using var original = Track(HostCertificate.CreateNew(IPAddress.Loopback));
        Settings.SaveIdentity(new(original.Thumbprint));
        var pairing = new PairingService(Settings, TimeProvider.System);
        var token = pairing.Pair(pairing.OpenPairing().Code, "Phone");
        var oldInvitation = pairing.OpenPairingSession();
        using var replacement = Track(new CertificateIdentity(Settings, pairing).Reset(IPAddress.Loopback));
        Assert.NotEqual(HostCertificate.KeyFingerprint(original), HostCertificate.KeyFingerprint(replacement));
        Assert.False(pairing.Authorize(token));
        Assert.Empty(pairing.ActiveClients);
        Assert.False(pairing.IsPairingOpen);
        Assert.Throws<UnauthorizedAccessException>(() => pairing.PairQr(oldInvitation.QrSecret, "Phone"));
        Assert.False(new PairingService(Settings, TimeProvider.System).Authorize(token));
        using var reopened = new CertificateIdentity(Settings, pairing).Load(IPAddress.Loopback);
        Assert.Equal(replacement.Thumbprint, reopened.Thumbprint);
    }

    [Fact]
    public void LostIdentityReferenceDoesNotSilentlyAdoptAnotherStoredCertificate()
    {
        if (!OperatingSystem.IsWindows()) return;
        var pairing = new PairingService(Settings, TimeProvider.System);
        var token = pairing.Pair(pairing.OpenPairing().Code, "Saved phone");
        var failure = Assert.Throws<InvalidOperationException>(() =>
            new CertificateIdentity(Settings, pairing).Load(IPAddress.Loopback));
        Assert.Contains("Reset connection identity", failure.Message);
        Assert.True(pairing.Authorize(token));
        Assert.Null(Settings.ReadIdentity());
    }

    [Fact]
    public void FutureDatedIdentityDoesNotRenewAroundAnIncorrectClock()
    {
        if (!OperatingSystem.IsWindows()) return;
        using var cert = Track(HostCertificate.CreateNew(IPAddress.Loopback));
        var clock = new FakeTimeProvider(DateTimeOffset.UtcNow.AddDays(-2));
        Assert.Throws<InvalidOperationException>(() => HostCertificate.GetOrCreate(IPAddress.Loopback, cert.Thumbprint, clock));
    }

    private X509Certificate2 AddCertificate(int remainingDays)
    {
        using var rsa = RSA.Create(2048);
        using var generated = new CertificateRequest($"CN=TapMyPC-test-{Guid.NewGuid():N}", rsa,
            HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1)
            .CreateSelfSigned(DateTimeOffset.UtcNow.AddDays(-365), DateTimeOffset.UtcNow.AddDays(remainingDays));
        var certificate = Track(X509CertificateLoader.LoadPkcs12(generated.Export(X509ContentType.Pfx), null,
            X509KeyStorageFlags.UserKeySet | X509KeyStorageFlags.PersistKeySet));
        using var store = OpenStore();
        store.Add(certificate);
        return certificate;
    }

    private X509Certificate2 Track(X509Certificate2 certificate) { owned.Add(certificate.Thumbprint); return certificate; }
    private static X509Store OpenStore()
    {
        var store = new X509Store(StoreName.My, StoreLocation.CurrentUser);
        store.Open(OpenFlags.ReadWrite);
        return store;
    }
    public void Dispose()
    {
        if (!OperatingSystem.IsWindows()) return;
        using var store = OpenStore();
        foreach (var cert in store.Certificates.Cast<X509Certificate2>().Where(c => owned.Contains(c.Thumbprint)))
        { using (cert) store.Remove(cert); }
        if (Directory.Exists(directory)) Directory.Delete(directory, true);
    }
}
