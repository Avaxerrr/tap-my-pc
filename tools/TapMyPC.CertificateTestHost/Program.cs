using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text.Json;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.Logging;
using TapMyPC.Api;
using TapMyPC.Api.Contracts;
using TapMyPC.Core.Devices;
using TapMyPC.Core.Timers;
using TapMyPC.Windows.Settings;

// Isolated loopback-only fixture. No real PC controllers, user settings, or production credentials.
if (args.Length != 1) throw new ArgumentException("Pass the output fixture JSON path.");
var directory = Path.Combine(Path.GetTempPath(), "TapMyPC-cert-e2e-" + Guid.NewGuid().ToString("N"));
var settings = new LocalSettings(directory);
var pairing = new PairingService(settings, TimeProvider.System);
using var scheduler = new PowerScheduler(new SimulatedDevice(), TimeProvider.System);
var device = new SimulatedDevice();
var owned = new HashSet<string>();
var oldClock = new FixtureClock(DateTimeOffset.UtcNow.AddDays(-350));
var certificate = HostCertificate.CreateNew(IPAddress.Loopback, oldClock);
owned.Add(certificate.Thumbprint);
settings.SaveIdentity(new(certificate.Thumbprint));
var listener = new TcpListener(IPAddress.Loopback, 0);
listener.Start();
var apiPort = ((IPEndPoint)listener.LocalEndpoint).Port;
listener.Stop();
WebApplication? host = null;
var key = Convert.ToHexString(RandomNumberGenerator.GetBytes(32));
var gate = new SemaphoreSlim(1, 1);
var done = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
var builder = WebApplication.CreateSlimBuilder();
builder.Logging.ClearProviders();
builder.WebHost.ConfigureKestrel(o => o.Listen(IPAddress.Loopback, 0));
await using var control = builder.Build();
async Task StopHost()
{
    pairing.ClosePairing();
    if (host is not null) { await host.StopAsync(); await host.DisposeAsync(); host = null; }
}
async Task StartHost()
{
    host = await ApiHost.StartAsync(IPAddress.Loopback, apiPort, certificate, device, pairing, scheduler);
}
object Invitation()
{
    var address = $"https://127.0.0.1:{apiPort}";
    var secret = pairing.OpenPairingSession();
    return new {
        address, code = secret.Code, fingerprint = certificate.GetCertHashString(HashAlgorithmName.SHA256).ToLowerInvariant(),
        keyPin = HostCertificate.KeyFingerprint(certificate),
        invitation = PairingInvitation.CreateJson("Certificate test PC", address,
            certificate.GetCertHashString(HashAlgorithmName.SHA256), secret)
    };
}
control.MapPost("/test/{action}", async (HttpContext context, string action) =>
{
    if (context.Request.Headers["X-Test-Key"] != key) return Results.Unauthorized();
    await gate.WaitAsync();
    try
    {
        if (action == "stop") { done.TrySetResult(); return Results.Ok(new { stopped = true }); }
        if (action == "state") return Results.Ok(Invitation());
        await StopHost();
        if (action == "lose")
        {
            using var store = new X509Store(StoreName.My, StoreLocation.CurrentUser);
            store.Open(OpenFlags.ReadWrite);
            store.Remove(certificate);
            try { using var unexpected = new CertificateIdentity(settings, pairing).Load(IPAddress.Loopback); }
            catch (InvalidOperationException) { return Results.Ok(new { recoveryRequired = true }); }
            throw new InvalidOperationException("Missing certificate unexpectedly recovered without local reset.");
        }
        if (action == "expire")
        {
            using var rsa = certificate.GetRSAPrivateKey()!;
            using var expired = new CertificateRequest(certificate.Subject, rsa, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1)
                .CreateSelfSigned(DateTimeOffset.UtcNow.AddDays(-365), DateTimeOffset.UtcNow.AddDays(-1));
            using var store = new X509Store(StoreName.My, StoreLocation.CurrentUser);
            store.Open(OpenFlags.ReadWrite); store.Add(expired);
            owned.Add(expired.Thumbprint); settings.SaveIdentity(new(expired.Thumbprint));
        }
        if (action is not ("renew" or "restart" or "reset" or "expire"))
            return Results.BadRequest();
        var next = action == "reset" ? new CertificateIdentity(settings, pairing).Reset(IPAddress.Loopback)
            : new CertificateIdentity(settings, pairing).Load(IPAddress.Loopback);
        owned.Add(next.Thumbprint);
        certificate.Dispose(); certificate = next;
        await StartHost();
        return Results.Ok(Invitation());
    }
    finally { gate.Release(); }
});
try
{
    await StartHost();
    await control.StartAsync();
    var fixture = new { controlUrl = control.Urls.Single(), controlKey = key, state = Invitation() };
    File.WriteAllText(args[0], JsonSerializer.Serialize(fixture));
    Console.WriteLine("Certificate fixture ready (loopback only).");
    await done.Task;
}
finally
{
    await StopHost();
    await control.StopAsync();
    certificate.Dispose();
    using var store = new X509Store(StoreName.My, StoreLocation.CurrentUser);
    store.Open(OpenFlags.ReadWrite);
    foreach (var cert in store.Certificates.Cast<X509Certificate2>().Where(c => owned.Contains(c.Thumbprint)))
    { using (cert) store.Remove(cert); }
    if (Directory.Exists(directory)) Directory.Delete(directory, true);
}

sealed class FixtureClock(DateTimeOffset now) : TimeProvider { public override DateTimeOffset GetUtcNow() => now; }
sealed class SimulatedDevice : IDeviceController
{
    public DeviceCapabilities Capabilities => new(true, true, true, true, true);
    public AudioState ReadAudio() => new(40, false);
    public void SetVolume(int percent) { }
    public void SetMute(bool muted) { }
    public void StepVolume(VolumeDirection direction) { }
    public void SendMedia(MediaAction action) { }
    public void TurnOffDisplays() { }
    public void ExecutePower(PowerAction action) => throw new InvalidOperationException("Power is disabled in certificate tests.");
}
