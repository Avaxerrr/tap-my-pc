using Forms = System.Windows.Forms;

namespace TapMyPC.Desktop.Tray;

public sealed class TrayIcon : IDisposable
{
    private readonly Forms.NotifyIcon icon;
    private readonly Forms.ContextMenuStrip menu = new();
    private bool disposed;
    public TrayIcon(Action showSettings, Action exit)
    {
        menu.Items.Add("Settings", null, (_, _) => showSettings());
        menu.Items.Add("Exit (cancels timers)", null, (_, _) => exit());
        icon = new Forms.NotifyIcon
        {
            Text = "TapMyPC",
            Icon = System.Drawing.SystemIcons.Application,
            ContextMenuStrip = menu,
            Visible = true
        };
        icon.DoubleClick += (_, _) => showSettings();
    }
    public void Dispose() { if (disposed) return; disposed = true; icon.Visible = false; icon.Dispose(); menu.Dispose(); }
}
