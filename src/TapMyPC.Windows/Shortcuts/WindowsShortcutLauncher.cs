using System.Diagnostics;
using TapMyPC.Core.Shortcuts;

namespace TapMyPC.Windows.Shortcuts;

public sealed class WindowsShortcutLauncher : IShortcutLauncher
{
    public void Launch(ApprovedShortcut shortcut)
    {
        if (shortcut.Kind == ShortcutKind.App && !File.Exists(shortcut.Target))
            throw new FileNotFoundException("The approved application no longer exists.");
        // No shell command, remotely supplied path, or remotely supplied arguments.
        using var process = Process.Start(new ProcessStartInfo(shortcut.Target) { UseShellExecute = true });
    }
}
