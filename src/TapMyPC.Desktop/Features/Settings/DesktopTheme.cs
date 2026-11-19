namespace TapMyPC.Desktop.Features.Settings;

internal sealed record DesktopTheme(
    string Name, string Background, string Card, string Elevated, string Subtle,
    string Border, string ControlBorder, string Hover, string SwitchTrack, string ScrollThumb,
    string Text, string Secondary, string Muted, string Detail, string Backdrop, bool IsLight = false)
{
    public static IReadOnlyList<DesktopTheme> Choices { get; } =
    [
        new("Dark", Background: "#0B0C0E", Card: "#16181D", Elevated: "#1C1F26", Subtle: "#262A34",
            Border: "#262A34", ControlBorder: "#343946", Hover: "#303542", SwitchTrack: "#323642", ScrollThumb: "#424853",
            Text: "#F5F5F7", Secondary: "#98989D", Muted: "#94949B", Detail: "#B6BBC5", Backdrop: "#B3050608"),
        new("Light", Background: "#EEF1F6", Card: "#FFFFFF", Elevated: "#F5F7FB", Subtle: "#E4E9F1",
            Border: "#CED6E3", ControlBorder: "#A0AEC1", Hover: "#D6DFEC", SwitchTrack: "#626E82", ScrollThumb: "#8290A6",
            Text: "#192438", Secondary: "#43536B", Muted: "#4D5D75", Detail: "#384961", Backdrop: "#70182538", IsLight: true),
        new("Midnight", Background: "#0B1325", Card: "#14213A", Elevated: "#1B2C49", Subtle: "#233654",
            Border: "#2B4263", ControlBorder: "#3A5174", Hover: "#2D4567", SwitchTrack: "#3D5377", ScrollThumb: "#50698E",
            Text: "#EFF5FF", Secondary: "#B0C1DB", Muted: "#A7B8D5", Detail: "#C8D7EF", Backdrop: "#B3050B18"),
        new("Forest", Background: "#0C1813", Card: "#16271F", Elevated: "#1D3227", Subtle: "#263E31",
            Border: "#2C4537", ControlBorder: "#3B5948", Hover: "#304D3C", SwitchTrack: "#3F5B4B", ScrollThumb: "#4D7060",
            Text: "#F0F8F3", Secondary: "#AEC6B7", Muted: "#A8BEAE", Detail: "#C7DACD", Backdrop: "#B3060E09"),
        new("Plum", Background: "#1A1020", Card: "#291C32", Elevated: "#33233E", Subtle: "#422F4E",
            Border: "#4A3556", ControlBorder: "#5A4266", Hover: "#50395D", SwitchTrack: "#594164", ScrollThumb: "#70567D",
            Text: "#FBF2FF", Secondary: "#CDBAD7", Muted: "#BEABC9", Detail: "#DFCEE8", Backdrop: "#B30E0813")
    ];
}
