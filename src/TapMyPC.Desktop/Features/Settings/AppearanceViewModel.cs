using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Media;
using TapMyPC.Windows.Settings;

namespace TapMyPC.Desktop.Features.Settings;

internal sealed record AccentPalette(string Name, string Fill, string Hover, string Soft, string Border, string Text, string Foreground);

public sealed class AppearanceViewModel : INotifyPropertyChanged
{
    private static readonly AccentPalette[] DarkAccents =
    [
        new("Blue", "#0875DF", "#0969C6", "#122338", "#25466A", "#8EC6FF", "#FFFFFF"),
        new("Mint", "#B8E593", "#A6D080", "#1C2B20", "#3E5940", "#C8EDAC", "#132110"),
        new("Purple", "#AC8CFF", "#9977EA", "#261F38", "#4E3C6B", "#C8B3FF", "#1B102D"),
        new("Teal", "#42D3C4", "#36BBAD", "#142C2B", "#285752", "#8BE4DA", "#092523"),
        new("Amber", "#F0B454", "#DAA048", "#302719", "#65502C", "#F5CB86", "#291B07")
    ];

    private static readonly AccentPalette[] LightAccents =
    [
        new("Blue", "#1265B9", "#0B559F", "#E1EFFF", "#A1BDE5", "#155496", "#FFFFFF"),
        new("Mint", "#387323", "#2C5E19", "#E6F4DD", "#9FBE8A", "#305E21", "#FFFFFF"),
        new("Purple", "#7143A8", "#60348F", "#F1E8FC", "#C6ACDF", "#5C3587", "#FFFFFF"),
        new("Teal", "#09736B", "#075D56", "#DDF5EF", "#93C6BB", "#086057", "#FFFFFF"),
        new("Amber", "#8A5314", "#73420D", "#FFF0D7", "#D7AD75", "#77460E", "#FFFFFF")
    ];

    private readonly LocalSettings settings;
    private string theme = "Dark";
    private string accent = "Blue";
    private string status = "";

    public IReadOnlyList<string> ThemeChoices { get; } = DesktopTheme.Choices.Select(choice => choice.Name).ToArray();
    public IReadOnlyList<string> AccentChoices { get; } = DarkAccents.Select(choice => choice.Name).ToArray();

    public AppearanceViewModel(LocalSettings settings)
    {
        this.settings = settings;
        try
        {
            var saved = settings.ReadAppearance();
            if (ThemeChoices.Contains(saved.Theme)) theme = saved.Theme;
            if (AccentChoices.Contains(saved.Accent)) accent = saved.Accent;
        }
        catch (Exception ex) { status = $"Could not read appearance preferences: {ex.Message}"; }
    }

    public string Theme
    {
        get => theme;
        set
        {
            if (theme == value || !ThemeChoices.Contains(value)) return;
            theme = value;
            Save();
            Notify();
        }
    }

    public string Accent
    {
        get => accent;
        set
        {
            if (accent == value || !AccentChoices.Contains(value)) return;
            accent = value;
            Save();
            Notify();
        }
    }

    internal DesktopTheme ThemeColors => DesktopTheme.Choices.First(choice => choice.Name == theme);
    internal AccentPalette AccentColors => (ThemeColors.IsLight ? LightAccents : DarkAccents)
        .First(choice => choice.Name == accent);

    public string Status { get => status; private set { status = value; Notify(); } }

    private void Save()
    {
        try { settings.SaveAppearance(new(accent, theme)); Status = ""; }
        catch (Exception ex) { Status = $"Preview applied, but preferences could not be saved: {ex.Message}"; }
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    private void Notify([CallerMemberName] string? name = null) => PropertyChanged?.Invoke(this, new(name));

    internal static void Apply(ResourceDictionary resources, AppearanceViewModel? appearance)
    {
        var theme = appearance?.ThemeColors ?? DesktopTheme.Choices[0];
        var accent = appearance?.AccentColors ?? DarkAccents[0];
        var light = theme.IsLight;
        foreach (var (key, color) in new[]
        {
            ("BgPrimary", theme.Background), ("SurfaceCard", theme.Card), ("SurfaceElevated", theme.Elevated),
            ("SurfaceSubtle", theme.Subtle), ("BorderHairline", theme.Border), ("ControlBorder", theme.ControlBorder),
            ("ControlHover", theme.Hover), ("SwitchTrack", theme.SwitchTrack), ("ScrollThumb", theme.ScrollThumb),
            ("TextPrimary", theme.Text), ("TextSecondary", theme.Secondary), ("TextMuted", theme.Muted),
            ("TextDetail", theme.Detail), ("DrawerBackdrop", theme.Backdrop),
            ("AccentBlue", accent.Fill), ("AccentBlueHover", accent.Hover), ("AccentSoft", accent.Soft),
            ("AccentBorder", accent.Border), ("AccentText", accent.Text), ("AccentForeground", accent.Foreground),
            ("BluetoothBadgeFill", light ? "#E5EFFF" : "#14263B"),
            ("BluetoothBorder", light ? "#7D9FCB" : "#344F71"),
            ("BluetoothText", light ? "#244E81" : "#A1D0FF"),
            ("WiFiBadgeFill", light ? "#DFF2E7" : "#182C24"),
            ("WiFiBorder", light ? "#79A890" : "#365647"),
            ("WiFiText", light ? "#285B43" : "#A4E2BF"),
            ("TailscaleBadgeFill", light ? "#F0E9FC" : "#29223A"),
            ("TailscaleBorder", light ? "#A894C6" : "#53426D"),
            ("TailscaleText", light ? "#563B83" : "#D5C1FF"),
            ("ErrorText", light ? "#972A28" : "#FFB4AB"),
            ("ErrorSoft", light ? "#FBE9E7" : "#342124"),
            ("ErrorBorder", light ? "#CF9490" : "#694047")
        })
        {
            var brush = new SolidColorBrush((Color)ColorConverter.ConvertFromString(color));
            brush.Freeze();
            resources[key] = brush;
        }
    }
}
