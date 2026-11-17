using System.Runtime.InteropServices;

namespace TapMyPC.Windows.Interop;

internal static class NativeMethods
{
    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool LockWorkStation();
    [DllImport("powrprof.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.U1)]
    internal static extern bool SetSuspendState(
        [MarshalAs(UnmanagedType.U1)] bool hibernate, [MarshalAs(UnmanagedType.U1)] bool force, [MarshalAs(UnmanagedType.U1)] bool disableWake);
    [DllImport("powrprof.dll")]
    [return: MarshalAs(UnmanagedType.U1)] internal static extern bool IsPwrSuspendAllowed();
    [DllImport("powrprof.dll")]
    [return: MarshalAs(UnmanagedType.U1)] internal static extern bool IsPwrHibernateAllowed();
    [DllImport("user32.dll", SetLastError = true)]
    internal static extern IntPtr SendMessageTimeout(IntPtr window, uint message, UIntPtr wParam, IntPtr lParam, uint flags, uint timeout, out UIntPtr result);
    [DllImport("user32.dll", SetLastError = true)]
    internal static extern uint SendInput(uint count, Input[] inputs, int size);

    [StructLayout(LayoutKind.Sequential)]
    internal struct Input { public uint Type; public InputUnion Data; }
    [StructLayout(LayoutKind.Explicit)]
    internal struct InputUnion
    {
        [FieldOffset(0)] public KeyboardInput Keyboard;
        [FieldOffset(0)] public MouseInput Mouse;
    }
    [StructLayout(LayoutKind.Sequential)]
    internal struct KeyboardInput { public ushort Key; public ushort Scan; public uint Flags; public uint Time; public UIntPtr Extra; }
    [StructLayout(LayoutKind.Sequential)]
    internal struct MouseInput { public int X; public int Y; public uint Data; public uint Flags; public uint Time; public UIntPtr Extra; }
}
