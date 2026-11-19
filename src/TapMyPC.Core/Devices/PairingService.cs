using System.Security.Cryptography;
using System.Text;

namespace TapMyPC.Core.Devices;

public record PairedDevice(Guid Id, string Name, string TokenHash, DateTimeOffset CreatedAt, bool NameCustomized = false, bool RemoteDesktopEnabled = false, bool RemoteDesktopAudioEnabled = false);
public enum RemoteTransport { WiFi, Bluetooth, Tailscale }
public record PairingSession(string Code, string QrSecret, DateTimeOffset ExpiresAt);
public record PairedClient(Guid Id, string Name, DateTimeOffset CreatedAt, RemoteTransport? Transport = null, bool RemoteDesktopEnabled = false, bool RemoteDesktopAudioEnabled = false);
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
    private sealed class RemoteDesktopSession(Guid clientId, CancellationTokenSource stop)
    {
        public Guid ClientId { get; } = clientId;
        public CancellationTokenSource Stop { get; } = stop;
        public bool Ready { get; set; }
        public CancellationTokenSource? AudioStop { get; set; }
    }

    private RemoteDesktopSession? remoteDesktopSession;
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

    public bool Authorize(string token, RemoteTransport transport = RemoteTransport.WiFi, string? reportedName = null) =>
        Authenticate(token, transport, reportedName) is not null;

    public Guid? Authenticate(string token, RemoteTransport transport, string? reportedName = null)
    {
        if (token.Length != 64) return null;
        var hash = Hash(token);
        lock (gate)
        {
            var device = devices.FirstOrDefault(d => CryptographicOperations.FixedTimeEquals(Convert.FromHexString(d.TokenHash), Convert.FromHexString(hash)));
            if (device is null) return null;
            if (!device.NameCustomized && IsValidName(reportedName) && device.Name != reportedName!.Trim())
            {
                var renamed = device with { Name = reportedName!.Trim() };
                var updated = devices.Select(d => d.Id == device.Id ? renamed : d).ToList();
                try { store.Save(updated); devices = updated; }
                catch (IOException) { /* Optional display metadata cannot interrupt valid commands. */ }
                catch (UnauthorizedAccessException) { }
            }
            lastAuthenticated[device.Id] = (clock.GetUtcNow(), transport);
            return device.Id;
        }
    }

    public IReadOnlyList<PairedClient> Clients
    { get { lock (gate) return devices.Select(d => new PairedClient(d.Id, d.Name, d.CreatedAt, RemoteDesktopEnabled: d.RemoteDesktopEnabled, RemoteDesktopAudioEnabled: d.RemoteDesktopAudioEnabled)).ToArray(); } }

    public bool AllowsRemoteDesktop(Guid clientId)
    {
        lock (gate) return devices.Any(d => d.Id == clientId && d.RemoteDesktopEnabled);
    }

    public void SetRemoteDesktopAccess(Guid clientId, bool enabled)
    {
        lock (gate)
        {
            if (!devices.Any(d => d.Id == clientId)) throw new InvalidOperationException("Select an existing paired device.");
            var updated = devices.Select(d => d.Id == clientId ? d with { RemoteDesktopEnabled = enabled, RemoteDesktopAudioEnabled = enabled && d.RemoteDesktopAudioEnabled } : d).ToList();
            store.Save(updated);
            devices = updated;
            if (!enabled) StopRemoteDesktop(clientId);
        }
    }

    public bool AllowsRemoteDesktopAudio(Guid clientId)
    {
        lock (gate) return devices.Any(d => d.Id == clientId && d.RemoteDesktopEnabled && d.RemoteDesktopAudioEnabled);
    }

    public void SetRemoteDesktopAudioAccess(Guid clientId, bool enabled)
    {
        lock (gate)
        {
            if (!AllowsRemoteDesktop(clientId)) throw new InvalidOperationException("Enable Remote Desktop for this phone first.");
            var updated = devices.Select(d => d.Id == clientId ? d with { RemoteDesktopAudioEnabled = enabled } : d).ToList();
            store.Save(updated);
            devices = updated;
            if (!enabled && remoteDesktopSession is { } session && session.ClientId == clientId)
                session.AudioStop?.Cancel();
        }
    }

    public async Task RunRemoteDesktopAudioAsync(Guid clientId, Func<CancellationToken, Task> run)
    {
        RemoteDesktopSession session;
        CancellationTokenSource stop;
        lock (gate)
        {
            if (!AllowsRemoteDesktopAudio(clientId))
                throw new UnauthorizedAccessException("Allow Remote Desktop audio for this phone on the PC.");
            if (remoteDesktopSession is not { Ready: true } current || current.ClientId != clientId ||
                current.Stop.IsCancellationRequested)
                throw new InvalidOperationException("Open the Remote Desktop viewer first.");
            if (current.AudioStop is not null)
                throw new InvalidOperationException("Remote Desktop audio is already open.");
            session = current;
            stop = CancellationTokenSource.CreateLinkedTokenSource(session.Stop.Token);
            session.AudioStop = stop;
        }
        try { await run(stop.Token); }
        finally
        {
            lock (gate) session.AudioStop = null;
            stop.Dispose();
        }
    }

    public async Task RunRemoteDesktopAsync(Guid clientId, Func<CancellationToken, Task> run)
    {
        using var stop = new CancellationTokenSource();
        lock (gate)
        {
            if (!AllowsRemoteDesktop(clientId)) throw new UnauthorizedAccessException("Enable Remote Desktop for this phone on the PC.");
            if (remoteDesktopSession is not null) throw new InvalidOperationException("A Remote Desktop session is already open.");
            remoteDesktopSession = new(clientId, stop);
        }
        try { await run(stop.Token); }
        finally
        {
            try { await stop.CancelAsync(); }
            finally { lock (gate) remoteDesktopSession = null; }
        }
    }

    public string? RemoteDesktopViewer
    {
        get
        {
            lock (gate)
            {
                if (remoteDesktopSession is not { Ready: true } session || session.Stop.IsCancellationRequested) return null;
                return devices.FirstOrDefault(device => device.Id == session.ClientId)?.Name;
            }
        }
    }

    public bool MarkRemoteDesktopReady(Guid clientId)
    {
        lock (gate)
        {
            if (remoteDesktopSession is not { Ready: false } session || session.ClientId != clientId ||
                session.Stop.IsCancellationRequested) return false;
            session.Ready = true;
            return true;
        }
    }

    private void StopRemoteDesktop(Guid? clientId = null)
    {
        if (remoteDesktopSession is { } session && (clientId is null || session.ClientId == clientId))
            session.Stop.Cancel();
    }

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
    public void ClearPresence(RemoteTransport transport)
    {
        lock (gate)
            foreach (var id in lastAuthenticated.Where(p => p.Value.Transport == transport).Select(p => p.Key).ToArray())
                lastAuthenticated.Remove(id);
    }

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
            StopRemoteDesktop();
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
            StopRemoteDesktop(id);
        }
    }

    private static string Hash(string value) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(value)));
}
