using System.Net;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;

namespace TapMyPC.Windows.Settings;

public static class HostCertificate
{
    public static TimeSpan RenewalWindow { get; } = TimeSpan.FromDays(30);

    // Renewal changes the certificate validity, preserving the persisted PC identity key.
    public static X509Certificate2 GetOrCreate(IPAddress address, string? savedThumbprint = null, TimeProvider? clock = null)
    {
        var now = (clock ?? TimeProvider.System).GetUtcNow();
        using var store = OpenStore();
        if (!string.IsNullOrWhiteSpace(savedThumbprint))
        {
            using var saved = store.Certificates.FirstOrDefault(c => c.Thumbprint == savedThumbprint);
            if (saved is null || !saved.HasPrivateKey)
                throw new InvalidOperationException("The saved PC identity is missing. Use Reset connection identity in Advanced settings, then pair your phones again.");
            if (saved.NotBefore.ToUniversalTime() > now.UtcDateTime)
                throw new InvalidOperationException("The PC certificate is not valid yet. Check the PC clock before resetting its identity.");
            if (!NeedsRenewal(saved, now)) return new(saved);
            try
            {
                using var key = saved.GetRSAPrivateKey() ?? throw new CryptographicException("The PC identity key is unavailable.");
                // Reuse the existing persisted key without exporting it.
                using var renewed = Create(address, key, now);
                store.Add(renewed);
                return store.Certificates.Single(c => c.Thumbprint == renewed.Thumbprint && c.HasPrivateKey);
            }
            catch (CryptographicException ex)
            {
                throw new InvalidOperationException("The PC identity key could not renew its certificate. Use Reset connection identity in Advanced settings and pair again.", ex);
            }
        }
        var subject = $"CN=TapMyPC-{address}";
        var existing = store.Certificates.FirstOrDefault(c =>
            (c.Subject == subject || c.Subject == $"CN=PCRemote-{address}") &&
            c.HasPrivateKey && c.NotBefore.ToUniversalTime() <= now.UtcDateTime &&
            !NeedsRenewal(c, now));
        return existing ?? CreateNew(address, clock);
    }

    public static bool NeedsRenewal(X509Certificate2 certificate, DateTimeOffset? now = null) =>
        certificate.NotAfter.ToUniversalTime() <= (now ?? DateTimeOffset.UtcNow).Add(RenewalWindow).UtcDateTime;

    public static string KeyFingerprint(X509Certificate2 certificate) =>
        Convert.ToHexString(SHA256.HashData(certificate.PublicKey.ExportSubjectPublicKeyInfo())).ToLowerInvariant();

    // Explicit recovery must never pick an old certificate by subject.
    public static X509Certificate2 CreateNew(IPAddress address, TimeProvider? clock = null)
    {
        using var rsa = RSA.Create(2048);
        using var generated = Create(address, rsa, (clock ?? TimeProvider.System).GetUtcNow());
        using var persisted = X509CertificateLoader.LoadPkcs12(generated.Export(X509ContentType.Pfx), null,
            X509KeyStorageFlags.PersistKeySet | X509KeyStorageFlags.UserKeySet);
        using var store = OpenStore();
        store.Add(persisted);
        return store.Certificates.Single(c => c.Thumbprint == persisted.Thumbprint && c.HasPrivateKey);
    }

    private static X509Certificate2 Create(IPAddress address, RSA key, DateTimeOffset now)
    {
        var request = new CertificateRequest($"CN=TapMyPC-{address}", key, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
        var names = new SubjectAlternativeNameBuilder();
        names.AddIpAddress(address);
        names.AddDnsName("localhost");
        request.CertificateExtensions.Add(names.Build());
        request.CertificateExtensions.Add(new X509BasicConstraintsExtension(false, false, 0, true));
        request.CertificateExtensions.Add(new X509KeyUsageExtension(X509KeyUsageFlags.DigitalSignature | X509KeyUsageFlags.KeyEncipherment, true));
        request.CertificateExtensions.Add(new X509EnhancedKeyUsageExtension(new OidCollection { new("1.3.6.1.5.5.7.3.1") }, false));
        return request.CreateSelfSigned(now.AddMinutes(-5), now.AddYears(1));
    }

    private static X509Store OpenStore()
    {
        var store = new X509Store(StoreName.My, StoreLocation.CurrentUser);
        store.Open(OpenFlags.ReadWrite);
        return store;
    }
}
