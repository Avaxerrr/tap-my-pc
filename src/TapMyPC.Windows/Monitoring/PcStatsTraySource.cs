using System.Net.Http;
using System.Net.Http.Json;
using System.Text.Json;
using TapMyPC.Core.Monitoring;

namespace TapMyPC.Windows.Monitoring;

public sealed class PcStatsTraySource : IMonitoringSource
{
    private const string Endpoint = "http://127.0.0.1:4587/api/metrics";
    private static readonly HttpClient Client = new(new SocketsHttpHandler
    {
        UseProxy = false,
        AllowAutoRedirect = false
    })
    {
        Timeout = TimeSpan.FromSeconds(2),
        MaxResponseContentBufferSize = 512 * 1024
    };

    public async Task<MonitoringSnapshot?> ReadAsync(CancellationToken cancellationToken)
    {
        try
        {
            using var response = await Client.GetAsync(Endpoint, cancellationToken);
            if (!response.IsSuccessStatusCode) return null;

            var snapshot = await response.Content.ReadFromJsonAsync<MonitoringSnapshot>(cancellationToken);
            return snapshot is
                { RefreshIntervalMs: 1000 or 2000 or 5000, Metrics: not null, GeneratedAtUtc: var timestamp }
                && timestamp != default && timestamp <= DateTimeOffset.UtcNow.AddMinutes(1)
                ? snapshot : null;
        }
        catch (HttpRequestException) { return null; }
        catch (JsonException) { return null; }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested) { return null; }
    }
}
