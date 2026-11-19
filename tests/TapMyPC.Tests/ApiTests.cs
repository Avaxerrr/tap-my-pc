using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Builder;
using Microsoft.Extensions.Time.Testing;
using TapMyPC.Api;
using TapMyPC.Core.Devices;
using TapMyPC.Core.Shortcuts;
using TapMyPC.Core.Timers;

namespace TapMyPC.Tests;

public sealed class ApiTests : IAsyncLifetime
{
    private readonly FakeDevice device = new();
    private readonly FakeBluetooth bluetooth = new();
    private readonly FakeHardware hardware = new();
    private readonly FakeShortcutLauncher shortcutLauncher = new();
    private readonly ShortcutCatalog shortcuts;
    private readonly FakeTimeProvider clock = new();
    private readonly PairingService pairing;
    private readonly PowerScheduler scheduler;
    private WebApplication app = null!;
    private HttpClient client = null!;
    private X509Certificate2 certificate = null!;

    public ApiTests() { pairing = new(new MemoryStore(), clock); scheduler = new(device, clock); shortcuts = new(new MemoryShortcutStore(), shortcutLauncher, scheduler.Activity); shortcuts.Add("Example", ShortcutKind.Website, "https://example.com"); }
    public async Task InitializeAsync()
    {
        using var rsa = RSA.Create(2048);
        using var generated = new CertificateRequest("CN=TapMyPC-test", rsa, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1)
            .CreateSelfSigned(DateTimeOffset.UtcNow.AddMinutes(-1), DateTimeOffset.UtcNow.AddHours(1));
        certificate = X509CertificateLoader.LoadPkcs12(generated.Export(X509ContentType.Pfx), null, X509KeyStorageFlags.UserKeySet);
        app = await ApiHost.StartAsync(IPAddress.Loopback, 0, certificate, device, pairing, scheduler, bluetooth: bluetooth, outputs: hardware, monitors: hardware, shortcuts: shortcuts, bluetoothConnection: () => new(true, "10:6F:D9:9E:80:F0", TapMyPC.Core.Bluetooth.BluetoothConnectionInfo.ServiceUuid),
            networkConnection: () => new("https://192.168.12.37:45831", null, new("02:00:00:00:00:01", "192.168.12.255")));
        // Test-only pinning of this ephemeral certificate. Production clients must verify the host identity.
        var handler = new HttpClientHandler { ServerCertificateCustomValidationCallback = (_, cert, _, _) => cert?.Thumbprint == certificate.Thumbprint };
        client = new HttpClient(handler) { BaseAddress = new Uri(app.Urls.Single()) };
    }
    public async Task DisposeAsync() { client.Dispose(); await app.StopAsync(); await app.DisposeAsync(); scheduler.Dispose(); certificate.Dispose(); }

    [Fact]
    public async Task ActualListenerDeterminesTransportAndBluetoothRadioChangesAreRejected()
    {
        await Authenticate();
        client.DefaultRequestHeaders.Add("X-TapMyPC-Transport", "Bluetooth");
        client.DefaultRequestHeaders.Add("X-TapMyPC-Device-Name", Convert.ToBase64String(Encoding.UTF8.GetBytes("我的手機")));
        Assert.Equal(HttpStatusCode.OK, (await client.GetAsync("/api/v1/status")).StatusCode);
        Assert.Equal(RemoteTransport.WiFi, Assert.Single(pairing.ActiveClients).Transport);
        Assert.Equal("我的手機", Assert.Single(pairing.Clients).Name);
        await using var btApp = await ApiHost.StartAsync(IPAddress.Loopback, 0, certificate, device, pairing, scheduler,
            bluetooth: bluetooth, transport: RemoteTransport.Bluetooth);
        using var btClient = new HttpClient(new HttpClientHandler {
            ServerCertificateCustomValidationCallback = (_, cert, _, _) => cert?.Thumbprint == certificate.Thumbprint
        }) { BaseAddress = new Uri(btApp.Urls.Single()) };
        btClient.DefaultRequestHeaders.Authorization = client.DefaultRequestHeaders.Authorization;
        var blocked = await btClient.PutAsJsonAsync("/api/v1/bluetooth", new { enabled = false });
        Assert.Equal(HttpStatusCode.UnprocessableEntity, blocked.StatusCode);
        Assert.Contains("Switch to local network or Tailscale", await blocked.Content.ReadAsStringAsync());
        Assert.Empty(bluetooth.Changes);
        Assert.Equal(RemoteTransport.Bluetooth, Assert.Single(pairing.ActiveClients).Transport);
        client.DefaultRequestHeaders.Remove("X-TapMyPC-Device-Name");
        client.DefaultRequestHeaders.Add("X-TapMyPC-Device-Name", "invalid base64");
        Assert.Equal(HttpStatusCode.OK, (await client.GetAsync("/api/v1/status")).StatusCode);
        Assert.Equal("我的手機", Assert.Single(pairing.Clients).Name);
        Assert.Equal(RemoteTransport.WiFi, Assert.Single(pairing.ActiveClients).Transport);
        await btApp.StopAsync();
    }

