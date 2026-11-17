using System.Windows;
using TapMyPC.Core.Devices;
using TapMyPC.Core.Timers;
using TapMyPC.Desktop.Features.Settings;
using TapMyPC.Desktop.Features.Feedback;
using TapMyPC.Desktop.Tray;
using TapMyPC.Windows;
using TapMyPC.Windows.Settings;

namespace TapMyPC.Desktop;

public partial class App : Application
{
    private TrayIcon? tray;
    private Mutex? instanceMutex;
    private SettingsViewModel? settingsViewModel;
    private FeedbackPresenter? feedback;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        // Keep the original lock identity so a pre-rename host cannot run beside TapMyPC.
        instanceMutex = new Mutex(true, @"Local\PCRemote.Desktop", out var created);
        if (!created) { Shutdown(); return; }
        try
        {
            var settings = new LocalSettings();
            if (StartupRegistration.Enabled) StartupRegistration.SetEnabled(true);
            var device = new WindowsDeviceController();
            var pairing = new PairingService(settings, TimeProvider.System);
            var scheduler = new PowerScheduler(device, TimeProvider.System);
            settingsViewModel = new SettingsViewModel(device, settings, pairing, scheduler);
            feedback = new FeedbackPresenter(scheduler, () => settingsViewModel.ShowNotifications, Dispatcher);
            MainWindow = new MainWindow { DataContext = settingsViewModel };
            tray = new TrayIcon(ShowSettings, ExitAsync);
            if (e.Args.Contains("--tray")) settingsViewModel.ToggleHost.Execute(null);
            else ShowSettings();
        }
        catch (Exception ex)
        {
            MessageBox.Show($"TapMyPC could not start: {ex.Message}", "TapMyPC", MessageBoxButton.OK, MessageBoxImage.Error);
            Shutdown(1);
        }
    }

    private void ShowSettings()
    {
        MainWindow.Show(); MainWindow.WindowState = WindowState.Normal; MainWindow.Activate();
    }

    private async void ExitAsync()
    {
        try { feedback?.Dispose(); if (settingsViewModel is not null) await settingsViewModel.ShutdownAsync(); }
        finally { tray?.Dispose(); Shutdown(); }
    }

    protected override void OnExit(ExitEventArgs e)
    {
        feedback?.Dispose(); tray?.Dispose(); instanceMutex?.Dispose(); base.OnExit(e);
    }
}
