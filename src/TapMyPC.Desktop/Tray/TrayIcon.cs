using System.ComponentModel;
using System.Drawing;
using TapMyPC.Desktop.Features.Settings;
using Forms = System.Windows.Forms;

namespace TapMyPC.Desktop.Tray;

public sealed class TrayIcon : IDisposable
{
    private readonly Forms.NotifyIcon icon;
    private readonly Forms.ContextMenuStrip menu = new();
    private readonly Icon brandIcon;
    private readonly AppearanceViewModel appearance;
    private readonly Font menuFont = new("Segoe UI", 10);
    private bool disposed;
    public TrayIcon(Action showSettings, Action exit, AppearanceViewModel appearance)
    {
        this.appearance = appearance;
        using (var stream = System.Windows.Application.GetResourceStream(new Uri("pack://application:,,,/TapMyPC;component/Assets/TapMyPC.ico")).Stream)
        using (var loaded = new Icon(stream)) brandIcon = (Icon)loaded.Clone();
        menu.ShowImageMargin = false;
        menu.BackColor = Color.FromArgb(22, 24, 29);
        menu.ForeColor = Color.FromArgb(245, 245, 247);
        menu.Font = menuFont;
        menu.Padding = new Forms.Padding(6);
        menu.Items.Add(new Forms.ToolStripMenuItem("TapMyPC") { Enabled = false });
        menu.Items.Add("Open TapMyPC", null, (_, _) => showSettings());
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add("Exit (cancels timers)", null, (_, _) => exit());
        foreach (Forms.ToolStripItem item in menu.Items) item.Padding = new Forms.Padding(10, 7, 10, 7);
        UpdateTheme();
        appearance.PropertyChanged += AppearanceChanged;
        icon = new Forms.NotifyIcon { Text = "TapMyPC", Icon = brandIcon, ContextMenuStrip = menu, Visible = true };
        icon.DoubleClick += (_, _) => showSettings();
    }
    private void AppearanceChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(AppearanceViewModel.Palette)) UpdateTheme();
    }
    private void UpdateTheme()
    {
        menu.Renderer = new TrayMenuRenderer(appearance.Palette);
        menu.Invalidate();
    }
    public void Dispose()
    {
        if (disposed) return; disposed = true;
        appearance.PropertyChanged -= AppearanceChanged;
        icon.Visible = false; icon.Dispose(); menu.Dispose(); brandIcon.Dispose(); menuFont.Dispose();
    }

    private sealed class TrayMenuRenderer(AccentPalette palette) : Forms.ToolStripProfessionalRenderer
    {
        protected override void OnRenderMenuItemBackground(Forms.ToolStripItemRenderEventArgs e)
        {
            using var brush = new SolidBrush(ColorTranslator.FromHtml(e.Item.Selected ? palette.Soft : "#16181D"));
            e.Graphics.FillRectangle(brush, new Rectangle(Point.Empty, e.Item.Size));
        }
        protected override void OnRenderItemText(Forms.ToolStripItemTextRenderEventArgs e)
        {
            e.TextColor = ColorTranslator.FromHtml(!e.Item.Enabled ? "#98989D" : e.Item.Selected ? palette.Text : "#F5F5F7");
            base.OnRenderItemText(e);
        }
        protected override void OnRenderToolStripBorder(Forms.ToolStripRenderEventArgs e)
        {
            using var pen = new Pen(Color.FromArgb(52, 57, 70));
            e.Graphics.DrawRectangle(pen, 0, 0, e.ToolStrip.Width - 1, e.ToolStrip.Height - 1);
        }
        protected override void OnRenderSeparator(Forms.ToolStripSeparatorRenderEventArgs e)
        {
            using var pen = new Pen(Color.FromArgb(52, 57, 70));
            e.Graphics.DrawLine(pen, 8, e.Item.Height / 2, e.Item.Width - 8, e.Item.Height / 2);
        }
    }
}
