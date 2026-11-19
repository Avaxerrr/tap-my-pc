using System.Net;
using System.Net.Sockets;
using System.Net.WebSockets;
using Microsoft.AspNetCore.Http;
using TapMyPC.Core.Devices;
using TapMyPC.Core.Feedback;

namespace TapMyPC.Api.Endpoints;

internal static class RemoteDesktopEndpoint
{
    internal const string Path = "/api/v1/remote-desktop";
    private const string ViewerStatusProtocol = "tapmypc.viewer-status.v1";

    internal static async Task RunAsync(HttpContext context, Guid clientId, PairingService pairing,
        int port, ActionFeed activity, CancellationToken hostStopping)
    {
        if (!pairing.AllowsRemoteDesktop(clientId))
        {
            context.Response.StatusCode = StatusCodes.Status403Forbidden;
            return;
        }
        if (!context.WebSockets.IsWebSocketRequest)
        {
            context.Response.StatusCode = StatusCodes.Status400BadRequest;
            return;
        }
        try
        {
            await pairing.RunRemoteDesktopAsync(clientId, stop =>
                ConnectAsync(context, clientId, pairing, port, activity, stop, hostStopping));
        }
        catch (UnauthorizedAccessException) when (!context.Response.HasStarted)
        {
            context.Response.StatusCode = StatusCodes.Status403Forbidden;
        }
    }

    private static async Task ConnectAsync(HttpContext context, Guid clientId, PairingService pairing, int port,
        ActionFeed activity, CancellationToken permissionRevoked, CancellationToken hostStopping)
    {
        using var stopped = CancellationTokenSource.CreateLinkedTokenSource(
            context.RequestAborted, permissionRevoked, hostStopping);
        using var backend = new TcpClient(AddressFamily.InterNetwork);
        var greeting = new byte[12];
        NetworkStream stream;
        try
        {
            using var startup = CancellationTokenSource.CreateLinkedTokenSource(stopped.Token);
            startup.CancelAfter(TimeSpan.FromSeconds(4));
            await backend.ConnectAsync(IPAddress.Loopback, port, startup.Token);
            backend.NoDelay = true;
            stream = backend.GetStream();
            await stream.ReadExactlyAsync(greeting, startup.Token);
            if (!greeting.AsSpan(0, 11).StartsWith("RFB 003."u8) ||
                greeting[8] != '0' || greeting[9] != '0' ||
                greeting[10] is not ((byte)'3' or (byte)'6' or (byte)'7' or (byte)'8') || greeting[11] != '\n')
                throw new IOException("Unexpected VNC server greeting.");
        }
        catch (Exception ex) when (ex is IOException or SocketException or OperationCanceledException)
        {
            if (stopped.IsCancellationRequested) return;
            context.Response.StatusCode = StatusCodes.Status503ServiceUnavailable;
            await context.Response.WriteAsJsonAsync(new { error = "Start the local UltraVNC Server service on the PC." }, stopped.Token);
            return;
        }

        if (stopped.IsCancellationRequested) return;
        var reportsViewerStatus = context.WebSockets.WebSocketRequestedProtocols.Contains(ViewerStatusProtocol);
        using var viewer = await context.WebSockets.AcceptWebSocketAsync(reportsViewerStatus ? ViewerStatusProtocol : null);
        var name = pairing.Clients.FirstOrDefault(client => client.Id == clientId)?.Name ?? "Paired phone";
        var ready = false;
        void MarkReady()
        {
            if (ready || !pairing.MarkRemoteDesktopReady(clientId)) return;
            ready = true;
            activity.Publish("Remote Desktop", $"Remote Desktop connected · {name}", ActionPhase.Succeeded);
        }
        try
        {
            await viewer.SendAsync(greeting.AsMemory(), WebSocketMessageType.Binary, true, stopped.Token);
            var receive = CopyInputAsync(viewer, stream, reportsViewerStatus ? MarkReady : null, stopped.Token);
            var send = CopyScreenAsync(stream, viewer, stopped.Token);
            await Task.WhenAny(receive, send);
            if (send.IsCompletedSuccessfully && viewer.State == WebSocketState.Open)
                await CloseOutputAsync(viewer);
            await stopped.CancelAsync();
            try { await Task.WhenAll(receive, send); }
            finally
            {
                if (viewer.State is WebSocketState.Open or WebSocketState.CloseReceived)
                    await CloseOutputAsync(viewer);
            }
        }
        catch (Exception ex) when (ex is IOException or SocketException or WebSocketException or OperationCanceledException or ObjectDisposedException) { }
        finally
        {
            if (ready)
                activity.Publish("Remote Desktop", $"Remote Desktop disconnected · {name}", ActionPhase.Succeeded);
        }
    }

    private static async Task CloseOutputAsync(WebSocket socket)
    {
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(1));
        try { await socket.CloseOutputAsync(WebSocketCloseStatus.NormalClosure, null, timeout.Token); }
        catch (Exception ex) when (ex is WebSocketException or OperationCanceledException) { }
    }

    private static async Task CopyInputAsync(WebSocket viewer, Stream backend, Action? markReady, CancellationToken stop)
    {
        var buffer = new byte[16 * 1024];
        var marker = "viewer-ready"u8.ToArray();
        var markerOffset = 0;
        while (true)
        {
            var packet = await viewer.ReceiveAsync(buffer.AsMemory(), stop);
            if (packet.MessageType == WebSocketMessageType.Text && markReady is not null)
            {
                if (packet.Count > marker.Length - markerOffset ||
                    !buffer.AsSpan(0, packet.Count).SequenceEqual(marker.AsSpan(markerOffset, packet.Count)))
                    return;
                markerOffset += packet.Count;
                if (packet.EndOfMessage)
                {
                    if (markerOffset != marker.Length) return;
                    markReady();
                    markerOffset = 0;
                }
                continue;
            }
            if (packet.MessageType != WebSocketMessageType.Binary) return;
            await backend.WriteAsync(buffer.AsMemory(0, packet.Count), stop);
        }
    }

    private static async Task CopyScreenAsync(Stream backend, WebSocket viewer, CancellationToken stop)
    {
        var buffer = new byte[32 * 1024];
        int count;
        while ((count = await backend.ReadAsync(buffer.AsMemory(), stop)) > 0)
            await viewer.SendAsync(buffer.AsMemory(0, count), WebSocketMessageType.Binary, true, stop);
    }
}
