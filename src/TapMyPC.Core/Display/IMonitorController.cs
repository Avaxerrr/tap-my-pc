namespace TapMyPC.Core.Display;

public record MonitorStatus(string Id, string Name, int? Brightness, bool CanSetBrightness, bool CanSetPower, bool? IsOn, string? Message = null);
public interface IMonitorController
{
    Task<IReadOnlyList<MonitorStatus>> ListAsync();
    Task SetBrightnessAsync(string id, int brightness);
    Task SetPowerAsync(string id, bool enabled);
}
