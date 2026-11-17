using System.Net;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;

namespace TapMyPC.Windows.Settings;

public static class HostCertificate
{
    // A per-user store keeps the private key out of source/config files. This does not trust the certificate.
    public static X509Certificate2 GetOrCreate(IPAddress address)
    {
        var subject = $"CN=TapMyPC-{address}";
        using var store = new X509Store(StoreName.My, StoreLocation.CurrentUser);
        store.Open(OpenFlags.ReadWrite);
        // Reuse a valid pre-rename identity so existing browser exceptions/pins keep working.
        var existing = store.Certificates.FirstOrDefault(c =>
            (c.Subject == subject || c.Subject == $"CN=PCRemote-{address}") &&
            c.HasPrivateKey && c.NotAfter.ToUniversalTime() > DateTime.UtcNow.AddDays(7));
        if (existing is not null) return existing;
        using var rsa = RSA.Create(2048);
        var request = new CertificateRequest(subject, rsa, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
        var names = new SubjectAlternativeNameBuilder();
        names.AddIpAddress(address);
        names.AddDnsName("localhost");
        request.CertificateExtensions.Add(names.Build());
        request.CertificateExtensions.Add(new X509BasicConstraintsExtension(false, false, 0, true));
        request.CertificateExtensions.Add(new X509KeyUsageExtension(X509KeyUsageFlags.DigitalSignature | X509KeyUsageFlags.KeyEncipherment, true));
        request.CertificateExtensions.Add(new X509EnhancedKeyUsageExtension(new OidCollection { new("1.3.6.1.5.5.7.3.1") }, false));
        using var generated = request.CreateSelfSigned(DateTimeOffset.UtcNow.AddMinutes(-5), DateTimeOffset.UtcNow.AddYears(1));
        using var persisted = X509CertificateLoader.LoadPkcs12(generated.Export(X509ContentType.Pfx), null, X509KeyStorageFlags.PersistKeySet | X509KeyStorageFlags.UserKeySet);
        store.Add(persisted);
        return store.Certificates.First(c => c.Thumbprint == persisted.Thumbprint);
    }
}
