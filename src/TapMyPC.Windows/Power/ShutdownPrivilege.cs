using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace TapMyPC.Windows.Power;

internal sealed class ShutdownPrivilege : IDisposable
{
    private readonly SafeAccessTokenHandle token;
    private TokenPrivileges previous;

    private ShutdownPrivilege(SafeAccessTokenHandle token, TokenPrivileges previous) { this.token = token; this.previous = previous; }
    public static ShutdownPrivilege Enable()
    {
        if (!OpenProcessToken(GetCurrentProcess(), 0x0020 | 0x0008, out var token)) throw new Win32Exception(Marshal.GetLastWin32Error());
        try
        {
            if (!LookupPrivilegeValue(null, "SeShutdownPrivilege", out var luid)) throw new Win32Exception(Marshal.GetLastWin32Error());
            var desired = new TokenPrivileges { Count = 1, Luid = luid, Attributes = 2 };
            if (!AdjustTokenPrivileges(token, false, ref desired, Marshal.SizeOf<TokenPrivileges>(), out var previous, out _))
                throw new Win32Exception(Marshal.GetLastWin32Error());
            var error = Marshal.GetLastWin32Error();
            if (error != 0) throw new Win32Exception(error);
            return new(token, previous);
        }
        catch { token.Dispose(); throw; }
    }
    public void Dispose()
    {
        AdjustTokenPrivileges(token, false, ref previous, Marshal.SizeOf<TokenPrivileges>(), out _, out _);
        token.Dispose();
    }
    [StructLayout(LayoutKind.Sequential)] private struct Luid { public uint Low; public int High; }
    [StructLayout(LayoutKind.Sequential)] private struct TokenPrivileges { public uint Count; public Luid Luid; public uint Attributes; }
    [DllImport("kernel32.dll")] private static extern IntPtr GetCurrentProcess();
    [DllImport("advapi32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool OpenProcessToken(IntPtr process, uint access, out SafeAccessTokenHandle token);
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool LookupPrivilegeValue(string? system, string name, out Luid luid);
    [DllImport("advapi32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool AdjustTokenPrivileges(SafeAccessTokenHandle token, [MarshalAs(UnmanagedType.Bool)] bool disableAll, ref TokenPrivileges state, int length, out TokenPrivileges previous, out int required);
}
