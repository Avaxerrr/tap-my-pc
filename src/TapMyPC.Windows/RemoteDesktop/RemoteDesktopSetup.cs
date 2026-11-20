using System.ComponentModel;
using System.Diagnostics;
using System.IO.Compression;
using System.IO.Pipes;
using System.Management;
using System.Net;
using System.Net.NetworkInformation;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;
using System.Text.Json;
using Microsoft.Win32.SafeHandles;

namespace TapMyPC.Windows.RemoteDesktop;

public enum RemoteDesktopOperation { Configure, Start, Stop, Save, ResetPassword }
public enum RemoteDesktopOperationResult { Completed, Canceled, Failed }

public sealed record RemoteDesktopCaptureSettings(int MaxFps, bool KeepWallpaper)
{
    public static RemoteDesktopCaptureSettings Default { get; } = new(25, true);
}

public sealed record RemoteDesktopSetupProgress(string Message, int? Percent);
public sealed record RemoteDesktopSetupOutcome(RemoteDesktopOperationResult Result, string? Error = null, string? GeneratedPassword = null);

public sealed record RemoteDesktopServiceStatus(
    bool Installed, bool Running, string ServiceState, string? Version, string? Listener,
    RemoteDesktopCaptureSettings CaptureSettings, bool HasLocalListener = false, bool Configured = false);

