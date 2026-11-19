using System.ComponentModel;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using TapMyPC.Desktop.Features.Settings;
using Forms = System.Windows.Forms;

namespace TapMyPC.Desktop.Tray;

public sealed class TrayIcon : IDisposable
{
    private readonly Forms.NotifyIcon icon;
    private readonly Forms.ContextMenuStrip menu = new();
    private readonly Icon brandIcon;
    private readonly AppearanceViewModel appearance;
    private readonly TrayMenuFont menuFont = new();
    private bool disposed;
    public TrayIcon(Action showSettings, Action exit, AppearanceViewModel appearance)
    {
        this.appearance = appearance;
        using (var stream = System.Windows.Application.GetResourceStream(new Uri("pack://application:,,,/TapMyPC;component/Assets/TapMyPC.ico")).Stream)
        using (var loaded = new Icon(stream)) brandIcon = (Icon)loaded.Clone();
        menu.ShowImageMargin = false;
        menu.Font = menuFont.Font;
        menu.Padding = new Forms.Padding(4);
        menu.AutoSize = false;
        menu.Items.Add(new TrayMenuItem("TapMyPC") { Enabled = false });
        var openItem = new TrayMenuItem("Open TapMyPC");
        openItem.Click += (_, _) => showSettings();
        menu.Items.Add(openItem);
        menu.Items.Add(new Forms.ToolStripSeparator());
        var exitItem = new TrayMenuItem("Exit (cancels timers)");
        exitItem.Click += (_, _) => exit();
        menu.Items.Add(exitItem);
        menu.Opening += (_, _) => LayoutMenu();
        menu.DpiChangedAfterParent += (_, _) => LayoutMenu();
        LayoutMenu();
        menu.SizeChanged += UpdateMenuShape;
        menu.HandleCreated += UpdateMenuShape;
        menu.DpiChangedAfterParent += UpdateMenuShape;
        UpdateTheme();
        appearance.PropertyChanged += AppearanceChanged;
        icon = new Forms.NotifyIcon { Text = "TapMyPC", Icon = brandIcon, ContextMenuStrip = menu, Visible = true };
        icon.DoubleClick += (_, _) => showSettings();
    }
    private void LayoutMenu()
    {
        // ToolStrip's built-in text measurement uses GDI, which cannot see our private font.
        // Size the rows and popup using the same GDI+ metrics as our renderer.
        var dpi = menu.DeviceDpi;
        var gap = Math.Max(4, 4 * dpi / 96);
        menu.Padding = new Forms.Padding(gap);
        var width = menu.Items.OfType<TrayMenuItem>().Max(item => item.GetPreferredSize(Size.Empty).Width);
        var height = gap * 2;
        foreach (Forms.ToolStripItem item in menu.Items)
        {
            item.AutoSize = false;
            item.Margin = Forms.Padding.Empty;
            item.Padding = Forms.Padding.Empty;
            var rowHeight = item is TrayMenuItem row ? row.GetPreferredSize(Size.Empty).Height : 6 * dpi / 96;
            item.Size = new Size(width, rowHeight);
            height += rowHeight;
        }
        menu.Size = new Size(width + gap * 2, height);
    }
    private void UpdateMenuShape(object? sender, EventArgs e)
    {
        if (menu.Width < 2 || menu.Height < 2) return;
        using var path = Rounded(new RectangleF(0, 0, menu.Width, menu.Height), 8 * menu.DeviceDpi / 96f);
        var previous = menu.Region;
        menu.Region = new Region(path);
        previous?.Dispose();
    }
    private void AppearanceChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName is nameof(AppearanceViewModel.Theme) or nameof(AppearanceViewModel.Accent)) UpdateTheme();
    }
    private void UpdateTheme()
    {
        var theme = appearance.ThemeColors;
        menu.BackColor = ColorTranslator.FromHtml(theme.Card);
        menu.ForeColor = ColorTranslator.FromHtml(theme.Text);
        menu.Renderer = new TrayMenuRenderer(theme, appearance.AccentColors);
        menu.Invalidate();
    }
    public void Dispose()
    {
        if (disposed) return; disposed = true;
        appearance.PropertyChanged -= AppearanceChanged;
        icon.Visible = false; icon.Dispose(); menu.Dispose(); brandIcon.Dispose(); menuFont.Dispose();
    }
    private static GraphicsPath Rounded(RectangleF bounds, float radius)
    {
        var path = new GraphicsPath();
        var diameter = Math.Min(radius * 2, Math.Min(bounds.Width, bounds.Height));
        path.AddArc(bounds.Left, bounds.Top, diameter, diameter, 180, 90);
        path.AddArc(bounds.Right - diameter, bounds.Top, diameter, diameter, 270, 90);
        path.AddArc(bounds.Right - diameter, bounds.Bottom - diameter, diameter, diameter, 0, 90);
        path.AddArc(bounds.Left, bounds.Bottom - diameter, diameter, diameter, 90, 90);
        path.CloseFigure();
        return path;
    }
    private sealed class TrayMenuItem(string text) : Forms.ToolStripMenuItem(text)
    {
        public override Size GetPreferredSize(Size constrainingSize)
        {
            var dpi = Owner?.DeviceDpi ?? 96;
            using var bitmap = new Bitmap(1, 1);
            bitmap.SetResolution(dpi, dpi);
            using var graphics = Graphics.FromImage(bitmap);
            // Measure with the same GDI+ font used for painting, avoiding GDI font fallback.
            var measured = graphics.MeasureString(Text, Font);
            return new Size(
                (int)Math.Ceiling(measured.Width) + 20 * dpi / 96,
                (int)Math.Ceiling(Font.GetHeight(graphics)) + (Enabled ? 10 : 6) * dpi / 96);
        }
    }
    private sealed class TrayMenuRenderer(DesktopTheme theme, AccentPalette palette) : Forms.ToolStripProfessionalRenderer
    {
        protected override void OnRenderToolStripBackground(Forms.ToolStripRenderEventArgs e)
        {
            using var brush = new SolidBrush(e.ToolStrip.BackColor);
            e.Graphics.FillRectangle(brush, e.AffectedBounds);
        }

        protected override void OnRenderMenuItemBackground(Forms.ToolStripItemRenderEventArgs e)
        {
            if (!e.Item.Selected || !e.Item.Enabled) return;
            var state = e.Graphics.Save();
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            var inset = 2 * (e.ToolStrip?.DeviceDpi ?? 96) / 96f;
            using var shape = Rounded(new RectangleF(inset, inset, e.Item.Width - inset * 2, e.Item.Height - inset * 2), 5 * (e.ToolStrip?.DeviceDpi ?? 96) / 96f);
            using var brush = new SolidBrush(ColorTranslator.FromHtml(palette.Soft));
            e.Graphics.FillPath(brush, shape);
            e.Graphics.Restore(state);
        }
        protected override void OnRenderItemText(Forms.ToolStripItemTextRenderEventArgs e)
        {
            var state = e.Graphics.Save();
            e.Graphics.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
            var inset = 10 * (e.ToolStrip?.DeviceDpi ?? 96) / 96f;
            using var brush = new SolidBrush(ColorTranslator.FromHtml(!e.Item.Enabled ? theme.Secondary : e.Item.Selected ? palette.Text : theme.Text));
            using var format = new StringFormat {
                Alignment = StringAlignment.Near, LineAlignment = StringAlignment.Center,
                FormatFlags = StringFormatFlags.NoWrap, Trimming = StringTrimming.EllipsisCharacter
            };
            e.Graphics.DrawString(e.Text, e.TextFont ?? e.Item.Font, brush, new RectangleF(inset, 0, e.Item.Width - inset * 2, e.Item.Height), format);
            e.Graphics.Restore(state);
        }
        protected override void OnRenderToolStripBorder(Forms.ToolStripRenderEventArgs e)
        {
            var state = e.Graphics.Save();
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            using var shape = Rounded(new RectangleF(0.5f, 0.5f, e.ToolStrip.Width - 1, e.ToolStrip.Height - 1), 8 * e.ToolStrip.DeviceDpi / 96f);
            using var pen = new Pen(ColorTranslator.FromHtml(theme.ControlBorder));
            e.Graphics.DrawPath(pen, shape);
            e.Graphics.Restore(state);
        }
        protected override void OnRenderSeparator(Forms.ToolStripSeparatorRenderEventArgs e)
        {
            using var pen = new Pen(ColorTranslator.FromHtml(theme.ControlBorder));
            e.Graphics.DrawLine(pen, 8, e.Item.Height / 2, e.Item.Width - 8, e.Item.Height / 2);
        }
    }
}
