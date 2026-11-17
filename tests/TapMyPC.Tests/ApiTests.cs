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
using TapMyPC.Core.Timers;

namespace TapMyPC.Tests;

public sealed class ApiTests : IAsyncLifetime
{
    private readonly FakeDevice device = new();
    private readonly FakeTimeProvider clock = new();
    private readonly PairingService pairing;
    private readonly PowerScheduler scheduler;
    private WebApplication app = null!;
    private HttpClient client = null!;
    private X509Certificate2 certificate = null!;

    public ApiTests() { pairing = new(new MemoryStore(), clock); scheduler = new(device, clock); }
    public async Task InitializeAsync()
    {
        using var rsa = RSA.Create(2048);
        using var generated = new CertificateRequest("CN=TapMyPC-test", rsa, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1)
            .CreateSelfSigned(DateTimeOffset.UtcNow.AddMinutes(-1), DateTimeOffset.UtcNow.AddHours(1));
        certificate = X509CertificateLoader.LoadPkcs12(generated.Export(X509ContentType.Pfx), null, X509KeyStorageFlags.UserKeySet);
        app = await ApiHost.StartAsync(IPAddress.Loopback, 0, certificate, device, pairing, scheduler);
        // Test-only pinning of this ephemeral certificate. Production clients must verify the host identity.
        var handler = new HttpClientHandler { ServerCertificateCustomValidationCallback = (_, cert, _, _) => cert?.Thumbprint == certificate.Thumbprint };
        client = new HttpClient(handler) { BaseAddress = new Uri(app.Urls.Single()) };
    }
    public async Task DisposeAsync() { client.Dispose(); await app.StopAsync(); await app.DisposeAsync(); scheduler.Dispose(); certificate.Dispose(); }

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
