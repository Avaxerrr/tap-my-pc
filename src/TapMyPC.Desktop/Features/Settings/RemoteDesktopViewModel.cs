using System.ComponentModel;
using System.Diagnostics;
using System.Globalization;
using System.Runtime.CompilerServices;
using Microsoft.Win32;
using TapMyPC.Windows.RemoteDesktop;

namespace TapMyPC.Desktop.Features.Settings;

public sealed class RemoteDesktopViewModel : INotifyPropertyChanged
{
    private RemoteDesktopServiceStatus? status;
    private bool busy;
    private bool polling;
    private bool working;
    private bool showDiagnostics;
    private bool networkAvailable;
    private string? viewer;
    private int? progressPercent;
    private string message = "";
    private string maxFps = "25";
    private bool keepWallpaper = true;

    public RemoteDesktopViewModel()
    {
        Refresh = new AsyncCommand(() => PollAsync(readSettings: true));
        ToggleDiagnostics = new RelayCommand(() =>
        {
            showDiagnostics = !showDiagnostics;
            Notify(nameof(ShowDiagnostics));
        });
        Configure = new AsyncCommand(() => RunAsync(RemoteDesktopOperation.Configure));
        UseDownloadedInstaller = new AsyncCommand(ChooseInstallerAsync);
        OpenUltraVncDownloads = new RelayCommand(OpenDownloads);
        ToggleService = new AsyncCommand(() => RunAsync(
            status?.Running == true ? RemoteDesktopOperation.Stop : RemoteDesktopOperation.Start));
        ResetPassword = new AsyncCommand(() => RunAsync(RemoteDesktopOperation.ResetPassword));
        Save = new AsyncCommand(() => RunAsync(RemoteDesktopOperation.Save));
    }

    public AsyncCommand Refresh { get; }
    public RelayCommand ToggleDiagnostics { get; }
    public AsyncCommand Configure { get; }
    public AsyncCommand UseDownloadedInstaller { get; }
    public RelayCommand OpenUltraVncDownloads { get; }
    public AsyncCommand ToggleService { get; }
    public AsyncCommand ResetPassword { get; }
    public AsyncCommand Save { get; }

    public string Status => status is null ? "Service status unavailable" : $"Service · {status.ServiceState}";
    public string DashboardStatus => status switch
    {
        not { Configured: true } => "View and control this PC from your phone",
        _ when viewer is not null => $"Connected · {viewer}",
        { Running: false } => "Service stopped",
        { HasLocalListener: false } => "Capture service unavailable",
        _ when !networkAvailable => "TapMyPC connections unavailable",
        _ => "Ready · No viewer"
    };
    public bool HasViewer => Configured && viewer is not null;
    public string DashboardAction => Configured ? "Settings" : "Set up";
    public string Diagnostics => status is { Installed: true }
        ? $"UltraVNC {status.Version ?? "version unavailable"}{Environment.NewLine}{status.Listener ?? "Listener status unavailable"}"
        : "Set up Remote Desktop to see the server version and listener status.";
    public bool Installed => status?.Installed == true;
    public bool ShowInstallerOptions => !Installed;
    public bool Configured => status?.Configured == true;
    public bool Ready => !busy;
    public bool Working => working;
    public bool ProgressIndeterminate => progressPercent is null;
    public int ProgressValue => progressPercent ?? 0;
    public string ConfigureLabel => Configured ? "Repair setup" : "Set up Remote Desktop";
    public string ToggleLabel => status?.Running == true ? "Stop" : "Start";

    public string Message { get => message; private set { message = value; Notify(); } }
    public string MaxFps { get => maxFps; set { maxFps = value; Notify(); } }
    public bool KeepWallpaper { get => keepWallpaper; set { keepWallpaper = value; Notify(); } }
    public bool ShowDiagnostics => showDiagnostics;

    public event PropertyChangedEventHandler? PropertyChanged;

    public void UpdateViewer(string? activeViewer, bool hasNetworkListener)
    {
        if (viewer == activeViewer && networkAvailable == hasNetworkListener) return;
        viewer = activeViewer;
        networkAvailable = hasNetworkListener;
        Notify(nameof(DashboardStatus));
        Notify(nameof(HasViewer));
    }

    public async Task PollAsync(bool readSettings = false)
    {
        if (polling || busy) return;
        polling = true;
        try
        {
            var observed = await RemoteDesktopSetup.ReadStatusAsync();
            if (!busy) ApplyStatus(observed, readSettings);
        }
        catch (Exception ex)
        {
            if (readSettings && !busy) Message = $"Could not check Remote Desktop. {ex.Message}";
        }
        finally { polling = false; }
    }

