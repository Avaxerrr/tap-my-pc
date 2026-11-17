using System.Runtime.InteropServices;
using TapMyPC.Core.Audio;
using static TapMyPC.Windows.Audio.EndpointAudio;

namespace TapMyPC.Windows.Audio;

public sealed class WindowsAudioOutputs : IAudioOutputController
{
    public IReadOnlyList<AudioOutput> List()
    {
        var enumerator = (IMMDeviceEnumerator)new MMDeviceEnumerator();
        IMMDeviceCollection? collection = null;
        IMMDevice? current = null;
        try
        {
            string? currentId = null;
            if (enumerator.GetDefaultAudioEndpoint(0, 1, out current) >= 0)
                Marshal.ThrowExceptionForHR(current.GetId(out currentId));
            Marshal.ThrowExceptionForHR(enumerator.EnumAudioEndpoints(0, 1, out collection)); // active render endpoints
            Marshal.ThrowExceptionForHR(collection.GetCount(out var count));
            var result = new List<AudioOutput>();
            for (uint i = 0; i < count; i++)
            {
                Marshal.ThrowExceptionForHR(collection.Item(i, out var device));
                IPropertyStore? properties = null;
                try
                {
                    Marshal.ThrowExceptionForHR(device.GetId(out var id));
                    Marshal.ThrowExceptionForHR(device.OpenPropertyStore(0, out properties));
                    var key = new PropertyKey { Format = new Guid("A45C254E-DF1C-4EFD-8020-67D146A850E0"), Id = 14 };
                    Marshal.ThrowExceptionForHR(properties.GetValue(ref key, out var value));
                    try
                    {
                        var name = value.Type == 31 ? Marshal.PtrToStringUni(value.Pointer) : null;
                        result.Add(new(id, name ?? "Audio output", id == currentId));
                    }
                    finally { PropVariantClear(ref value); }
                }
                finally
                {
                    if (properties is not null) Marshal.ReleaseComObject(properties);
                    Marshal.ReleaseComObject(device);
                }
            }
            return result;
        }
        finally
        {
            if (current is not null) Marshal.ReleaseComObject(current);
            if (collection is not null) Marshal.ReleaseComObject(collection);
            Marshal.ReleaseComObject(enumerator);
        }
    }

    public void Select(string id)
    {
        if (!List().Any(o => o.Id == id)) throw new ArgumentException("That audio output is no longer connected.");
        // IPolicyConfig is an undocumented Windows compatibility interface; keep
        // it isolated and surface failures instead of pretending to switch.
        var policy = (IPolicyConfig)new PolicyConfigClient();
        try
        {
            for (var role = 0; role < 3; role++) Marshal.ThrowExceptionForHR(policy.SetDefaultEndpoint(id, role));
        }
        finally { Marshal.ReleaseComObject(policy); }
    }

    [DllImport("ole32.dll")] private static extern int PropVariantClear(ref PropertyValue value);
    [ComImport, Guid("870AF99C-171D-4F9E-AF0D-E63DF40C2BC9")]
    private class PolicyConfigClient { }
    [ComImport, Guid("F8679F50-850A-41CF-9C72-430F290290C8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IPolicyConfig
    {
        [PreserveSig] int GetMixFormat();
        [PreserveSig] int GetDeviceFormat();
        [PreserveSig] int ResetDeviceFormat();
        [PreserveSig] int SetDeviceFormat();
        [PreserveSig] int GetProcessingPeriod();
        [PreserveSig] int SetProcessingPeriod();
        [PreserveSig] int GetShareMode();
        [PreserveSig] int SetShareMode();
        [PreserveSig] int GetPropertyValue();
        [PreserveSig] int SetPropertyValue();
        [PreserveSig] int SetDefaultEndpoint([MarshalAs(UnmanagedType.LPWStr)] string id, int role);
    }
}
