using System.Security.Cryptography;
using System.Text;

namespace TapMyPC.Core.Devices;

public record PairedDevice(Guid Id, string Name, string TokenHash, DateTimeOffset CreatedAt, bool NameCustomized = false);
public enum RemoteTransport { WiFi, Bluetooth }
public record PairingSession(string Code, string QrSecret, DateTimeOffset ExpiresAt);
public record PairedClient(Guid Id, string Name, DateTimeOffset CreatedAt, RemoteTransport? Transport = null);
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
    private readonly Dictionary<Guid, (DateTimeOffset SeenAt, RemoteTransport Transport)> lastAuthenticated = new();
    public static TimeSpan PresenceTimeout { get; } = TimeSpan.FromSeconds(10);
    private string? code;
    private string? qrSecret;
    private DateTimeOffset expires;
    private int failedAttempts;

    public PairingService(IDeviceStore store, TimeProvider clock)
    { this.store = store; this.clock = clock; devices = store.Load().ToList(); }

    public (string Code, DateTimeOffset ExpiresAt) OpenPairing()
    {
        var session = OpenPairingSession();
        return (session.Code, session.ExpiresAt);
    }

    public PairingSession OpenPairingSession()
    {
        lock (gate)
        {
            code = RandomNumberGenerator.GetInt32(100000, 1000000).ToString();
            qrSecret = Convert.ToHexString(RandomNumberGenerator.GetBytes(32));
            expires = clock.GetUtcNow().AddMinutes(5); failedAttempts = 0;
            return new(code, qrSecret, expires);
        }
    }

    public bool IsPairingOpen
    {
        get { lock (gate) return code is not null && clock.GetUtcNow() < expires && failedAttempts < 5; }
    }

    public void ClosePairing()
    {
        lock (gate) { code = null; qrSecret = null; }
    }

    public string Pair(string suppliedCode, string name) => Redeem(suppliedCode, name, false);
    public string PairQr(string suppliedSecret, string name) => Redeem(suppliedSecret, name, true);

    private string Redeem(string supplied, string name, bool qr)
    {
        if (string.IsNullOrWhiteSpace(name) || name.Length > 60) throw new ArgumentException("Device name must be 1–60 characters.");
        lock (gate)
        {
            if (!IsPairingOpen) throw new UnauthorizedAccessException("Open a new pairing window on the PC.");
            var expected = qr ? qrSecret : code;
            if (expected is null || !CryptographicOperations.FixedTimeEquals(Encoding.UTF8.GetBytes(expected), Encoding.UTF8.GetBytes(supplied)))
            {
                failedAttempts++;
                throw new UnauthorizedAccessException(qr ? "QR pairing is invalid. Generate a new QR on the PC." : "Incorrect pairing code.");
            }
            if (devices.Count >= 20) throw new InvalidOperationException("Remove an existing paired device first.");
            var token = Convert.ToHexString(RandomNumberGenerator.GetBytes(32));
            var updated = devices.Append(new PairedDevice(Guid.NewGuid(), name.Trim(), Hash(token), clock.GetUtcNow())).ToList();
            store.Save(updated); devices = updated;
            ClosePairing();
            return token;
        }
    }

    public bool Authorize(string token, RemoteTransport transport = RemoteTransport.WiFi, string? reportedName = null)
    {
        if (token.Length != 64) return false;
        var hash = Hash(token);
        lock (gate)
        {
            var device = devices.FirstOrDefault(d => CryptographicOperations.FixedTimeEquals(Convert.FromHexString(d.TokenHash), Convert.FromHexString(hash)));
            if (device is null) return false;
            if (!device.NameCustomized && IsValidName(reportedName) && device.Name != reportedName!.Trim())
            {
                var renamed = device with { Name = reportedName!.Trim() };
                var updated = devices.Select(d => d.Id == device.Id ? renamed : d).ToList();
                try { store.Save(updated); devices = updated; }
                catch (IOException) { /* Optional display metadata cannot interrupt valid commands. */ }
                catch (UnauthorizedAccessException) { }
            }
            lastAuthenticated[device.Id] = (clock.GetUtcNow(), transport);
            return true;
        }
    }

    public IReadOnlyList<PairedClient> Clients
    { get { lock (gate) return devices.Select(d => new PairedClient(d.Id, d.Name, d.CreatedAt)).ToArray(); } }

    // Ephemeral presence comes from authenticated activity, never from stored pairing alone.
    public IReadOnlyList<PairedClient> ActiveClients
    {
        get
        {
            lock (gate)
            {
                var now = clock.GetUtcNow();
                return devices.Where(d => lastAuthenticated.TryGetValue(d.Id, out var seen) && now - seen.SeenAt < PresenceTimeout)
                    .Select(d => new PairedClient(d.Id, d.Name, d.CreatedAt, lastAuthenticated[d.Id].Transport)).ToArray();
            }
        }
    }
    public void ClearPresence() { lock (gate) lastAuthenticated.Clear(); }

    public void Rename(Guid id, string name)
    {
        if (!IsValidName(name)) throw new ArgumentException("Phone name must be 1–60 characters without control characters.");
        lock (gate)
        {
            if (!devices.Any(d => d.Id == id)) throw new InvalidOperationException("Select an existing paired device.");
            var updated = devices.Select(d => d.Id == id ? d with { Name = name.Trim(), NameCustomized = true } : d).ToList();
            store.Save(updated); devices = updated;
        }
    }

    private static bool IsValidName(string? value) =>
        !string.IsNullOrWhiteSpace(value) && value.Trim().Length <= 60 && !value.Any(char.IsControl);

    public void RevokeAll()
    {
        lock (gate)
        {
            store.Save(Array.Empty<PairedDevice>());
            devices.Clear();
            lastAuthenticated.Clear();
            ClosePairing();
        }
    }

    public void Revoke(Guid id)
    {
        lock (gate)
        {
            var updated = devices.Where(d => d.Id != id).ToList();
            store.Save(updated); devices = updated;
            lastAuthenticated.Remove(id);
        }
    }

    private static string Hash(string value) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(value)));
}
