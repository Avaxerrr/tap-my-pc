using TapMyPC.Core.Feedback;

namespace TapMyPC.Core.Devices;

public sealed class RemoteCommands(IDeviceController device, ActionFeed activity)
{
    public ActionNotice SetVolume(int volume)
    {
        if (volume is < 0 or > 100) throw new ArgumentException("Volume must be 0–100.");
        return Execute("Volume", $"Setting volume to {volume}%…", () =>
        {
            device.SetVolume(volume);
            var state = device.ReadAudio();
            return ($"Volume {state.Volume}%", state);
        });
    }

    public ActionNotice SetMute(bool muted) => Execute("Audio", muted ? "Muting audio…" : "Unmuting audio…", () =>
    {
        device.SetMute(muted);
        var state = device.ReadAudio();
        return (state.Muted ? "Audio muted" : $"Audio unmuted · {state.Volume}%", state);
    });

    public ActionNotice StepVolume(VolumeDirection direction)
    {
        if (!Enum.IsDefined(direction)) throw new ArgumentException("Unknown volume direction.");
        return Execute("Volume", $"Volume {direction.ToString().ToLowerInvariant()}…", () =>
        {
            device.StepVolume(direction);
            return ($"Volume {direction.ToString().ToLowerInvariant()} key sent", (AudioState?)null);
        }, ActionPhase.Requested);
    }

    public ActionNotice Media(MediaAction action)
    {
        if (!Enum.IsDefined(action)) throw new ArgumentException("Unknown media action.");
        var label = action switch { MediaAction.PlayPause => "Play / pause", MediaAction.Next => "Next track", _ => "Previous track" };
        return Execute("Media", $"Sending {label.ToLowerInvariant()}…", () =>
        {
            device.SendMedia(action);
            return ($"{label} sent to Windows", (AudioState?)null);
        }, ActionPhase.Requested);
    }

    public ActionNotice DisplaysOff() => Execute("Displays", "Turning monitors off…", () =>
    {
        device.TurnOffDisplays();
        return ("Display-off request sent · input may wake the monitors", (AudioState?)null);
    }, ActionPhase.Requested);

    private ActionNotice Execute(string title, string pending, Func<(string Message, AudioState? Audio)> action, ActionPhase completed = ActionPhase.Succeeded)
    {
        activity.Publish(title, pending, ActionPhase.Running);
        try
        {
            var result = action();
            return activity.Publish(title, result.Message, completed, result.Audio);
        }
        catch
        {
            activity.Publish(title, $"{title} command failed. Check the PC and try again.", ActionPhase.Failed);
            throw;
        }
    }
}
