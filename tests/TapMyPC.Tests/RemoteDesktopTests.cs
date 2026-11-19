using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Net.Sockets;
using System.Net.WebSockets;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text.Json;
using Microsoft.AspNetCore.Builder;
using TapMyPC.Api;
using TapMyPC.Core.Devices;
using TapMyPC.Core.Timers;

namespace TapMyPC.Tests;

public sealed class RemoteDesktopTests : IAsyncLifetime
{
    private readonly FakeDevice device = new();
    private readonly TcpListener backend = new(IPAddress.Loopback, 0);
    private readonly PairingService pairing = new(new MemoryStore(), TimeProvider.System);
    private PowerScheduler scheduler = null!;
    private X509Certificate2 certificate = null!;
    private WebApplication app = null!;
    private int desktopRevision;

    public async Task InitializeAsync()
    {
        backend.Start();
        scheduler = new(device, TimeProvider.System);
        using var rsa = RSA.Create(2048);
        using var generated = new CertificateRequest("CN=RemoteDesktopTest", rsa, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1)
            .CreateSelfSigned(DateTimeOffset.UtcNow.AddMinutes(-1), DateTimeOffset.UtcNow.AddHours(1));
        certificate = X509CertificateLoader.LoadPkcs12(
            generated.Export(X509ContentType.Pfx), null, X509KeyStorageFlags.UserKeySet);
        app = await StartHostAsync(RemoteTransport.WiFi);
    }

    public async Task DisposeAsync()
    {
        backend.Stop();
        await app.StopAsync();
        await app.DisposeAsync();
        scheduler.Dispose();
        certificate.Dispose();
    }

    [Fact]
    public async Task OnlyAuthorizedPhoneCanReachVncAndOnlyOverNetwork()
    {
        using var timer = new CancellationTokenSource(TimeSpan.FromSeconds(8));
        var phone = Pair("Phone");
        var other = Pair("Other phone");

        await RejectAsync(app, null, HttpStatusCode.Unauthorized, timer.Token);
        await RejectAsync(app, phone.Token, HttpStatusCode.Forbidden, timer.Token);
        var disabled = await ReadStatusAsync(app, phone.Token, timer.Token);
        Assert.False(disabled.GetProperty("remoteDesktopEnabled").GetBoolean());
        Assert.Equal(JsonValueKind.Null, disabled.GetProperty("remoteDesktopRevision").ValueKind);

        pairing.SetRemoteDesktopAccess(phone.Id, true);
        var enabled = await ReadStatusAsync(app, phone.Token, timer.Token);
        Assert.True(enabled.GetProperty("remoteDesktopEnabled").GetBoolean());
        Assert.Equal(0, enabled.GetProperty("remoteDesktopRevision").GetInt32());
        desktopRevision++;
        var updated = await ReadStatusAsync(app, phone.Token, timer.Token);
        Assert.Equal(1, updated.GetProperty("remoteDesktopRevision").GetInt32());

        var otherStatus = await ReadStatusAsync(app, other.Token, timer.Token);
        Assert.False(otherStatus.GetProperty("remoteDesktopEnabled").GetBoolean());
        Assert.Equal(JsonValueKind.Null, otherStatus.GetProperty("remoteDesktopRevision").ValueKind);
        await RejectAsync(app, other.Token, HttpStatusCode.Forbidden, timer.Token);
        await using var bluetooth = await StartHostAsync(RemoteTransport.Bluetooth);
        var bluetoothStatus = await ReadStatusAsync(bluetooth, phone.Token, timer.Token);
        Assert.False(bluetoothStatus.GetProperty("remoteDesktopEnabled").GetBoolean());
        Assert.Equal(JsonValueKind.Null, bluetoothStatus.GetProperty("remoteDesktopRevision").ValueKind);
        await RejectAsync(bluetooth, phone.Token, HttpStatusCode.NotFound, timer.Token);
        Assert.False(backend.Pending());
    }

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public async Task ViewerForwardsBinaryAndRevocationClosesTheActiveBackend(bool viewerStatus)
    {
        using var timer = new CancellationTokenSource(TimeSpan.FromSeconds(8));
        var phone = Pair("Phone");
        pairing.SetRemoteDesktopAccess(phone.Id, true);
        using var viewer = CreateSocket(phone.Token, viewerStatus);
        var connecting = viewer.ConnectAsync(DesktopUri(app), timer.Token);
        using var vnc = await backend.AcceptTcpClientAsync(timer.Token);
        var stream = vnc.GetStream();
        var greeting = "RFB 003.008\n"u8.ToArray();
        await stream.WriteAsync(greeting, timer.Token);
        await connecting;
        var frame = new byte[16];
        var message = await viewer.ReceiveAsync(frame.AsMemory(), timer.Token);
        Assert.Equal(WebSocketMessageType.Binary, message.MessageType);
        Assert.Equal(greeting, frame[..message.Count]);
        Assert.Equal(viewerStatus ? "tapmypc.viewer-status.v1" : null, viewer.SubProtocol);
        Assert.Null(pairing.RemoteDesktopViewer);
        Assert.DoesNotContain(scheduler.Activity.Recent, item => item.Message == "Remote Desktop connected · Phone");
        if (viewerStatus)
        {
            await viewer.SendAsync("viewer-"u8.ToArray().AsMemory(), WebSocketMessageType.Text, false, timer.Token);
            await viewer.SendAsync("ready"u8.ToArray().AsMemory(), WebSocketMessageType.Text, true, timer.Token);
        }

        await using var tailscale = await StartHostAsync(RemoteTransport.Tailscale);
        await RejectAsync(tailscale, phone.Token, HttpStatusCode.Conflict, timer.Token);
        Assert.False(backend.Pending());
        await viewer.SendAsync(new byte[] { 4, 1, 0 }.AsMemory(), WebSocketMessageType.Binary, false, timer.Token);
        await viewer.SendAsync(new byte[] { 0, 0, 0, 255, 13 }.AsMemory(), WebSocketMessageType.Binary, true, timer.Token);
        var input = new byte[8];
        await stream.ReadExactlyAsync(input, timer.Token);
        Assert.Equal(new byte[] { 4, 1, 0, 0, 0, 0, 255, 13 }, input);
        Assert.Equal(viewerStatus ? "Phone" : null, pairing.RemoteDesktopViewer);
        Assert.Equal(viewerStatus, scheduler.Activity.Recent.Any(item => item.Message == "Remote Desktop connected · Phone"));

        await stream.WriteAsync(new byte[] { 0, 0, 0, 0 }, timer.Token);
        message = await viewer.ReceiveAsync(frame.AsMemory(), timer.Token);
        Assert.Equal(WebSocketMessageType.Binary, message.MessageType);
        Assert.Equal(new byte[] { 0, 0, 0, 0 }, frame[..message.Count]);

        pairing.SetRemoteDesktopAccess(phone.Id, false);
        Assert.Null(pairing.RemoteDesktopViewer);
        Assert.Equal(0, await stream.ReadAsync(input, timer.Token));
        await RejectAsync(app, phone.Token, HttpStatusCode.Forbidden, timer.Token);
        Assert.Equal(viewerStatus, scheduler.Activity.Recent.Any(item => item.Message == "Remote Desktop disconnected · Phone"));
    }