    private void OpenDownloads()
    {
        try
        {
            using var browser = Process.Start(new ProcessStartInfo("https://uvnc.com/downloads/ultravnc.html")
            {
                UseShellExecute = true
            });
        }
        catch (Win32Exception ex) { Message = $"Could not open the UltraVNC download page. {ex.Message}"; }
    }

    private Task ChooseInstallerAsync()
    {
        if (busy || Installed) return Task.CompletedTask;
        var picker = new OpenFileDialog
        {
            Title = "Select the official UltraVNC x64 installer",
            Filter = "Windows installer (*.exe)|*.exe",
            CheckFileExists = true,
            DereferenceLinks = false
        };
        return picker.ShowDialog(System.Windows.Application.Current.MainWindow) == true
            ? RunAsync(RemoteDesktopOperation.Configure, picker.FileName)
            : Task.CompletedTask;
    }

    private async Task RunAsync(RemoteDesktopOperation operation, string? installerPath = null)
    {
        if (busy) return;
        var settings = RemoteDesktopCaptureSettings.Default;
        if (operation == RemoteDesktopOperation.Save)
        {
            if (!int.TryParse(MaxFps, NumberStyles.Integer, CultureInfo.CurrentCulture, out var fps) || fps is < 5 or > 60)
            {
                Message = "Enter a capture limit from 5 to 60 FPS.";
                return;
            }
            settings = new(fps, KeepWallpaper);
        }

        busy = true;
        Notify(nameof(Ready));
        try
        {
            string? password = null;
            var generated = false;
            if ((operation == RemoteDesktopOperation.ResetPassword || operation == RemoteDesktopOperation.Configure && !Installed) &&
                !RemoteDesktopPasswordDialog.TryChoose(operation, out password, out generated)) return;

            SetProgress(new("Waiting for Windows administrator approval…", null));
            SetWorking(true);
            var outcome = await RemoteDesktopSetup.RunAsync(operation, settings, password,
                new Progress<RemoteDesktopSetupProgress>(update =>
                {
                    if (working) SetProgress(update);
                }), installerPath);
            SetWorking(false);
            Message = outcome.Result switch
            {
                RemoteDesktopOperationResult.Canceled => "Remote Desktop change canceled.",
                RemoteDesktopOperationResult.Failed => outcome.Error ?? "Remote Desktop change failed.",
                _ => operation switch
                {
                    RemoteDesktopOperation.Stop => "Remote Desktop stopped.",
                    RemoteDesktopOperation.Save => "Remote Desktop settings saved.",
                    RemoteDesktopOperation.ResetPassword => "Password reset. Forget the old saved password on your phone, then reconnect.",
                    _ => "Remote Desktop is ready for authorized phones."
                }
            };
            if (outcome.Result == RemoteDesktopOperationResult.Completed &&
                (outcome.GeneratedPassword ?? (generated ? password : null)) is { } generatedPassword)
                RemoteDesktopPasswordDialog.ShowGenerated(generatedPassword);
            if (outcome.Result != RemoteDesktopOperationResult.Canceled)
                ApplyStatus(await RemoteDesktopSetup.ReadStatusAsync(), readSettings: operation == RemoteDesktopOperation.Save);
        }
        catch (Exception ex) { Message = ex.Message; }
        finally
        {
            SetWorking(false);
            busy = false;
            Notify(nameof(Ready));
        }
    }

    private void ApplyStatus(RemoteDesktopServiceStatus observed, bool readSettings)
    {
        if (readSettings || status?.Installed != true)
        {
            MaxFps = observed.CaptureSettings.MaxFps.ToString(CultureInfo.CurrentCulture);
            KeepWallpaper = observed.CaptureSettings.KeepWallpaper;
        }

        if (status == observed) return;
        status = observed;
        Notify(nameof(Status));
        Notify(nameof(DashboardStatus));
        Notify(nameof(Diagnostics));
        Notify(nameof(Installed));
        Notify(nameof(ShowInstallerOptions));
        Notify(nameof(Configured));
        Notify(nameof(DashboardAction));
        Notify(nameof(HasViewer));
        Notify(nameof(ConfigureLabel));
        Notify(nameof(ToggleLabel));
    }

    private void SetProgress(RemoteDesktopSetupProgress progress)
    {
        progressPercent = progress.Percent;
        Message = progress.Percent is { } percent ? $"{progress.Message} · {percent}%" : progress.Message;
        Notify(nameof(ProgressValue));
        Notify(nameof(ProgressIndeterminate));
    }

    private void SetWorking(bool value)
    {
        if (working == value) return;
        working = value;
        Notify(nameof(Working));
    }

    private void Notify([CallerMemberName] string? property = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(property));
}
