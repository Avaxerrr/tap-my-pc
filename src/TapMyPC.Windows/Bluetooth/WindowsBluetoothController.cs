using TapMyPC.Core.Bluetooth;
using Windows.Devices.Radios;

namespace TapMyPC.Windows.Bluetooth;

/// <summary>Controls Bluetooth radios only; never touches Wi-Fi or disables PnP devices.</summary>
public sealed class WindowsBluetoothController(Func<Func<Task>, Task> runOnUiThread) : IBluetoothController
{
    private readonly SemaphoreSlim changeGate = new(1, 1);
    private bool accessGranted;

    public async Task<BluetoothStatus> ReadAsync()
    {
        try
        {
            var radios = (await Radio.GetRadiosAsync()).Where(r => r.Kind == RadioKind.Bluetooth).ToArray();
            if (radios.Length == 0) return new(false, false, BluetoothRadioState.Unavailable, "No Bluetooth adapter found.");
            var states = radios.Select(r => r.State).Distinct().ToArray();
            var state = states.Length != 1 ? BluetoothRadioState.Mixed : states[0] switch
            {
                RadioState.On => BluetoothRadioState.On,
                RadioState.Off => BluetoothRadioState.Off,
                RadioState.Disabled => BluetoothRadioState.Disabled,
                _ => BluetoothRadioState.Unavailable
            };
            var controllable = radios.All(r => r.State is RadioState.On or RadioState.Off);
            return new(true, controllable, state, controllable ? null : "Bluetooth is disabled or unavailable. Check Windows settings or the hardware switch.");
        }
        catch
        {
            return new(false, false, BluetoothRadioState.Unavailable, "Windows could not read Bluetooth status.");
        }
    }

    public async Task SetEnabledAsync(bool enabled)
    {
        if (!await changeGate.WaitAsync(0)) throw new InvalidOperationException("A Bluetooth change is already in progress.");
        try
        {
            var radios = (await Radio.GetRadiosAsync()).Where(r => r.Kind == RadioKind.Bluetooth).ToArray();
            if (radios.Length == 0) throw new NotSupportedException("No Bluetooth adapter found.");
            if (radios.Any(r => r.State is not (RadioState.On or RadioState.Off)))
                throw new NotSupportedException("Bluetooth is disabled or unavailable. Check Windows settings or the hardware switch.");
            var desired = enabled ? RadioState.On : RadioState.Off;
            if (radios.All(r => r.State == desired)) return;
            if (!accessGranted)
            {
                // Consent can require a valid UI thread, even when the command came from HTTP.
                await runOnUiThread(async () =>
                {
                    accessGranted = await Radio.RequestAccessAsync() == RadioAccessStatus.Allowed;
                });
                if (!accessGranted) throw new NotSupportedException("Windows denied Bluetooth control. Check radio permissions on the PC.");
            }
            foreach (var radio in radios.Where(r => r.State != desired))
            {
                var result = await radio.SetStateAsync(desired);
                if (result != RadioAccessStatus.Allowed)
                {
                    accessGranted = false;
                    throw new NotSupportedException("Windows rejected the Bluetooth change. Check permissions and Bluetooth settings on the PC.");
                }
            }
            // Accepted requests transition asynchronously. Bound the wait; the caller
            // reports Requested instead of Succeeded if the effective state differs.
            for (var attempt = 0; attempt < 10 && radios.Any(r => r.State != desired); attempt++)
                await Task.Delay(150);
        }
        finally { changeGate.Release(); }
    }
}
