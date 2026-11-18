using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Effects;
using TapMyPC.Windows.Interop;

namespace TapMyPC.Desktop.Presentation;

// Keep the transparent shadow on its own surface so the opaque content retains text antialiasing.
public sealed class WindowShadow : IDisposable
{
    private const double Padding = 22;
    private readonly Window owner;
    private readonly Window shadow;
    private readonly Grid surface;
    private bool disposed;
    public WindowShadow(Window owner)
    {
        this.owner = owner;
        surface = new Grid { IsHitTestVisible = false };
        surface.Children.Add(new Border {
            Margin = new Thickness(Padding), CornerRadius = new CornerRadius(16), Background = Brushes.Black,
            Effect = new DropShadowEffect { BlurRadius = 20, ShadowDepth = 3, Opacity = 0.55, Color = Colors.Black }
        });
        shadow = new Window {
            Title = "TapMyPC shadow", Owner = owner, WindowStyle = WindowStyle.None, ResizeMode = ResizeMode.NoResize,
            AllowsTransparency = true, Background = Brushes.Transparent, ShowInTaskbar = false,
            ShowActivated = false, Focusable = false, IsHitTestVisible = false, Content = surface
        };
        shadow.SourceInitialized += (_, _) => WindowAppearance.MakeShadowNonInteractive(new WindowInteropHelper(shadow).Handle);
        owner.LocationChanged += Update;
        owner.SizeChanged += SizeChanged;
        owner.StateChanged += Update;
        owner.IsVisibleChanged += VisibilityChanged;
        owner.Closed += OwnerClosed;
        Sync();
    }
    private void SizeChanged(object sender, SizeChangedEventArgs e) => Sync();
    private void VisibilityChanged(object sender, DependencyPropertyChangedEventArgs e) => Sync();
    private void Update(object? sender, EventArgs e) => Sync();
    private void OwnerClosed(object? sender, EventArgs e) => Dispose();
    private void Sync()
    {
        if (disposed) return;
        if (!owner.IsVisible || owner.WindowState != WindowState.Normal || owner.ActualWidth <= 0 || owner.ActualHeight <= 0)
        { shadow.Hide(); return; }
        shadow.Left = owner.Left - Padding; shadow.Top = owner.Top - Padding;
        shadow.Width = owner.ActualWidth + Padding * 2; shadow.Height = owner.ActualHeight + Padding * 2;
        // Exclude the entire content rectangle: no shadow effect is composited over the text.
        surface.Clip = new CombinedGeometry(GeometryCombineMode.Exclude,
            new RectangleGeometry(new Rect(0, 0, shadow.Width, shadow.Height)),
            new RectangleGeometry(new Rect(Padding, Padding, owner.ActualWidth, owner.ActualHeight)));
        if (!shadow.IsVisible) shadow.Show();
    }
    public void Dispose()
    {
        if (disposed) return; disposed = true;
        owner.LocationChanged -= Update; owner.SizeChanged -= SizeChanged; owner.StateChanged -= Update;
        owner.IsVisibleChanged -= VisibilityChanged; owner.Closed -= OwnerClosed;
        shadow.Close();
    }
}
