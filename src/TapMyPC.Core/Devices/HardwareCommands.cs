using TapMyPC.Core.Audio;
using TapMyPC.Core.Display;
using TapMyPC.Core.Feedback;

namespace TapMyPC.Core.Devices;

public sealed class HardwareCommands(ActionFeed activity)
{
    public async Task<ActionNotice> SelectOutputAsync(IAudioOutputController outputs, string id)
    {
        if (string.IsNullOrWhiteSpace(id)) throw new ArgumentException("Choose an audio output.");
        var output = outputs.List().SingleOrDefault(o => o.Id == id) ?? throw new ArgumentException("That audio output is no longer available. Refresh devices.");
        return await ExecuteAsync("Audio output", () =>
        {
            outputs.Select(id);
            var confirmed = outputs.List().Any(o => o.Id == id && o.IsDefault);
            return Task.FromResult((confirmed ? $"Audio output: {output.Name}" : $"Audio output change requested: {output.Name}", confirmed));
        });
    }

    public async Task<ActionNotice> SetBrightnessAsync(IMonitorController monitors, string id, int brightness)
    {
        if (brightness is < 0 or > 100) throw new ArgumentException("Brightness must be 0–100.");
        var monitor = await FindMonitor(monitors, id);
        if (!monitor.CanSetBrightness) throw new NotSupportedException("Brightness control is unavailable for this monitor.");
        return await ExecuteAsync("Monitor brightness", async () =>
        {
            await monitors.SetBrightnessAsync(id, brightness);
            return ($"{monitor.Name}: brightness {brightness}% requested", false);
        });
    }

    public async Task<ActionNotice> SetMonitorPowerAsync(IMonitorController monitors, string id, bool enabled)
    {
        var monitor = await FindMonitor(monitors, id);
        if (!monitor.CanSetPower) throw new NotSupportedException("Individual power control is unavailable for this monitor.");
        return await ExecuteAsync("Monitor power", async () =>
        {
            await monitors.SetPowerAsync(id, enabled);
            return ($"{monitor.Name}: {(enabled ? "on" : "off")} requested", false);
        });
    }

    private static async Task<MonitorStatus> FindMonitor(IMonitorController monitors, string id)
    {
        if (string.IsNullOrWhiteSpace(id)) throw new ArgumentException("Choose a monitor.");
        return (await monitors.ListAsync()).SingleOrDefault(m => m.Id == id) ?? throw new ArgumentException("That monitor is no longer available. Refresh devices.");
    }

    private async Task<ActionNotice> ExecuteAsync(string title, Func<Task<(string Message, bool Confirmed)>> action)
    {
        activity.Publish(title, $"Sending {title.ToLowerInvariant()} command…", ActionPhase.Running);
        try
        {
            var result = await action();
            return activity.Publish(title, result.Message, result.Confirmed ? ActionPhase.Succeeded : ActionPhase.Requested);
        }
        catch
        {
            activity.Publish(title, $"{title} command failed. Check the PC and refresh devices.", ActionPhase.Failed);
            throw;
        }
    }
}
