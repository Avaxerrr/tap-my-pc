using System.ComponentModel;
using System.Runtime.InteropServices;
using TapMyPC.Core.Devices;
using TapMyPC.Windows.Interop;

namespace TapMyPC.Windows.Media;

internal static class MediaControl
{
    public static void Send(MediaAction action)
    {
        ushort key = action switch { MediaAction.PlayPause => 0xB3, MediaAction.Next => 0xB0, MediaAction.Previous => 0xB1, _ => throw new ArgumentException("Unknown media command.") };
        SendKey(key);
    }

    internal static void SendKey(ushort key)
    {
        var inputs = new[]
        {
            new NativeMethods.Input { Type = 1, Data = new() { Keyboard = new() { Key = key } } },
            new NativeMethods.Input { Type = 1, Data = new() { Keyboard = new() { Key = key, Flags = 2 } } }
        };
        if (NativeMethods.SendInput(2, inputs, Marshal.SizeOf<NativeMethods.Input>()) != 2)
            throw new Win32Exception("Windows could not deliver the media/volume key. An elevated application may block it.");
    }
}
