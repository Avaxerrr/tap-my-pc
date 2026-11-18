using System.Text.Json;
using TapMyPC.Core.Devices;
using TapMyPC.Core.Shortcuts;

namespace TapMyPC.Windows.Settings;

public record AppearanceSettings(string Accent = "Blue");

public record HostIdentity(string CertificateThumbprint);
public record HostSettings(string Address = "auto", int Port = 45831, bool ShowNotifications = true, int Version = 3, bool ConnectionsEnabled = true);

public sealed class LocalSettings(string? directoryPath = null, string? legacyDirectoryPath = null) : IDeviceStore, IShortcutStore
{
    public string DirectoryPath { get; } = directoryPath ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "TapMyPC");
    private readonly string? legacyDirectory = legacyDirectoryPath ?? (directoryPath is null
        ? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "PCRemote") : null);
    public HostSettings ReadHost()
    {
        var path = ReadPath("host.json");
        if (!File.Exists(path)) return new();
        var json = File.ReadAllText(path);
        using var document = JsonDocument.Parse(json);
        var settings = JsonSerializer.Deserialize<HostSettings>(json) ?? new();
        // The original UI persisted an address without a mode. Migrate it to automatic selection once.
        return document.RootElement.TryGetProperty("Version", out _) ? settings : settings with { Address = "auto" };
    }
    public AppearanceSettings ReadAppearance() => Read<AppearanceSettings>("appearance.json") ?? new();
    public void SaveAppearance(AppearanceSettings appearance) => Write("appearance.json", appearance);

    public HostIdentity? ReadIdentity() => Read<HostIdentity>("identity.json");
    public void SaveIdentity(HostIdentity identity) => Write("identity.json", identity);
    public void SaveHost(HostSettings settings) => Write("host.json", settings);
    public IReadOnlyList<PairedDevice> Load() => Read<List<PairedDevice>>("devices.json") ?? [];
    public void Save(IReadOnlyList<PairedDevice> devices) => Write("devices.json", devices);

    public IReadOnlyList<ApprovedShortcut> LoadShortcuts() => Read<List<ApprovedShortcut>>("shortcuts.json") ?? [];
    public void SaveShortcuts(IReadOnlyList<ApprovedShortcut> shortcuts) => Write("shortcuts.json", shortcuts);

    private T? Read<T>(string name)
    {
        var path = ReadPath(name);
        return File.Exists(path) ? JsonSerializer.Deserialize<T>(File.ReadAllText(path)) : default;
    }
    private string ReadPath(string name)
    {
        var current = Path.Combine(DirectoryPath, name);
        if (File.Exists(current) || legacyDirectory is null) return current;
        return Path.Combine(legacyDirectory, name);
    }
    private void Write<T>(string name, T value)
    {
        Directory.CreateDirectory(DirectoryPath);
        var path = Path.Combine(DirectoryPath, name);
        var temporary = path + ".tmp";
        File.WriteAllText(temporary, JsonSerializer.Serialize(value, new JsonSerializerOptions { WriteIndented = true }));
        File.Move(temporary, path, true);
    }
}
