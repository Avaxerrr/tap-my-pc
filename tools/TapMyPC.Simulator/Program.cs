using System.Net;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using TapMyPC.Api;
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
var port = args.Length > 0 && int.TryParse(args[0], out var parsed) ? parsed : 45832;
await using var app = await ApiHost.StartAsync(IPAddress.Loopback, port, certificate, device, pairing, scheduler);
Console.WriteLine($"SIMULATED controls only. URL: {app.Urls.Single()}");
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
