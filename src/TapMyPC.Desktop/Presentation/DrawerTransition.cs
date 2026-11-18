using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;

namespace TapMyPC.Desktop.Presentation;

// Apply to an overlay Grid with a backdrop followed by a right-hand sheet.
public static class DrawerTransition
{
    public static readonly DependencyProperty IsOpenProperty = DependencyProperty.RegisterAttached(
        "IsOpen", typeof(bool), typeof(DrawerTransition), new PropertyMetadata(false, Changed));
    public static void SetIsOpen(DependencyObject element, bool value) => element.SetValue(IsOpenProperty, value);
    public static bool GetIsOpen(DependencyObject element) => (bool)element.GetValue(IsOpenProperty);
    private static void Changed(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        if (d is not Grid { Children.Count: >= 2 } grid) return;
        var open = (bool)e.NewValue;
        if (!grid.IsLoaded) { Snap(grid); return; }
        var backdrop = (FrameworkElement)grid.Children[0];
        var sheet = (FrameworkElement)grid.Children[1];
        if (sheet.RenderTransform is not TranslateTransform) sheet.RenderTransform = new TranslateTransform();
        var transform = (TranslateTransform)sheet.RenderTransform;
        var wasVisible = grid.Visibility == Visibility.Visible;
        grid.Visibility = Visibility.Visible;
        grid.IsHitTestVisible = open;
        var duration = TimeSpan.FromMilliseconds(open ? 180 : 140);
        DoubleAnimation Animate(double from, double to) => new(from, to, duration) { EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut } };
        backdrop.BeginAnimation(UIElement.OpacityProperty, Animate(wasVisible ? backdrop.Opacity : 0, open ? 1 : 0));
        sheet.BeginAnimation(UIElement.OpacityProperty, Animate(wasVisible ? sheet.Opacity : 0, open ? 1 : 0));
        var slide = Animate(wasVisible ? transform.X : 40, open ? 0 : 40);
        slide.Completed += (_, _) => { if (GetIsOpen(grid) == open) Snap(grid); };
        transform.BeginAnimation(TranslateTransform.XProperty, slide);
    }
    private static void Snap(Grid grid)
    {
        if (grid.Children.Count < 2) return;
        foreach (FrameworkElement element in grid.Children)
        {
            element.BeginAnimation(UIElement.OpacityProperty, null); element.Opacity = 1;
            if (element.RenderTransform is TranslateTransform transform) { transform.BeginAnimation(TranslateTransform.XProperty, null); transform.X = 0; }
        }
        var open = GetIsOpen(grid);
        grid.Visibility = open ? Visibility.Visible : Visibility.Collapsed;
        grid.IsHitTestVisible = open;
    }
}
