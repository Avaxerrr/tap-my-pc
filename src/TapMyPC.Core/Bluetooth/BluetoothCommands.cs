using TapMyPC.Core.Feedback;

namespace TapMyPC.Core.Bluetooth;

public sealed class BluetoothCommands(IBluetoothController controller, ActionFeed activity)
{
    public async Task<ActionNotice> SetEnabledAsync(bool enabled)
    {
        activity.Publish("Bluetooth", enabled ? "Turning Bluetooth on…" : "Turning Bluetooth off…", ActionPhase.Running);
        try
        {
            await controller.SetEnabledAsync(enabled);
            var state = await controller.ReadAsync();
            var confirmed = state.State == (enabled ? BluetoothRadioState.On : BluetoothRadioState.Off);
            return activity.Publish("Bluetooth",
                confirmed ? $"Bluetooth {(enabled ? "on" : "off")}" : $"Bluetooth {(enabled ? "on" : "off")} requested; current state: {state.State.ToString().ToLowerInvariant()}.",
                confirmed ? ActionPhase.Succeeded : ActionPhase.Requested);
        }
        catch (Exception ex)
        {
            activity.Publish("Bluetooth", ex is NotSupportedException or InvalidOperationException ? ex.Message : "Bluetooth command failed. Check the PC and try again.", ActionPhase.Failed);
            throw;
        }
    }
}
