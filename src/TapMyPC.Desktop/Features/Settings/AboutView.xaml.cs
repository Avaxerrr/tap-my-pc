using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Navigation;

namespace TapMyPC.Desktop.Features.Settings;

public partial class AboutView : UserControl
{
    private const string PairingGuide = """
        1. Start TapMyPC on Windows and connect your PC and phone to the same trusted local network. If the Windows dashboard shows that connections are stopped, select Start connections.

        2. On Windows, open Pair a Phone. Select Show pairing QR or Add another phone if you need a new invitation.

        3. On Android, select Add your PC or Add another PC, then Scan PC QR. Scan the invitation, review the PC name, and select Pair with this PC.

        TapMyPC remembers this PC. Leave the phone on Automatic to try the local network, Tailscale, then Bluetooth when those routes are configured.

        To use the browser remote, open the HTTPS address from Pair a Phone, verify the certificate against the fingerprint on the PC, and enter the one-time code.
        """;

    private Button? detailsSource;

    public AboutView() => InitializeComponent();

    public event EventHandler? BackRequested;

    internal void Prepare(string version)
    {
        ShowOverview();
        VersionText.Text = version.TrimStart('v');
        CopyVersion.IsEnabled = version != "Version unavailable";
        Feedback.Text = "";
        AboutContent.ScrollToTop();
    }

    internal void FocusBack() => Back.Focus();

    internal void GoBack()
    {
        var source = detailsSource;
        if (source is null)
        {
            BackRequested?.Invoke(this, EventArgs.Empty);
            return;
        }

        ShowOverview();
        source.Focus();
    }

    private void ShowOverview()
    {
        detailsSource = null;
        Back.Content = "‹  Configure";
        Heading.Text = "About TapMyPC";
        DetailsText.Visibility = Visibility.Collapsed;
        AboutContent.Visibility = Visibility.Visible;
    }

    private void CopyVersion_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            Clipboard.SetText($"TapMyPC Windows app: {VersionText.Text}");
            Feedback.Text = "Version info copied.";
        }
        catch (ExternalException)
        {
            Feedback.Text = "Could not copy version info. Try again.";
        }
    }

    private void SetupGuide_Click(object sender, RoutedEventArgs e) =>
        ShowDetails(SetupGuide, "Setup guide", PairingGuide);

    private void Licenses_Click(object sender, RoutedEventArgs e)
    {
        var assembly = typeof(AboutView).Assembly;
        const string prefix = "TapMyPC.Licenses.";
        var names = assembly.GetManifestResourceNames()
            .Where(name => name.StartsWith(prefix, StringComparison.Ordinal))
            .OrderBy(name => name, StringComparer.Ordinal);

        var licenses = new List<string>();
        foreach (var name in names)
        {
            using var stream = assembly.GetManifestResourceStream(name)!;
            using var reader = new StreamReader(stream);
            var title = Path.GetFileNameWithoutExtension(name[prefix.Length..]);
            licenses.Add($"{title}\n\n{reader.ReadToEnd().Trim()}");
        }

        ShowDetails(Licenses, "Third-party licenses", string.Join("\n\n", licenses));
    }

    private void ShowDetails(Button source, string title, string text)
    {
        detailsSource = source;
        Back.Content = "‹  About TapMyPC";
        Heading.Text = title;
        DetailsText.Text = text;
        AboutContent.Visibility = Visibility.Hidden;
        DetailsText.Visibility = Visibility.Visible;
        DetailsText.ScrollToHome();
        Back.Focus();
    }

    private void Back_Click(object sender, RoutedEventArgs e) => GoBack();

    private void GitHubRepository_Click(object sender, RoutedEventArgs e) =>
        OpenLink("https://github.com/Avaxerrr/tap-my-pc", "GitHub repository");

    private void DeveloperCredit_RequestNavigate(object sender, RequestNavigateEventArgs e)
    {
        e.Handled = true;
        OpenLink(e.Uri.AbsoluteUri, "GitHub profile");
    }

    private void OpenLink(string url, string label)
    {
        try
        {
            Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
        }
        catch (Exception ex) when (ex is Win32Exception or InvalidOperationException)
        {
            Feedback.Text = $"Could not open the {label}.";
        }
    }
}
