using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using TapMyPC.Core.Feedback;
using TapMyPC.Desktop.Features.Settings;
using System.ComponentModel;

namespace TapMyPC.Desktop.Features.Feedback;

public partial class FeedbackWindow : Window
{
    public event Action? CancelRequested;
    private readonly AppearanceViewModel? appearance;
    public FeedbackWindow(AppearanceViewModel? appearance = null)
    {
        this.appearance = appearance;
        InitializeComponent();
        AppearanceViewModel.Apply(Resources, appearance?.Palette ?? AppearanceViewModel.Palettes[0]);
        if (appearance is not null) appearance.PropertyChanged += AppearanceChanged;
        Closed += (_, _) => { if (appearance is not null) appearance.PropertyChanged -= AppearanceChanged; };
        SourceInitialized += (_, _) => HwndSource.FromHwnd(new WindowInteropHelper(this).Handle)?.AddHook(PreventActivation);
        SizeChanged += (_, _) => Reposition();
        IsVisibleChanged += (_, _) =>
        {
            BeginAnimation(OpacityProperty, null);
            Opacity = 1;
            if (IsVisible && (appearance?.AnimationsEnabled ?? SystemParameters.ClientAreaAnimation))
                BeginAnimation(OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(160)) { EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut } });
        };
    }

    private void AppearanceChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (appearance is null) return;
        if (e.PropertyName == nameof(AppearanceViewModel.Palette)) AppearanceViewModel.Apply(Resources, appearance.Palette);
        if (e.PropertyName == nameof(AppearanceViewModel.AnimationsEnabled) && !appearance.AnimationsEnabled)
        { BeginAnimation(OpacityProperty, null); Opacity = 1; }
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
        var failed = item.Phase == ActionPhase.Failed;
        ActionIcon.Text = failed ? "\uE783" : remaining is not null ? "\uE823" : item.Title switch
        {
            "Audio output" => "\uE767",
            "Monitor brightness" => "\uE706",
            "Monitor power" => "\uE7F4",
            "Shortcut" => "\uE8A7",
            "Bluetooth" => "\uE702",
            "Media" => "\uE768",
            "Audio" => "\uE767",
            "Displays" => "\uE7F4",
            _ => "\uE73E"
        };
        PhaseLabel.Text = remaining is <= 10 ? "Starting soon" : item.Phase switch
        {
            ActionPhase.Running => "Sending", ActionPhase.Succeeded => "Done", ActionPhase.Requested => "Requested",
            ActionPhase.Scheduled => "Scheduled", ActionPhase.Canceled => "Canceled", _ => "Failed"
        };
        ActionIcon.SetResourceReference(System.Windows.Controls.TextBlock.ForegroundProperty, failed ? "ErrorText" : "AccentText");
        PhaseLabel.SetResourceReference(System.Windows.Controls.TextBlock.ForegroundProperty, failed ? "ErrorText" : "AccentText");
        IconBackground.SetResourceReference(System.Windows.Controls.Border.BackgroundProperty, failed ? "ErrorSoft" : "AccentSoft");
        FeedbackCard.SetResourceReference(System.Windows.Controls.Border.BorderBrushProperty, failed ? "ErrorBorder" : "AccentBorder");
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
