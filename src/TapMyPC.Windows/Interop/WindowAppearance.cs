using System.Runtime.InteropServices;

namespace TapMyPC.Windows.Interop;

public static class WindowAppearance
{
    // A layered shadow must never intercept input or activate when clicked.
    public static void MakeShadowNonInteractive(nint handle)
    {
        const int extendedStyle = -20;
        const long transparent = 0x20, toolWindow = 0x80, noActivate = 0x08000000;
        SetWindowLongPtr(handle, extendedStyle, new nint(GetWindowLongPtr(handle, extendedStyle).ToInt64() | transparent | toolWindow | noActivate));
    }
    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
    private static extern nint GetWindowLongPtr(nint handle, int index);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")]
    private static extern nint SetWindowLongPtr(nint handle, int index, nint value);
}
