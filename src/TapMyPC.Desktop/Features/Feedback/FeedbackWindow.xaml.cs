using System.Windows;
using System.Windows.Interop;
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
    }

    private static IntPtr PreventActivation(IntPtr hwnd, int message, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (message == 0x0021) { handled = true; return new IntPtr(3); } // WM_MOUSEACTIVATE / MA_NOACTIVATE
        return IntPtr.Zero;
    }

    public void Present(ActionNotice item, double? remaining = null)
    {
        Heading.Text = item.Title;
        Detail.Text = item.Message;
        AudioBar.Visibility = item.Audio is null ? Visibility.Collapsed : Visibility.Visible;
        AudioBar.Value = item.Audio?.Volume ?? 0;
        Countdown.Visibility = remaining is null ? Visibility.Collapsed : Visibility.Visible;
        CancelButton.Visibility = remaining is null ? Visibility.Collapsed : Visibility.Visible;
        Countdown.Text = remaining is null ? "" : $"{Math.Max(0, Math.Ceiling(remaining.Value))} seconds";
        Reposition();
    }

    private void Reposition()
    {
        Left = SystemParameters.WorkArea.Right - Width - 24;
        Top = SystemParameters.WorkArea.Bottom - Math.Max(ActualHeight, 170) - 24;
    }
    private void Cancel_Click(object sender, RoutedEventArgs e) => CancelRequested?.Invoke();
}