    [Fact]
    public async Task BluetoothConnectionMetadataRequiresAuthentication()
    {
        var unauthorized = await client.GetAsync("/api/v1/status");
        Assert.Equal(HttpStatusCode.Unauthorized, unauthorized.StatusCode);
        Assert.DoesNotContain("10:6F:D9:9E:80:F0", await unauthorized.Content.ReadAsStringAsync());
        await Authenticate();
        var status = await client.GetFromJsonAsync<JsonElement>("/api/v1/status");
        var connection = status.GetProperty("bluetoothConnection");
        Assert.True(connection.GetProperty("available").GetBoolean());
        Assert.Equal("10:6F:D9:9E:80:F0", connection.GetProperty("address").GetString());
        Assert.Equal(TapMyPC.Core.Bluetooth.BluetoothConnectionInfo.ServiceUuid, connection.GetProperty("serviceId").GetString());
    }

    [Fact]
    public async Task WakeHintsRequireAuthentication()
    {
        using var unauthorized = await client.GetAsync("/api/v1/status");
        Assert.Equal(HttpStatusCode.Unauthorized, unauthorized.StatusCode);
        Assert.DoesNotContain("02:00:00:00:00:01", await unauthorized.Content.ReadAsStringAsync());

        await Authenticate();
        var status = await client.GetFromJsonAsync<JsonElement>("/api/v1/status");
        var hint = status.GetProperty("networkConnection").GetProperty("wakeOnLan");
        Assert.Equal("02:00:00:00:00:01", hint.GetProperty("mac").GetString());
        Assert.Equal("192.168.12.255", hint.GetProperty("destination").GetString());
        Assert.Equal(9, hint.GetProperty("port").GetInt32());
    }

