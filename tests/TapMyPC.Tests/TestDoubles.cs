using TapMyPC.Core.Devices;
using TapMyPC.Core.Bluetooth;

namespace TapMyPC.Tests;

internal sealed class FakeDevice : IDeviceController
{
    public DeviceCapabilities Capabilities { get; set; } = new(true, true, true, true, true);
    public AudioState Audio { get; private set; } = new(35, false);
    public List<PowerAction> PowerActions { get; } = [];
    public List<MediaAction> MediaActions { get; } = [];
    public bool FailPower { get; set; }
    public bool FailAudio { get; set; }
    public int DisplaysOff { get; private set; }
    public AudioState ReadAudio() => Audio;
    public void SetVolume(int percent)
    {
        if (FailAudio) throw new InvalidOperationException("Simulated audio rejection.");
        Audio = Audio with { Volume = percent };
    }
    public void SetMute(bool muted) => Audio = Audio with { Muted = muted };
    public void StepVolume(VolumeDirection direction) => SetVolume(Math.Clamp(Audio.Volume + (direction == VolumeDirection.Up ? 2 : -2), 0, 100));
    public void SendMedia(MediaAction action) => MediaActions.Add(action);
    public void TurnOffDisplays() => DisplaysOff++;
    public void ExecutePower(PowerAction action)
    {
        if (FailPower) throw new InvalidOperationException("Simulated Windows rejection.");
        PowerActions.Add(action);
    }
}

internal sealed class MemoryStore : IDeviceStore
{
    public IReadOnlyList<PairedDevice> Devices { get; private set; } = [];
    public IReadOnlyList<PairedDevice> Load() => Devices;
    public void Save(IReadOnlyList<PairedDevice> devices) => Devices = devices.ToArray();
}

internal sealed class FakeBluetooth : IBluetoothController
{
    public BluetoothStatus Status { get; set; } = new(true, true, BluetoothRadioState.On);
    public List<bool> Changes { get; } = [];
    public bool ConfirmChange { get; set; } = true;
    public Task<BluetoothStatus> ReadAsync() => Task.FromResult(Status);
    public Task SetEnabledAsync(bool enabled)
    {
        if (!Status.CanControl) throw new NotSupportedException(Status.Message ?? "Bluetooth control is unavailable.");
        Changes.Add(enabled);
        if (ConfirmChange) Status = Status with { State = enabled ? BluetoothRadioState.On : BluetoothRadioState.Off };
        return Task.CompletedTask;
    }
}
