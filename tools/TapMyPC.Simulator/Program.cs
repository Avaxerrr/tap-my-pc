using System.Net;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using TapMyPC.Api;
using TapMyPC.Core.Bluetooth;
using TapMyPC.Core.Audio;
using TapMyPC.Core.Display;
using TapMyPC.Core.Shortcuts;
using TapMyPC.Core.Devices;
using TapMyPC.Core.Timers;
using Microsoft.Extensions.Hosting;

// This executable deliberately has no reference to TapMyPC.Windows. All controls are simulated.
using var rsa = RSA.Create(2048);
using var generated = new CertificateRequest("CN=TapMyPC-Simulator", rsa, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1)
    .CreateSelfSigned(DateTimeOffset.UtcNow.AddMinutes(-1), DateTimeOffset.UtcNow.AddHours(4));
using var certificate = X509CertificateLoader.LoadPkcs12(generated.Export(X509ContentType.Pfx), null, X509KeyStorageFlags.UserKeySet);
var pairing = new PairingService(new MemoryStore(), TimeProvider.System);
var device = new SimulatedDevice();
using var scheduler = new PowerScheduler(device, TimeProvider.System);
var hardware = new SimulatedHardware();
var shortcuts = new ShortcutCatalog(new SimulatedShortcutStore(), new SimulatedShortcutLauncher(), scheduler.Activity);
shortcuts.Add("Example website", ShortcutKind.Website, "https://example.com");
shortcuts.Add("Example app", ShortcutKind.App, Path.Combine(Path.GetTempPath(), "simulated.exe"));
var port = args.Length > 0 && int.TryParse(args[0], out var parsed) ? parsed : 45832;
await using var app = await ApiHost.StartAsync(IPAddress.Loopback, port, certificate, device, pairing, scheduler, bluetooth: new SimulatedBluetooth(), outputs: hardware, monitors: hardware, shortcuts: shortcuts);
Console.WriteLine($"SIMULATED controls only. URL: {app.Urls.Single()}");
Console.WriteLine($"Certificate SHA-256: {certificate.GetCertHashString(HashAlgorithmName.SHA256)}");
Console.WriteLine($"Pairing code: {pairing.OpenPairing().Code} (one use; five minutes)");
await app.WaitForShutdownAsync();

sealed class MemoryStore : IDeviceStore
{
    private IReadOnlyList<PairedDevice> devices = [];
    public IReadOnlyList<PairedDevice> Load() => devices;
    public void Save(IReadOnlyList<PairedDevice> value) => devices = value.ToArray();
}
sealed class SimulatedDevice : IDeviceController
{
    private AudioState audio = new(35, false);
    public DeviceCapabilities Capabilities => new(true, true, true, true, true);
    public AudioState ReadAudio() => audio;
    public void SetVolume(int percent) => audio = audio with { Volume = percent };
    public void SetMute(bool muted) => audio = audio with { Muted = muted };
    public void StepVolume(VolumeDirection direction) => SetVolume(Math.Clamp(audio.Volume + (direction == VolumeDirection.Up ? 2 : -2), 0, 100));
    public void SendMedia(MediaAction action) => Console.WriteLine($"Simulated media: {action}");
    public void TurnOffDisplays() => Console.WriteLine("Simulated monitors off");
    public void ExecutePower(PowerAction action) => Console.WriteLine($"Simulated power: {action}");
}

sealed class SimulatedBluetooth : IBluetoothController
{
    private bool enabled = true;
    public Task<BluetoothStatus> ReadAsync() => Task.FromResult(new BluetoothStatus(true, true, enabled ? BluetoothRadioState.On : BluetoothRadioState.Off));
    public Task SetEnabledAsync(bool value) { enabled = value; return Task.CompletedTask; }
}

sealed class SimulatedHardware : IAudioOutputController, IMonitorController
{
    private string selected = "speakers";
    private readonly List<MonitorStatus> monitors =
    [
        new("monitor-1", "Main display", 60, true, true, true, "Simulated DDC/CI display."),
        new("monitor-2", "Unsupported display", null, false, false, null, "This display does not support remote controls.")
    ];
    public IReadOnlyList<AudioOutput> List() => new[] { "speakers", "headphones" }.Select(id => new AudioOutput(id, id == "speakers" ? "Speakers" : "Headphones", selected == id)).ToArray();
    public void Select(string id) { selected = id; Console.WriteLine($"Simulated audio output: {id}"); }
    public Task<IReadOnlyList<MonitorStatus>> ListAsync() => Task.FromResult<IReadOnlyList<MonitorStatus>>(monitors.ToArray());
    public Task SetBrightnessAsync(string id, int brightness)
    {
        var index = monitors.FindIndex(m => m.Id == id);
        monitors[index] = monitors[index] with { Brightness = brightness };
        return Task.CompletedTask;
    }
    public Task SetPowerAsync(string id, bool enabled)
    {
        var index = monitors.FindIndex(m => m.Id == id);
        monitors[index] = monitors[index] with { IsOn = enabled };
        return Task.CompletedTask;
    }
}
sealed class SimulatedShortcutStore : IShortcutStore
{
    private IReadOnlyList<ApprovedShortcut> items = [];
    public IReadOnlyList<ApprovedShortcut> LoadShortcuts() => items;
    public void SaveShortcuts(IReadOnlyList<ApprovedShortcut> value) => items = value.ToArray();
}
sealed class SimulatedShortcutLauncher : IShortcutLauncher
{
    public void Launch(ApprovedShortcut shortcut) => Console.WriteLine($"Simulated shortcut: {shortcut.Name}");
}
