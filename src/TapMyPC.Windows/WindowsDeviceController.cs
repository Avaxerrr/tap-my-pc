using System.Runtime.InteropServices;
using TapMyPC.Core.Devices;
using TapMyPC.Windows.Audio;
using TapMyPC.Windows.Interop;
using TapMyPC.Windows.Power;
using TapMyPC.Windows.Media;
using TapMyPC.Windows.Display;

namespace TapMyPC.Windows;

public sealed class WindowsDeviceController : IDeviceController
{
    public DeviceCapabilities Capabilities
    {
        get
        {
            var audio = true;
            try { EndpointAudio.Read(); } catch (COMException) { audio = false; }
            return new(audio, true, true, NativeMethods.IsPwrSuspendAllowed(), NativeMethods.IsPwrHibernateAllowed());
        }
    }
    public AudioState ReadAudio() => EndpointAudio.Read();
    public void SetVolume(int percent)
    {
        if (percent is < 0 or > 100) throw new ArgumentException("Volume must be 0–100.");
        EndpointAudio.WithEndpoint(endpoint =>
        {
            var context = Guid.Empty;
            Marshal.ThrowExceptionForHR(endpoint.SetMasterVolumeLevelScalar(percent / 100f, ref context));
            return true;
        });
    }
    public void SetMute(bool muted) => EndpointAudio.WithEndpoint(endpoint =>
    {
        var context = Guid.Empty;
        Marshal.ThrowExceptionForHR(endpoint.SetMute(muted, ref context));
        return true;
    });

    public void SendMedia(MediaAction action) => MediaControl.Send(action);
    public void StepVolume(VolumeDirection direction) => MediaControl.SendKey(direction switch
    {
        VolumeDirection.Up => 0xAF,
        VolumeDirection.Down => 0xAE,
        _ => throw new ArgumentException("Unknown volume direction.")
    });
    public void TurnOffDisplays() => DisplayControl.TurnOff();
    public void ExecutePower(PowerAction action) => PowerControl.Execute(action);
}