    [Fact]
    public async Task RejectsNonVncLoopbackServicesBeforeUpgrading()
    {
        using var timer = new CancellationTokenSource(TimeSpan.FromSeconds(8));
        var phone = Pair("Phone");
        pairing.SetRemoteDesktopAccess(phone.Id, true);
        var connecting = RejectAsync(app, phone.Token, HttpStatusCode.ServiceUnavailable, timer.Token);
        using var vnc = await backend.AcceptTcpClientAsync(timer.Token);
        await vnc.GetStream().WriteAsync("HTTP/1.1 200"u8.ToArray(), timer.Token);
        await connecting;
    }

    private Task<WebApplication> StartHostAsync(RemoteTransport transport) =>
        ApiHost.StartAsync(IPAddress.Loopback, 0, certificate, device, pairing, scheduler, transport: transport,
            remoteDesktopPort: ((IPEndPoint)backend.LocalEndpoint).Port,
            remoteDesktopRevision: () => desktopRevision);

    private (Guid Id, string Token) Pair(string name)
    {
        var token = pairing.Pair(pairing.OpenPairing().Code, name);
        return (pairing.Clients.Single(client => client.Name == name).Id, token);
    }

    private ClientWebSocket CreateSocket(string? token, bool viewerStatus = false)
    {
        var socket = new ClientWebSocket();
        socket.Options.RemoteCertificateValidationCallback = (_, cert, _, _) => cert?.GetRawCertData().SequenceEqual(certificate.RawData) == true;
        socket.Options.CollectHttpResponseDetails = true;
        if (viewerStatus) socket.Options.AddSubProtocol("tapmypc.viewer-status.v1");
        if (token is not null) socket.Options.SetRequestHeader("Authorization", $"Bearer {token}");
        return socket;
    }

    private async Task<JsonElement> ReadStatusAsync(WebApplication host, string token, CancellationToken stop)
    {
        using var client = new HttpClient(new HttpClientHandler
        {
            ServerCertificateCustomValidationCallback = (_, cert, _, _) => cert?.Thumbprint == certificate.Thumbprint
        }) { BaseAddress = new Uri(host.Urls.Single()) };
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
        return await client.GetFromJsonAsync<JsonElement>("/api/v1/status", stop);
    }

    private async Task RejectAsync(WebApplication host, string? token, HttpStatusCode expected, CancellationToken stop)
    {
        using var socket = CreateSocket(token);
        var error = await Assert.ThrowsAsync<WebSocketException>(() => socket.ConnectAsync(DesktopUri(host), stop));
        Assert.True(expected == socket.HttpStatusCode, $"Expected {expected}, received {socket.HttpStatusCode}. {error}");
    }

    private static Uri DesktopUri(WebApplication host) =>
        new UriBuilder(host.Urls.Single()) { Scheme = "wss", Path = "/api/v1/remote-desktop" }.Uri;
}
