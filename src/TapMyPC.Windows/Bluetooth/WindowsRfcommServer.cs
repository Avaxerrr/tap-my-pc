using System.Collections.Concurrent;
using System.Net;
using System.Net.Sockets;
using TapMyPC.Core.Bluetooth;
using Windows.Devices.Bluetooth;
using Windows.Devices.Bluetooth.Rfcomm;
using Windows.Devices.Radios;
using Windows.Networking.Sockets;

namespace TapMyPC.Windows.Bluetooth;

/// <summary>Encrypted RFCOMM byte transport to a fixed, process-owned loopback TLS listener.</summary>
public sealed class WindowsRfcommServer : IAsyncDisposable
{
    private readonly IPEndPoint endpoint;
    private readonly CancellationTokenSource lifetime = new();
    private readonly ConcurrentDictionary<Guid, StreamSocket> connections = new();
    private readonly ConcurrentDictionary<Guid, Task> pending = new();
    private readonly SemaphoreSlim slots = new(4, 4);
    private RfcommServiceProvider? provider;
    private StreamSocketListener? listener;
    public BluetoothConnectionInfo Info { get; private set; } = new(false, null, BluetoothConnectionInfo.ServiceUuid);

    private WindowsRfcommServer(IPEndPoint endpoint) => this.endpoint = endpoint;

    public static async Task<bool> RadioReadyAsync()
    {
        var radios = await Radio.GetRadiosAsync();
        return radios.Any(r => r.Kind == RadioKind.Bluetooth && r.State == RadioState.On);
    }

    public static async Task<WindowsRfcommServer> StartAsync(IPEndPoint endpoint)
    {
        if (!IPAddress.IsLoopback(endpoint.Address)) throw new ArgumentException("Bluetooth forwarding must target the local process.");
        var server = new WindowsRfcommServer(endpoint);
        try
        {
            var adapter = await BluetoothAdapter.GetDefaultAsync();
            if (adapter is null || !adapter.IsClassicSupported) throw new NotSupportedException("No Classic Bluetooth adapter is available.");
            if (!await RadioReadyAsync()) throw new NotSupportedException("Turn on Bluetooth on the PC to use the secondary connection.");
            server.provider = await RfcommServiceProvider.CreateAsync(RfcommServiceId.FromUuid(Guid.Parse(BluetoothConnectionInfo.ServiceUuid)));
            if (server.provider is null) throw new NotSupportedException("Windows could not create the Bluetooth connection service.");
            server.listener = new StreamSocketListener();
            server.listener.ConnectionReceived += server.OnConnection;
            await server.listener.BindServiceNameAsync(server.provider.ServiceId.AsString(), SocketProtectionLevel.BluetoothEncryptionWithAuthentication);
            server.provider.StartAdvertising(server.listener, true);
            var hex = adapter.BluetoothAddress.ToString("X12");
            var address = string.Join(":", Enumerable.Range(0, 6).Select(i => hex.Substring(i * 2, 2)));
            server.Info = new(true, address, BluetoothConnectionInfo.ServiceUuid);
            return server;
        }
        catch { await server.DisposeAsync(); throw; }
    }

    private void OnConnection(StreamSocketListener sender, StreamSocketListenerConnectionReceivedEventArgs args)
    {
        if (lifetime.IsCancellationRequested || !slots.Wait(0)) { args.Socket.Dispose(); return; }
        var id = Guid.NewGuid();
        connections[id] = args.Socket;
        var task = ForwardAsync(args.Socket);
        pending[id] = task;
        _ = task.ContinueWith(completed => {
            connections.TryRemove(id, out _); pending.TryRemove(id, out _); slots.Release();
        }, CancellationToken.None, TaskContinuationOptions.ExecuteSynchronously, TaskScheduler.Default);
    }

    private async Task ForwardAsync(StreamSocket socket)
    {
        using (socket)
        using (var tcp = new TcpClient())
        using (var transfer = CancellationTokenSource.CreateLinkedTokenSource(lifetime.Token))
        {
            try
            {
                await tcp.ConnectAsync(endpoint.Address, endpoint.Port, transfer.Token);
                using var input = socket.InputStream.AsStreamForRead(bufferSize: 0);
                using var output = socket.OutputStream.AsStreamForWrite(bufferSize: 0);
                using var local = tcp.GetStream();
                var inbound = input.CopyToAsync(local, 16384, transfer.Token);
                var outbound = local.CopyToAsync(output, 16384, transfer.Token);
                await Task.WhenAny(inbound, outbound);
                await transfer.CancelAsync();
                socket.Dispose(); tcp.Dispose();
                try { await Task.WhenAll(inbound, outbound); } catch { }
            }
            catch (Exception) { /* Closing/failed links cannot stop the listener. */ }
        }
    }

    public async ValueTask DisposeAsync()
    {
        await lifetime.CancelAsync();
        if (provider is not null) { try { provider.StopAdvertising(); } catch { } provider = null; }
        if (listener is not null) { listener.ConnectionReceived -= OnConnection; listener.Dispose(); listener = null; }
        foreach (var socket in connections.Values) socket.Dispose();
        try { await Task.WhenAll(pending.Values).WaitAsync(TimeSpan.FromSeconds(5)); } catch { }
        Info = Info with { Available = false };
    }
}
