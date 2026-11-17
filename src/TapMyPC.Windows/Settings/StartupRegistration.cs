using Microsoft.Win32;

namespace TapMyPC.Windows.Settings;

public static class StartupRegistration
{
    private const string KeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    public static bool Enabled
    {
        get
        {
            using var key = Registry.CurrentUser.OpenSubKey(KeyPath);
            return key?.GetValue("TapMyPC") is string || key?.GetValue("PCRemote") is string;
        }
    }
    public static void SetEnabled(bool enabled)
    {
        using var key = Registry.CurrentUser.CreateSubKey(KeyPath);
        if (enabled)
        {
            var executable = Environment.ProcessPath ?? throw new InvalidOperationException("Executable path is unavailable.");
            key.SetValue("TapMyPC", $"\"{executable}\" --tray");
        }
        else key.DeleteValue("TapMyPC", false);
        // Remove the old entry only after the requested new state was saved successfully.
        key.DeleteValue("PCRemote", false);
    }
}
