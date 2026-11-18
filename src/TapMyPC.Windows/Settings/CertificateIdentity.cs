using System.Net;
using System.Security.Cryptography.X509Certificates;
using TapMyPC.Core.Devices;

namespace TapMyPC.Windows.Settings;

/// <summary>Owns certificate persistence and local recovery, without listener or UI dependencies.</summary>
public sealed class CertificateIdentity(LocalSettings settings, PairingService pairing, TimeProvider? clock = null)
{
    public X509Certificate2 Load(IPAddress address)
    {
        var identity = settings.ReadIdentity();
        if (identity is null && pairing.Clients.Count > 0)
            throw new InvalidOperationException("The saved PC identity reference is missing. Use Reset connection identity in Advanced settings, then pair your phones again.");
        var certificate = HostCertificate.GetOrCreate(address, identity?.CertificateThumbprint, clock);
        try
        {
            if (identity?.CertificateThumbprint != certificate.Thumbprint)
                settings.SaveIdentity(new(certificate.Thumbprint));
            return certificate;
        }
        catch { certificate.Dispose(); throw; }
    }

    // The caller stops the listener first. Persist revocation before publishing the replacement identity.
    // Failure may leave phones revoked, but cannot authorize an old credential against the new identity.
    public X509Certificate2 Reset(IPAddress address)
    {
        var certificate = HostCertificate.CreateNew(address, clock);
        try
        {
            pairing.RevokeAll();
            settings.SaveIdentity(new(certificate.Thumbprint));
            return certificate;
        }
        catch { certificate.Dispose(); throw; }
    }
}
