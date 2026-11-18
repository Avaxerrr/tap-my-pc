using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Media;
using TapMyPC.Windows.Settings;

namespace TapMyPC.Desktop.Features.Settings;

public sealed record AccentPalette(string Name, string Fill, string Hover, string Soft, string Border, string Text, string Foreground);

public sealed class AppearanceViewModel : INotifyPropertyChanged, IDisposable
{
    public static IReadOnlyList<AccentPalette> Palettes { get; } = [
        new("Blue", "#0875DF", "#0969C6", "#122338", "#25466A", "#8EC6FF", "#FFFFFF"),
        new("Mint", "#B8E593", "#A6D080", "#1C2B20", "#3E5940", "#C8EDAC", "#132110"),
        new("Purple", "#AC8CFF", "#9977EA", "#261F38", "#4E3C6B", "#C8B3FF", "#1B102D"),
        new("Teal", "#42D3C4", "#36BBAD", "#142C2B", "#285752", "#8BE4DA", "#092523"),
        new("Amber", "#F0B454", "#DAA048", "#302719", "#65502C", "#F5CB86", "#291B07")
    ];
    public IReadOnlyList<string> AccentChoices { get; } = Palettes.Select(p => p.Name).ToArray();
    public IReadOnlyList<string> MotionChoices { get; } = ["Follow Windows", "On", "Off"];
    private readonly LocalSettings settings;
    private string accent = "Blue", motion = "Follow Windows", status = "";
    public AppearanceViewModel(LocalSettings settings)
    {
        this.settings = settings;
        try
        {
            var saved = settings.ReadAppearance();
            accent = AccentChoices.Contains(saved.Accent) ? saved.Accent : "Blue";
            motion = MotionChoices.Contains(saved.Motion) ? saved.Motion : "Follow Windows";
        }
        catch (Exception ex) { status = $"Could not read appearance preferences: {ex.Message}"; }
        SystemParameters.StaticPropertyChanged += SystemSettingChanged;
    }
    public string Accent
    {
        get => accent;
        set
        {
            if (accent == value || !AccentChoices.Contains(value)) return;
            accent = value; Save(); Notify(); Notify(nameof(Palette));
        }
    }
    public string Motion
    {
        get => motion;
        set
        {
            if (motion == value || !MotionChoices.Contains(value)) return;
            motion = value; Save(); Notify(); Notify(nameof(AnimationsEnabled));
        }
    }
    public AccentPalette Palette => Palettes.First(p => p.Name == accent);
    public bool AnimationsEnabled => motion == "On" || (motion == "Follow Windows" && SystemParameters.ClientAreaAnimation);
    public string Status { get => status; private set { status = value; Notify(); } }
    private void Save()
    {
        try { settings.SaveAppearance(new(accent, motion)); Status = ""; }
        catch (Exception ex) { Status = $"Preview applied, but preferences could not be saved: {ex.Message}"; }
    }
    private void SystemSettingChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(SystemParameters.ClientAreaAnimation)) Notify(nameof(AnimationsEnabled));
    }
    public void Dispose() => SystemParameters.StaticPropertyChanged -= SystemSettingChanged;
    public event PropertyChangedEventHandler? PropertyChanged;
    private void Notify([CallerMemberName] string? name = null) => PropertyChanged?.Invoke(this, new(name));
    public static void Apply(ResourceDictionary resources, AccentPalette palette)
    {
        foreach (var (key, color) in new[] {
            ("AccentBlue", palette.Fill), ("AccentBlueHover", palette.Hover), ("AccentSoft", palette.Soft),
            ("AccentBorder", palette.Border), ("AccentText", palette.Text), ("AccentForeground", palette.Foreground) })
        {
            var brush = new SolidColorBrush((Color)ColorConverter.ConvertFromString(color));
            brush.Freeze(); resources[key] = brush;
        }
    }
}
