namespace TapMyPC.Core.Bluetooth;

public enum BluetoothRadioState { On, Off, Mixed, Disabled, Unavailable }
public record BluetoothStatus(bool Available, bool CanControl, BluetoothRadioState State, string? Message = null);

public interface IBluetoothController
{
    Task<BluetoothStatus> ReadAsync();
    Task SetEnabledAsync(bool enabled);
}
