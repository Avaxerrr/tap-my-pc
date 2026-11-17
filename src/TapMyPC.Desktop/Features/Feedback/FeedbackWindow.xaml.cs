using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using TapMyPC.Core.Feedback;

namespace TapMyPC.Desktop.Features.Feedback;

public partial class FeedbackWindow : Window
{
    public event Action? CancelRequested;
    public FeedbackWindow()
    {
        InitializeComponent();
        SourceInitialized += (_, _) => HwndSource.FromHwnd(new WindowInteropHelper(this).Handle)?.AddHook(PreventActivation);
        SizeChanged += (_, _) => Reposition();
        IsVisibleChanged += (_, _) =>
        {
            if (IsVisible) BeginAnimation(OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(160)));
        };
    }

    private static IntPtr PreventActivation(IntPtr hwnd, int message, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (message == 0x0021) { handled = true; return new IntPtr(3); } // WM_MOUSEACTIVATE / MA_NOACTIVATE
        return IntPtr.Zero;
    }

    public void Present(ActionNotice item, double? remaining = null)
    {
        Heading.Text = $"TapMyPC · {item.Title}";
        Detail.Text = item.Message;
        var failed = item.Phase == ActionPhase.Failed;
        ActionIcon.Text = failed ? "\uE783" : remaining is not null ? "\uE823" : item.Title switch
        {
            "Media" => "\uE768",
            "Audio" => "\uE767",
            "Displays" => "\uE7F4",
            _ => "\uE73E"
        };
        ActionIcon.Foreground = new SolidColorBrush((Color)ColorConverter.ConvertFromString(failed ? "#FFB4AB" : "#C9EFAA"));
        IconBackground.Background = new SolidColorBrush((Color)ColorConverter.ConvertFromString(failed ? "#49302E" : "#2D3D33"));
        CountdownRow.Visibility = remaining is null ? Visibility.Collapsed : Visibility.Visible;
        CountdownBar.Visibility = remaining is <= 10 ? Visibility.Visible : Visibility.Collapsed;
        CountdownBar.Value = Math.Clamp(remaining ?? 0, 0, 10);
        var duration = TimeSpan.FromSeconds(Math.Max(0, Math.Ceiling(remaining ?? 0)));
        Countdown.Text = remaining is null ? "" : remaining <= 60
            ? $"{Math.Max(0, Math.Ceiling(remaining.Value))}s"
            : $"{(int)duration.TotalHours:00}:{duration.Minutes:00}:{duration.Seconds:00}";
        if (remaining is <= 10) Detail.Text = "Power action starting soon";
        Reposition();
    }

    private void Reposition()
    {
        Left = SystemParameters.WorkArea.Right - Width - 24;
        Top = SystemParameters.WorkArea.Bottom - ActualHeight - 24;
    }
    private void Cancel_Click(object sender, RoutedEventArgs e) => CancelRequested?.Invoke();
}