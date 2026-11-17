using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using TapMyPC.Core.Devices;
using TapMyPC.Windows.Interop;

namespace TapMyPC.Windows.Power;

internal static class PowerControl
{
    public static void Execute(PowerAction action)
    {
        switch (action)
        {
            case PowerAction.Lock:
                if (!NativeMethods.LockWorkStation()) throw new Win32Exception(Marshal.GetLastWin32Error());
                break;
            case PowerAction.Sleep:
            case PowerAction.Hibernate:
                var allowed = action == PowerAction.Sleep ? NativeMethods.IsPwrSuspendAllowed() : NativeMethods.IsPwrHibernateAllowed();
                if (!allowed) throw new NotSupportedException("This power state is unavailable.");
                using (ShutdownPrivilege.Enable())
                    if (!NativeMethods.SetSuspendState(action == PowerAction.Hibernate, false, false)) throw new Win32Exception(Marshal.GetLastWin32Error());
                break;
            case PowerAction.Shutdown:
            case PowerAction.Restart:
                // Windows /t > 0 implies /f. Core owns countdowns; never pass /f.
                using (var process = Process.Start(new ProcessStartInfo
                {
                    FileName = Path.Combine(Environment.SystemDirectory, "shutdown.exe"),
                    Arguments = action == PowerAction.Shutdown ? "/s /t 0" : "/r /t 0",
                    UseShellExecute = false,
                    CreateNoWindow = true
                }) ?? throw new InvalidOperationException("Unable to start the Windows power request."))
                {
                    if (!process.WaitForExit(5000)) throw new InvalidOperationException("Windows power request timed out.");
                    if (process.ExitCode != 0) throw new InvalidOperationException($"Windows rejected the power request (code {process.ExitCode}).");
                }
                break;
            default: throw new ArgumentException("Unknown power action.");
        }
    }
}
