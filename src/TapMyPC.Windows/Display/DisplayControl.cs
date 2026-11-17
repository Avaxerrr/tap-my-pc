using System.ComponentModel;
using TapMyPC.Windows.Interop;

namespace TapMyPC.Windows.Display;

internal static class DisplayControl
{
    public static void TurnOff()
    {
        if (NativeMethods.SendMessageTimeout(new IntPtr(0xffff), 0x0112, new UIntPtr(0xF170), new IntPtr(2), 0x0002, 2000, out _) == IntPtr.Zero)
            throw new Win32Exception("The display-off request did not complete.");
    }
}
