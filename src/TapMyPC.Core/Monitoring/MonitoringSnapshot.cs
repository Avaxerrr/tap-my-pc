namespace TapMyPC.Core.Monitoring;

public interface IMonitoringSource
{
    Task<MonitoringSnapshot?> ReadAsync(CancellationToken cancellationToken);
}

public sealed record MonitoringSnapshot(
    DateTimeOffset GeneratedAtUtc, int RefreshIntervalMs, IReadOnlyList<MonitoringMetric> Metrics)
{
    public bool IsStaleAt(DateTimeOffset now) => now - GeneratedAtUtc >
        TimeSpan.FromMilliseconds(Math.Max(5_000, RefreshIntervalMs * 3));
}

public sealed record MonitoringMetric(
    string Key, string Label, string Group, string? SourceName, string? Value,
    bool Available, bool DefaultVisible, double? NumericValue, string? Unit, double? TotalValue);
