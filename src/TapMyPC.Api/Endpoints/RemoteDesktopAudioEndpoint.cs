using System.Net.WebSockets;
using Microsoft.AspNetCore.Http;
using TapMyPC.Core.Audio;
using TapMyPC.Core.Devices;
using TapMyPC.Core.Feedback;

namespace TapMyPC.Api.Endpoints;

internal static class RemoteDesktopAudioEndpoint
{
    internal const string Path = "/api/v1/remote-desktop/audio";
    private const string Protocol = "tapmypc.audio.opus.v1";

    internal static async Task RunAsync(HttpContext context, Guid clientId, PairingService pairing,
        IRemoteDesktopAudioSource source, ActionFeed activity, CancellationToken hostStopping)
    {
        if (!pairing.AllowsRemoteDesktopAudio(clientId))
        {
            context.Response.StatusCode = StatusCodes.Status403Forbidden;
            return;
        }
        if (!context.WebSockets.IsWebSocketRequest || !context.WebSockets.WebSocketRequestedProtocols.Contains(Protocol))
        {
            context.Response.StatusCode = StatusCodes.Status400BadRequest;
            return;
        }
        try
        {
            var name = pairing.Clients.FirstOrDefault(client => client.Id == clientId)?.Name ?? "Paired phone";
            await pairing.RunRemoteDesktopAudioAsync(clientId, stop =>
                StreamAsync(context, source, activity, name, stop, hostStopping));
        }
        catch (UnauthorizedAccessException) when (!context.Response.HasStarted)
        {
            context.Response.StatusCode = StatusCodes.Status403Forbidden;
        }
    }

    private static async Task StreamAsync(HttpContext context, IRemoteDesktopAudioSource source,
        ActionFeed activity, string name, CancellationToken permissionRevoked, CancellationToken hostStopping)
    {
        using var stopped = CancellationTokenSource.CreateLinkedTokenSource(
            context.RequestAborted, permissionRevoked, hostStopping);
        stopped.Token.ThrowIfCancellationRequested();
        using var socket = await context.WebSockets.AcceptWebSocketAsync(Protocol);
        activity.Publish("Remote Desktop audio", $"Sharing PC playback · {name}", ActionPhase.Succeeded);
        var receive = WaitForCloseAsync(socket, stopped.Token);
        var send = SendAudioAsync(socket, source, stopped.Token);
        try
        {
            await Task.WhenAny(receive, send);
            var failed = send.IsFaulted && !stopped.IsCancellationRequested &&
                send.Exception?.GetBaseException() is not (IOException or WebSocketException or ObjectDisposedException);
            if (failed)
                activity.Publish("Remote Desktop audio", "Could not capture the default Windows audio output.", ActionPhase.Failed);
            if (socket.State is WebSocketState.CloseReceived || send.IsCompleted && socket.State is WebSocketState.Open)
            {
                using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(1));
                await socket.CloseOutputAsync(failed ? WebSocketCloseStatus.InternalServerError : WebSocketCloseStatus.NormalClosure,
                    failed ? "Audio capture failed." : null, timeout.Token);
            }
        }
        catch (Exception ex) when (ex is IOException or WebSocketException or OperationCanceledException or ObjectDisposedException) { }
        finally
        {
            await stopped.CancelAsync();
            // Observe both tasks after closing. Any capture failure has been reported above.
            await Task.WhenAll(receive, send).ConfigureAwait(ConfigureAwaitOptions.SuppressThrowing);
            activity.Publish("Remote Desktop audio", $"PC playback sharing ended · {name}", ActionPhase.Succeeded);
        }
    }

    private static async Task WaitForCloseAsync(WebSocket socket, CancellationToken stop)
    {
        // The channel is send-only. Any application data from the viewer ends it.
        await socket.ReceiveAsync(new byte[1].AsMemory(), stop);
    }

    private static async Task SendAudioAsync(WebSocket socket, IRemoteDesktopAudioSource source, CancellationToken stop)
    {
        await foreach (var packet in source.CaptureAsync(stop))
            await socket.SendAsync(packet, WebSocketMessageType.Binary, true, stop);
    }
}