public static class RemoteDesktopSetup
{
    private const string ServiceName = "uvnc_service";
    private static readonly string ServerPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "uvnc", "UltraVNC", "winvnc.exe");
    private static readonly string ConfigPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "UltraVNC", "ultravnc.ini");

    public static Task<RemoteDesktopServiceStatus> ReadStatusAsync() => Task.Run<RemoteDesktopServiceStatus>(() =>
    {
        using var searcher = new ManagementObjectSearcher(
            new ManagementScope(@"root\cimv2"),
            new ObjectQuery($"SELECT State, PathName FROM Win32_Service WHERE Name = '{ServiceName}'"),
            new System.Management.EnumerationOptions { Timeout = TimeSpan.FromSeconds(5) });
        using var services = searcher.Get();
        foreach (ManagementObject service in services)
        {
            using (service)
            {
                var state = service["State"] as string ?? "Unknown";
                if (!string.Equals(service["PathName"] as string, $"\"{ServerPath}\" -service",
                    StringComparison.OrdinalIgnoreCase))
                    return new(true, false, "Unrecognized service path", null, null, RemoteDesktopCaptureSettings.Default);

                var running = state == "Running";
                var version = File.Exists(ServerPath) ? FileVersionInfo.GetVersionInfo(ServerPath).FileVersion : null;
                var settings = new RemoteDesktopCaptureSettings(
                    ReadSetting("poll", "MaxFPS", 25),
                    ReadSetting("admin", "RemoveWallpaper", 0) == 0);
                var listeners = IPGlobalProperties.GetIPGlobalProperties().GetActiveTcpListeners()
                    .Where(endpoint => endpoint.Port == 5900).ToArray();
                var listener = listeners switch
                {
                    [] => "Port 5900 has no active listener",
                    [var local] when IPAddress.Loopback.Equals(local.Address) => "127.0.0.1:5900 (local only)",
                    _ => "Port 5900 has unexpected bindings"
                };
                return new(true, running, state, version, listener, settings,
                    listeners is [var active] && IPAddress.Loopback.Equals(active.Address),
                    Configured: version is not null && HasLocalConfiguration());
            }
        }
        return new(false, false, "Not installed", null, null, RemoteDesktopCaptureSettings.Default);
    });

    private static bool HasLocalConfiguration() =>
        ReadSetting("admin", "UseRegistry", -1) == 0 &&
        ReadSetting("admin", "SocketConnect", 0) == 1 &&
        ReadSetting("admin", "AllowLoopback", 0) == 1 &&
        ReadSetting("admin", "LoopbackOnly", 0) == 1 &&
        ReadSetting("admin", "PortNumber", 0) == 5900 &&
        ReadSetting("admin", "AutoPortSelect", 1) == 0 &&
        ReadSetting("admin", "HTTPConnect", 1) == 0 &&
        ReadSetting("admin", "AuthRequired", 0) == 1;

    public static string GeneratePassword() =>
        RandomNumberGenerator.GetString("ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789", 8);

    public static bool IsValidPassword(string value) =>
        value.Length is >= 1 and <= 8 && value.All(character => character is >= ' ' and <= '~');

    public static async Task<RemoteDesktopSetupOutcome> RunAsync(
        RemoteDesktopOperation operation, RemoteDesktopCaptureSettings settings,
        string? chosenPassword, IProgress<RemoteDesktopSetupProgress> progress, string? installerPath = null)
    {
        if (!Enum.IsDefined(operation)) throw new ArgumentOutOfRangeException(nameof(operation));
        if (settings.MaxFps is < 5 or > 60) throw new ArgumentOutOfRangeException(nameof(settings));
        if (chosenPassword is not null && !IsValidPassword(chosenPassword)) throw new ArgumentException("Invalid VNC password.");

        if (installerPath is not null && operation != RemoteDesktopOperation.Configure)
            throw new ArgumentException("An UltraVNC installer can only be used for setup.", nameof(installerPath));

        using var installer = installerPath is null ? null : File.OpenRead(installerPath);
        if (installer is { Length: <= 0 or > 64 * 1024 * 1024 })
            throw new ArgumentException("Choose a complete UltraVNC installer no larger than 64 MB.", nameof(installerPath));

        var pipeName = $"TapMyPC.RemoteDesktop.{Guid.NewGuid():N}";
        using var identity = WindowsIdentity.GetCurrent();
        var security = new PipeSecurity();
        var caller = identity.User ?? throw new InvalidOperationException("Windows user identity is unavailable.");
        var administrators = new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null);
        var network = new SecurityIdentifier(WellKnownSidType.NetworkSid, null);
        security.AddAccessRule(new(network, PipeAccessRights.FullControl, AccessControlType.Deny));
        security.AddAccessRule(new(caller, PipeAccessRights.FullControl, AccessControlType.Allow));
        security.AddAccessRule(new(administrators, PipeAccessRights.ReadWrite | PipeAccessRights.Synchronize, AccessControlType.Allow));
        using var pipe = NamedPipeServerStreamAcl.Create(pipeName, PipeDirection.InOut, 1, PipeTransmissionMode.Byte,
            PipeOptions.Asynchronous | PipeOptions.FirstPipeInstance, 0, 0, security);

        var assembly = typeof(RemoteDesktopSetup).Assembly;
        using var resource = assembly.GetManifestResourceStream("TapMyPC.Windows.RemoteDesktop.SetupCaptureService.ps1")
            ?? throw new InvalidOperationException("The Remote Desktop setup component is missing.");
        using var compressed = new MemoryStream();
        using (var compressor = new GZipStream(compressed, CompressionLevel.SmallestSize, leaveOpen: true))
            await resource.CopyToAsync(compressor);

        // Keep the embedded script within the Windows process command-line length limit.
        var packedScript = Convert.ToBase64String(compressed.ToArray());
        var command = $$"""
            $bytes = [Convert]::FromBase64String('{{packedScript}}')
            $stream = [IO.Compression.GZipStream]::new([IO.MemoryStream]::new($bytes), [IO.Compression.CompressionMode]::Decompress)
            $reader = [IO.StreamReader]::new($stream)
            try { $script = $reader.ReadToEnd() } finally { $reader.Dispose() }
            & ([scriptblock]::Create($script)) -Operation {{operation}} -MaxFps {{settings.MaxFps}} -KeepWallpaper {{PowerShellBoolean(settings.KeepWallpaper)}} -PipeName '{{pipeName}}' -ParentProcessId {{Environment.ProcessId}}
            exit $LASTEXITCODE
            """;
        var shell = Path.Combine(Environment.SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe");
        var launch = new ProcessStartInfo(shell)
        {
            UseShellExecute = true,
            Verb = "runas",
            WindowStyle = ProcessWindowStyle.Hidden
        };
        launch.ArgumentList.Add("-NoProfile");
        launch.ArgumentList.Add("-EncodedCommand");
        launch.ArgumentList.Add(Convert.ToBase64String(Encoding.Unicode.GetBytes(command)));

        try
        {
            using var process = Process.Start(launch)
                ?? throw new InvalidOperationException("Windows could not start Remote Desktop setup.");
            var exited = process.WaitForExitAsync();
            using var startTimeout = new CancellationTokenSource(TimeSpan.FromSeconds(25));
            var connected = pipe.WaitForConnectionAsync(startTimeout.Token);
            if (await Task.WhenAny(connected, exited) == exited && !connected.IsCompletedSuccessfully)
            {
                await startTimeout.CancelAsync();
                try { await connected; }
                catch (OperationCanceledException) { }
                return new(RemoteDesktopOperationResult.Failed, "The Remote Desktop setup process closed before it could report progress.");
            }
            await connected;
            if (!GetNamedPipeClientProcessId(pipe.SafePipeHandle, out var clientProcessId) || clientProcessId != process.Id)
                throw new IOException("Could not verify the Windows setup process.");

            using var writer = new StreamWriter(pipe, new UTF8Encoding(false), leaveOpen: true) { AutoFlush = true };
            using var reader = new StreamReader(pipe, Encoding.UTF8, detectEncodingFromByteOrderMarks: false, leaveOpen: true);
            await writer.WriteLineAsync(chosenPassword ?? "");
            await writer.WriteLineAsync(installer is null ? "download" : "local");

            string? error = null;
            string? generatedPassword = null;
            while (await reader.ReadLineAsync() is { } line)
            {
                using var payload = JsonDocument.Parse(line);
                var message = payload.RootElement;
                if (message.TryGetProperty("progress", out var stage))
                {
                    int? percent = message.TryGetProperty("percent", out var fraction) && fraction.TryGetInt32(out var value)
                        ? value : null;
                    progress.Report(new(stage.GetString() ?? "", percent));
                }
                if (message.TryGetProperty("installerRequested", out _))
                {
                    if (installer is null) throw new IOException("Windows setup requested an installer that was not selected.");
                    await SendInstallerAsync(installer, writer);
                }
                if (message.TryGetProperty("error", out var detail)) error = detail.GetString();
                if (message.TryGetProperty("password", out var secret)) generatedPassword = secret.GetString();
            }
            await exited;
            return process.ExitCode == 0
                ? new(RemoteDesktopOperationResult.Completed, GeneratedPassword: generatedPassword)
                : new(RemoteDesktopOperationResult.Failed, error ?? "Windows Remote Desktop setup did not finish.");
        }
        catch (Win32Exception ex) when (ex.NativeErrorCode == 1223)
        {
            return new(RemoteDesktopOperationResult.Canceled);
        }
    }

    // Send only the selected file's bytes. The elevated process never opens a user-supplied path.
    private static async Task SendInstallerAsync(Stream installer, StreamWriter writer)
    {
        var buffer = new byte[48 * 1024];
        int count;
        while ((count = await installer.ReadAsync(buffer)) != 0)
            await writer.WriteLineAsync(Convert.ToBase64String(buffer, 0, count));
        await writer.WriteLineAsync();
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetNamedPipeClientProcessId(SafePipeHandle pipe, out uint processId);

    private static string PowerShellBoolean(bool value) => value ? "$true" : "$false";

    private static int ReadSetting(string section, string key, int fallback) =>
        (int)GetPrivateProfileInt(section, key, fallback, ConfigPath);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern uint GetPrivateProfileInt(string section, string key, int fallback, string fileName);
}
