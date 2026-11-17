namespace TapMyPC.Core.Devices;

public record AudioState(int Volume, bool Muted);
public record DeviceCapabilities(bool Audio, bool Media, bool Display, bool Sleep, bool Hibernate);
public enum PowerAction { Lock, Sleep, Hibernate, Shutdown, Restart }
public enum MediaAction { PlayPause, Previous, Next }
public enum VolumeDirection { Up, Down }

public interface IDeviceController
{
    DeviceCapabilities Capabilities { get; }
    AudioState ReadAudio();
    void SetVolume(int percent);
    void SetMute(bool muted);
    void StepVolume(VolumeDirection direction);
    void SendMedia(MediaAction action);
    void TurnOffDisplays();
    void ExecutePower(PowerAction action);
}
