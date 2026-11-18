using System.Net;
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
using TapMyPC.Desktop.Connections;
using TapMyPC.Tests;
using TapMyPC.Windows.Settings;

if (args.Length != 1) throw new ArgumentException("Pass a fixture JSON path.");
var directory = Path.Combine(Path.GetTempPath(), "TapMyPC-bluetooth-test-" + Guid.NewGuid().ToString("N"));
var settings = new LocalSettings(directory);
using var certificate = HostCertificate.CreateNew(IPAddress.Loopback);
settings.SaveIdentity(new(certificate.Thumbprint));
var device = new FakeDevice();
var pairing = new PairingService(settings, TimeProvider.System);
using var scheduler = new PowerScheduler(device, TimeProvider.System);
var bluetooth = new BluetoothConnectionHost(settings, pairing, scheduler, device, new FakeBluetooth(), null, null, null);
WebApplication? wifi = null;
var key = Convert.ToHexString(RandomNumberGenerator.GetBytes(32));
var done = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
var builder = WebApplication.CreateSlimBuilder();
builder.Logging.ClearProviders();
builder.WebHost.ConfigureKestrel(o => o.Listen(IPAddress.Loopback, 0));
await using var control = builder.Build();
control.MapPost("/test/{action}", async (HttpContext context, string action) => {
    if (context.Request.Headers["X-Test-Key"] != key) return Results.Unauthorized();
    switch (action)
    {
        case "wifiOff":
            if (wifi is not null) { await wifi.StopAsync(); await wifi.DisposeAsync(); wifi = null; }
            return Results.Ok(new { wifiStopped = true });
        case "restartBluetooth":
            await bluetooth.StopAsync(); await bluetooth.EnsureAsync(); return Results.Ok(bluetooth.Info);
        case "revoke":
            pairing.RevokeAll(); return Results.Ok(new { revoked = true });
        case "state":
            return Results.Ok(new { bluetooth = bluetooth.Info, device.Audio, MediaCount = device.MediaActions.Count,
                ActiveClients = pairing.ActiveClients.Count, Pending = scheduler.State.Pending });
        case "stop":
            done.TrySetResult(); return Results.Ok(new { stopped = true });
        default: return Results.BadRequest();
    }
});
try
{
    await bluetooth.EnsureAsync();
    if (!bluetooth.Info.Available) throw new InvalidOperationException(bluetooth.Info.Message);
    wifi = await ApiHost.StartAsync(IPAddress.Loopback, 0, certificate, device, pairing, scheduler,
        bluetooth: new FakeBluetooth(), bluetoothConnection: () => bluetooth.Info);
    await control.StartAsync();
    var address = wifi.Urls.Single();
    var session = pairing.OpenPairingSession();
    var fixture = new {
        controlUrl = control.Urls.Single(), controlKey = key, wifiAddress = address,
        invitation = PairingInvitation.CreateJson("Bluetooth test PC", address,
            certificate.GetCertHashString(HashAlgorithmName.SHA256), session),
        bluetooth = bluetooth.Info
    };
    File.WriteAllText(args[0], JsonSerializer.Serialize(fixture, new JsonSerializerOptions(JsonSerializerDefaults.Web)));
    Console.WriteLine("Bluetooth hardware fixture ready; commands use simulated PC controls.");
    await done.Task;
}
finally
{
    await bluetooth.StopAsync();
    if (wifi is not null) { await wifi.StopAsync(); await wifi.DisposeAsync(); }
    await control.StopAsync();
    using var store = new X509Store(StoreName.My, StoreLocation.CurrentUser); store.Open(OpenFlags.ReadWrite);
    store.Remove(certificate);
    if (Directory.Exists(directory)) Directory.Delete(directory, true);
}
