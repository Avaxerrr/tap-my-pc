using System.Security.Cryptography;
using System.Text;

namespace TapMyPC.Core.Devices;

public record PairedDevice(Guid Id, string Name, string TokenHash, DateTimeOffset CreatedAt);
public record PairedClient(Guid Id, string Name, DateTimeOffset CreatedAt);
public interface IDeviceStore
{
    IReadOnlyList<PairedDevice> Load();
    void Save(IReadOnlyList<PairedDevice> devices);
}

public sealed class PairingService
{
    private readonly object gate = new();
    private readonly IDeviceStore store;
    private readonly TimeProvider clock;
    private List<PairedDevice> devices;
    private string? code;
    private DateTimeOffset expires;
    private int failedAttempts;

    public PairingService(IDeviceStore store, TimeProvider clock)
    { this.store = store; this.clock = clock; devices = store.Load().ToList(); }

    public (string Code, DateTimeOffset ExpiresAt) OpenPairing()
    {
        lock (gate)
        {
            code = RandomNumberGenerator.GetInt32(100000, 1000000).ToString();
            expires = clock.GetUtcNow().AddMinutes(5); failedAttempts = 0;
            return (code, expires);
        }
    }

    public string Pair(string suppliedCode, string name)
    {
        if (string.IsNullOrWhiteSpace(name) || name.Length > 60) throw new ArgumentException("Device name must be 1–60 characters.");
        lock (gate)
        {
            if (code is null || clock.GetUtcNow() >= expires || failedAttempts >= 5)
                throw new UnauthorizedAccessException("Open a new pairing window on the PC.");
            if (!CryptographicOperations.FixedTimeEquals(Encoding.UTF8.GetBytes(code), Encoding.UTF8.GetBytes(suppliedCode)))
            { failedAttempts++; throw new UnauthorizedAccessException("Incorrect pairing code."); }
            if (devices.Count >= 20) throw new InvalidOperationException("Remove an existing paired device first.");
            var token = Convert.ToHexString(RandomNumberGenerator.GetBytes(32));
            var updated = devices.Append(new PairedDevice(Guid.NewGuid(), name.Trim(), Hash(token), clock.GetUtcNow())).ToList();
            store.Save(updated); devices = updated; code = null;
            return token;
        }
    }

    public bool Authorize(string token)
    {
        if (token.Length != 64) return false;
        var hash = Hash(token);
        lock (gate) return devices.Any(d => CryptographicOperations.FixedTimeEquals(Convert.FromHexString(d.TokenHash), Convert.FromHexString(hash)));
    }

    public IReadOnlyList<PairedClient> Clients
    { get { lock (gate) return devices.Select(d => new PairedClient(d.Id, d.Name, d.CreatedAt)).ToArray(); } }

    public void Revoke(Guid id)
    {
        lock (gate)
        {
            var updated = devices.Where(d => d.Id != id).ToList();
            store.Save(updated); devices = updated;
        }
    }

    private static string Hash(string value) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(value)));
}