    [Fact]
    public async Task OnlyAuthenticatedTrafficUpdatesRemotePresence()
    {
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.GetAsync("/api/v1/status")).StatusCode);
        Assert.Empty(pairing.ActiveClients);
        await Authenticate();
        Assert.Empty(pairing.ActiveClients);
        using var crossOrigin = new HttpRequestMessage(HttpMethod.Get, "/api/v1/status");
        crossOrigin.Headers.Add("Origin", "https://unrelated.example");
        Assert.Equal(HttpStatusCode.Forbidden, (await client.SendAsync(crossOrigin)).StatusCode);
        Assert.Empty(pairing.ActiveClients);
        Assert.Equal(HttpStatusCode.OK, (await client.GetAsync("/api/v1/status")).StatusCode);
        Assert.Single(pairing.ActiveClients);
        clock.Advance(PairingService.PresenceTimeout);
        Assert.Empty(pairing.ActiveClients);
        Assert.Equal(HttpStatusCode.OK, (await client.GetAsync("/api/v1/status")).StatusCode);
        pairing.Revoke(Assert.Single(pairing.Clients).Id);
        Assert.Empty(pairing.ActiveClients);
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.GetAsync("/api/v1/status")).StatusCode);
        Assert.Empty(pairing.ActiveClients);
    }

    [Fact]
    public async Task BluetoothRequiresPairingAndExplicitBooleanBeforeChangingState()
    {
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.PutAsJsonAsync("/api/v1/bluetooth", new { enabled = false })).StatusCode);
        Assert.Empty(bluetooth.Changes);
        await Authenticate();
        foreach (var body in new[] { "{}", "{\"enabled\":null}", "{\"enabled\":\"false\"}" })
            Assert.Equal(HttpStatusCode.BadRequest, (await client.PutAsync("/api/v1/bluetooth", new StringContent(body, Encoding.UTF8, "application/json"))).StatusCode);
        Assert.Empty(bluetooth.Changes);
        foreach (var enabled in new[] { false, true })
        {
            var response = await client.PutAsJsonAsync("/api/v1/bluetooth", new { enabled });
            Assert.Equal(HttpStatusCode.OK, response.StatusCode);
            var payload = await response.Content.ReadFromJsonAsync<JsonElement>();
            Assert.Equal("Succeeded", payload.GetProperty("feedback").GetProperty("phase").GetString());
            var state = await client.GetFromJsonAsync<JsonElement>("/api/v1/status");
            Assert.Equal(enabled ? "On" : "Off", state.GetProperty("bluetooth").GetProperty("state").GetString());
        }
        Assert.Equal(new[] { false, true }, bluetooth.Changes);
    }

    [Fact]
    public async Task UnavailableBluetoothDoesNotBreakOtherControlsAndReportsFailure()
    {
        bluetooth.Status = new(false, false, TapMyPC.Core.Bluetooth.BluetoothRadioState.Unavailable, "No Bluetooth adapter found.");
        await Authenticate();
        var status = await client.GetFromJsonAsync<JsonElement>("/api/v1/status");
        Assert.False(status.GetProperty("bluetooth").GetProperty("canControl").GetBoolean());
        Assert.Equal(HttpStatusCode.UnprocessableEntity, (await client.PutAsJsonAsync("/api/v1/bluetooth", new { enabled = true })).StatusCode);
        Assert.Empty(bluetooth.Changes);
        Assert.Equal("Failed", scheduler.Activity.Recent[0].Phase.ToString());
        Assert.Equal(HttpStatusCode.OK, (await client.PutAsJsonAsync("/api/v1/audio/volume", new { volume = 55 })).StatusCode);
    }
    [Fact]
    public async Task NewControlsRequirePairingAndAcceptOnlyApprovedIdsAndValidPayloads()
    {
        foreach (var route in new[] { "/audio/outputs", "/monitors", "/shortcuts" })
            Assert.Equal(HttpStatusCode.Unauthorized, (await client.GetAsync("/api/v1" + route)).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.PutAsJsonAsync("/api/v1/audio/output", new { id = "headphones" })).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.PutAsJsonAsync("/api/v1/monitors/power", new { id = "monitor-1", enabled = false })).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.PostAsJsonAsync("/api/v1/shortcuts/" + shortcuts.List()[0].Id + "/launch", new { })).StatusCode);
        Assert.Equal(0, hardware.OutputChanges);
        Assert.Empty(shortcutLauncher.Launched);
        await Authenticate();
        Assert.Equal(HttpStatusCode.BadRequest, (await client.PutAsJsonAsync("/api/v1/audio/output", new { id = "missing" })).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await client.PutAsJsonAsync("/api/v1/monitors/brightness", new { id = "monitor-1", brightness = 101 })).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await client.PutAsJsonAsync("/api/v1/monitors/power", new { id = "monitor-1" })).StatusCode);
        Assert.Equal(HttpStatusCode.UnprocessableEntity, (await client.PutAsJsonAsync("/api/v1/monitors/power", new { id = "monitor-2", enabled = false })).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await client.PostAsJsonAsync("/api/v1/shortcuts/" + Guid.NewGuid() + "/launch", new { target = "https://unapproved.example" })).StatusCode);
        Assert.Empty(shortcutLauncher.Launched);
    }

    [Fact]
    public async Task AudioMonitorAndShortcutRoutesUseServerOwnedTargets()
    {
        await Authenticate();
        Assert.Equal(HttpStatusCode.OK, (await client.PutAsJsonAsync("/api/v1/audio/output", new { id = "headphones" })).StatusCode);
        Assert.Equal("headphones", hardware.DefaultOutput);
        Assert.Equal(HttpStatusCode.OK, (await client.PutAsJsonAsync("/api/v1/monitors/brightness", new { id = "monitor-1", brightness = 30 })).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await client.PutAsJsonAsync("/api/v1/monitors/power", new { id = "monitor-1", enabled = false })).StatusCode);
        Assert.Equal(30, hardware.Monitors[0].Brightness);
        Assert.False(hardware.Monitors[0].IsOn);
        var json = await client.GetStringAsync("/api/v1/shortcuts");
        Assert.DoesNotContain("https://example.com", json);
        var id = shortcuts.List()[0].Id;
        Assert.Equal(HttpStatusCode.OK, (await client.PostAsJsonAsync("/api/v1/shortcuts/" + id + "/launch", new { target = "https://unapproved.example" })).StatusCode);
        Assert.Equal("https://example.com", Assert.Single(shortcutLauncher.Launched).Target);
        shortcuts.Remove(id);
        Assert.Equal(HttpStatusCode.BadRequest, (await client.PostAsJsonAsync("/api/v1/shortcuts/" + id + "/launch", new { })).StatusCode);
        Assert.Single(shortcutLauncher.Launched);
    }
    [Fact]
    public async Task QrEnrollmentUsesTheOneTimeSecretAndReturnsANormalCredential()
    {
        var window = pairing.OpenPairingSession();
        Assert.Equal(HttpStatusCode.BadRequest, (await client.PostAsJsonAsync("/api/v1/pair/qr", new { name = "Phone" })).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.PostAsJsonAsync("/api/v1/pair/qr", new { secret = window.Code, name = "Phone" })).StatusCode);
        var response = await client.PostAsJsonAsync("/api/v1/pair/qr", new { secret = window.QrSecret, name = "QR phone" });
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var payload = await response.Content.ReadFromJsonAsync<JsonElement>();
        var token = payload.GetProperty("token").GetString()!;
        Assert.True(pairing.Authorize(token));
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.PostAsJsonAsync("/api/v1/pair/qr", new { secret = window.QrSecret, name = "Replay" })).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.PostAsJsonAsync("/api/v1/pair", new { code = window.Code, name = "Replay" })).StatusCode);
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
        var status = await client.GetStringAsync("/api/v1/status");
        Assert.DoesNotContain(window.QrSecret, status);
        pairing.Revoke(Assert.Single(pairing.Clients).Id);
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.GetAsync("/api/v1/status")).StatusCode);
    }

    private async Task Authenticate()
    {
        var response = await client.PostAsJsonAsync("/api/v1/pair", new { code = pairing.OpenPairing().Code, name = "Test phone" });
        response.EnsureSuccessStatusCode();
        var payload = await response.Content.ReadFromJsonAsync<JsonElement>();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", payload.GetProperty("token").GetString());
    }

    [Fact]
    public async Task WebsiteIsServedButCommandsRequirePairing()
    {
        var page = await client.GetAsync("/"); Assert.Equal(HttpStatusCode.OK, page.StatusCode);
        Assert.Contains("TapMyPC", await page.Content.ReadAsStringAsync());
        Assert.Contains("frame-ancestors 'none'", page.Headers.GetValues("Content-Security-Policy").Single());
        foreach (var asset in new[] { "/app.js", "/styles.css" }) Assert.Equal(HttpStatusCode.OK, (await client.GetAsync(asset)).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.GetAsync("/api/v1/status")).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.PostAsJsonAsync("/api/v1/display/off", new { })).StatusCode);
        Assert.Equal(0, device.DisplaysOff);
    }

    [Fact]
    public async Task PairControlReadStatusAndRevoke()
    {
        await Authenticate();
        Assert.Equal(HttpStatusCode.OK, (await client.PutAsJsonAsync("/api/v1/audio/volume", new { volume = 62 })).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await client.PutAsJsonAsync("/api/v1/audio/mute", new { muted = true })).StatusCode);
        await client.PostAsJsonAsync("/api/v1/media", new { action = "Next" });
        var status = await client.GetFromJsonAsync<JsonElement>("/api/v1/status");
        Assert.Equal(62, status.GetProperty("audio").GetProperty("volume").GetInt32()); Assert.True(device.Audio.Muted);
        Assert.Equal("Requested", status.GetProperty("activity")[0].GetProperty("phase").GetString());
        Assert.Equal(MediaAction.Next, Assert.Single(device.MediaActions));
        pairing.Revoke(Assert.Single(pairing.Clients).Id);
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.GetAsync("/api/v1/status")).StatusCode);
    }

    [Fact]
    public async Task FeedbackIsReturnedWithAudioCommandsAndNativeStepsAreValidated()
    {
        await Authenticate();
        var response = await client.PutAsJsonAsync("/api/v1/audio/volume", new { volume = 42 });
        var payload = await response.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal(42, payload.GetProperty("feedback").GetProperty("audio").GetProperty("volume").GetInt32());
        var step = await client.PostAsJsonAsync("/api/v1/audio/step", new { direction = "Up" });
        Assert.Equal(HttpStatusCode.OK, step.StatusCode);
        Assert.Equal(44, device.Audio.Volume);
        Assert.Equal(HttpStatusCode.BadRequest, (await client.PostAsJsonAsync("/api/v1/audio/step", new { direction = "Wrong" })).StatusCode);
        Assert.Equal(44, device.Audio.Volume);
    }

    [Fact]
    public async Task InvalidPayloadsNeverExecuteControls()
    {
        await Authenticate();
        Assert.Equal(HttpStatusCode.BadRequest, (await client.PutAsJsonAsync("/api/v1/audio/volume", new { volume = 101 })).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await client.PutAsJsonAsync("/api/v1/audio/volume", new { })).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await client.PostAsJsonAsync("/api/v1/media", new { action = "Garbage" })).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await client.PostAsync("/api/v1/media", new StringContent("{", Encoding.UTF8, "application/json"))).StatusCode);
        Assert.Equal(35, device.Audio.Volume); Assert.Empty(device.MediaActions);
    }

    [Fact]
    public async Task PowerRequiresConfirmationHasCountdownAndCanBeCanceled()
    {
        await Authenticate();
        Assert.Equal(HttpStatusCode.BadRequest, (await client.PostAsJsonAsync("/api/v1/power", new { action = "Shutdown", delaySeconds = 10, confirmed = false })).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await client.PostAsJsonAsync("/api/v1/power", new { action = "Shutdown", delaySeconds = 0, confirmed = true })).StatusCode);
        var scheduled = await client.PostAsJsonAsync("/api/v1/power", new { action = "Shutdown", delaySeconds = 10, confirmed = true });
        Assert.Equal(HttpStatusCode.Accepted, scheduled.StatusCode); Assert.Empty(device.PowerActions);
        Assert.Equal(HttpStatusCode.Conflict, (await client.PostAsJsonAsync("/api/v1/power", new { action = "Restart", delaySeconds = 10, confirmed = true })).StatusCode);
        var payload = await scheduled.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal(HttpStatusCode.OK, (await client.DeleteAsync("/api/v1/power/" + payload.GetProperty("id").GetString())).StatusCode);
        clock.Advance(TimeSpan.FromMinutes(1)); Assert.Empty(device.PowerActions);
    }

    [Fact]
    public async Task CrossOriginAndForeignHostRequestsAreRejected()
    {
        await Authenticate();
        using var crossOrigin = new HttpRequestMessage(HttpMethod.Post, "/api/v1/display/off");
        crossOrigin.Headers.Add("Origin", "https://unrelated.example"); crossOrigin.Content = JsonContent.Create(new { });
        Assert.Equal(HttpStatusCode.Forbidden, (await client.SendAsync(crossOrigin)).StatusCode);
        using var foreignHost = new HttpRequestMessage(HttpMethod.Get, "/api/v1/status"); foreignHost.Headers.Host = "unrelated.example";
        Assert.Equal(HttpStatusCode.BadRequest, (await client.SendAsync(foreignHost)).StatusCode);
        Assert.Equal(0, device.DisplaysOff);
    }
}
