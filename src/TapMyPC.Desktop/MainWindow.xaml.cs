using System.ComponentModel;
using System.Windows;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Threading;
using TapMyPC.Desktop.Features.Settings;
using TapMyPC.Desktop.Presentation;
using System.Windows.Controls;
using System.Windows.Media.Animation;

namespace TapMyPC.Desktop;

public partial class MainWindow : Window
{
    private IInputElement? returnFocus;
    private bool switchingDrawer;

    private WindowShadow? shadow;
    private bool connectionPulsing;
    public MainWindow()
    {
        InitializeComponent();
        SizeChanged += (_, _) => UpdateDashboardLayout();
        IsVisibleChanged += (_, _) => UpdateConnectionPulse();
        StateChanged += (_, _) => UpdateConnectionPulse();
        SourceInitialized += (_, _) => shadow = new WindowShadow(this);
        Closed += (_, _) => shadow?.Dispose();
    }

    private void UpdateDashboardLayout()
    {
        var wide = ActualWidth >= 1120;
        Dashboard.ColumnDefinitions[0].Width = new GridLength(wide ? 1.4 : 1, GridUnitType.Star);
        Dashboard.ColumnDefinitions[1].Width = new GridLength(wide ? 24 : 0);
        Dashboard.ColumnDefinitions[2].Width = wide ? new GridLength(1, GridUnitType.Star) : new GridLength(0);
        Grid.SetColumn(Preferences, wide ? 2 : 0);
        Grid.SetRow(Preferences, wide ? 0 : 3);
        Grid.SetRowSpan(Preferences, wide ? 3 : 1);
    }

    private ToggleButton[] DrawerToggles => [PairDrawerToggle, ActivityDrawerToggle, SettingsDrawerToggle];

    // Drawer state and keyboard navigation are presentation-only; commands stay in the view model.
    private void Drawer_Checked(object sender, RoutedEventArgs e)
    {
        if (switchingDrawer || sender is not ToggleButton selected) return;
        switchingDrawer = true;
        try
        {
            returnFocus ??= Keyboard.FocusedElement;
            foreach (var toggle in DrawerToggles)
                if (toggle != selected) toggle.IsChecked = false;
        }
        finally { switchingDrawer = false; }
        var panel = selected == PairDrawerToggle ? PairPanel : selected == ActivityDrawerToggle ? ActivityPanel : SettingsPanel;
        Dispatcher.BeginInvoke(DispatcherPriority.Input, new Action(() =>
        {
            if (selected.IsChecked != true) return;
            panel.Focus();
            panel.MoveFocus(new TraversalRequest(FocusNavigationDirection.First));
        }));
    }

    private void Drawer_Unchecked(object sender, RoutedEventArgs e)
    {
        if (switchingDrawer) return;
        Dispatcher.BeginInvoke(DispatcherPriority.Input, new Action(() =>
        {
            if (DrawerToggles.Any(toggle => toggle.IsChecked == true)) return;
            if (returnFocus is UIElement { IsVisible: true, IsEnabled: true } element) element.Focus();
            else PairAction.Focus();
            returnFocus = null;
        }));
    }

    private void CloseDrawers()
    {
        foreach (var toggle in DrawerToggles) toggle.IsChecked = false;
    }

    private void Backdrop_Click(object sender, MouseButtonEventArgs e)
    {
        CloseDrawers();
        e.Handled = true;
    }

    private void Window_PreviewKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key != Key.Escape || !DrawerToggles.Any(toggle => toggle.IsChecked == true)) return;
        // Let an open network dropdown consume Escape before dismissing its panel.
        if (Keyboard.FocusedElement is System.Windows.Controls.ComboBox { IsDropDownOpen: true }) return;
        CloseDrawers();
        e.Handled = true;
    }

    private void Window_DataContextChanged(object sender, DependencyPropertyChangedEventArgs e)
    {
        if (e.OldValue is SettingsViewModel previous)
        {
            previous.PropertyChanged -= SettingsChanged;
            previous.Appearance.PropertyChanged -= AppearanceChanged;
        }
        if (e.NewValue is SettingsViewModel current)
        {
            current.PropertyChanged += SettingsChanged;
            current.Appearance.PropertyChanged += AppearanceChanged;
            AppearanceViewModel.Apply(Resources, current.Appearance.Palette);
            if (current.HasPairingQr) PairDrawerToggle.IsChecked = true;
        }
        UpdateConnectionPulse();
    }

    private void UpdateConnectionPulse()
    {
        var active = DataContext is SettingsViewModel { HasConnectedClients: true };
        var animate = active && DataContext is SettingsViewModel vm && vm.Appearance.AnimationsEnabled
            && IsVisible && WindowState != WindowState.Minimized;
        if (animate == connectionPulsing)
        {
            if (!animate) ConnectionHalo.Opacity = active ? 0.18 : 0;
            return;
        }
        connectionPulsing = animate;
        ConnectionHalo.BeginAnimation(OpacityProperty, null);
        if (animate)
            ConnectionHalo.BeginAnimation(OpacityProperty, new DoubleAnimation(0.12, 0.45, TimeSpan.FromMilliseconds(1200))
            { AutoReverse = true, RepeatBehavior = RepeatBehavior.Forever, EasingFunction = new SineEase() });
        else ConnectionHalo.Opacity = active ? 0.18 : 0;
    }

    private void AppearanceChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(AppearanceViewModel.Palette) && sender is AppearanceViewModel appearance)
            AppearanceViewModel.Apply(Resources, appearance.Palette);
        UpdateConnectionPulse();
    }

    private void SettingsChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(SettingsViewModel.HasConnectedClients)) UpdateConnectionPulse();
        // First-time setup generates its QR automatically; keep it discoverable in the new layout.
        if (e.PropertyName == nameof(SettingsViewModel.HasPairingQr) && DataContext is SettingsViewModel { HasPairingQr: true })
            PairDrawerToggle.IsChecked = true;
    }

    private void Minimize_Click(object sender, RoutedEventArgs e) => SystemCommands.MinimizeWindow(this);
    private void Maximize_Click(object sender, RoutedEventArgs e)
    {
        if (WindowState == WindowState.Maximized) SystemCommands.RestoreWindow(this);
        else SystemCommands.MaximizeWindow(this);
    }
    private void Hide_Click(object sender, RoutedEventArgs e) => Close();
    protected override void OnClosing(CancelEventArgs e)
    {
        e.Cancel = true;
        CloseDrawers();
        Hide();
    }
}
