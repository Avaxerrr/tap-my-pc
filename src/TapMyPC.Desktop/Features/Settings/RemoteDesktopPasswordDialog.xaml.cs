using System.Runtime.InteropServices;
using System.Windows;
using TapMyPC.Windows.RemoteDesktop;

namespace TapMyPC.Desktop.Features.Settings;

public partial class RemoteDesktopPasswordDialog : Window
{
    private string? selectedPassword;
    private string? generatedSuggestion;

    private RemoteDesktopPasswordDialog()
    {
        InitializeComponent();
        if (Application.Current.MainWindow is { IsVisible: true } owner)
        {
            Owner = owner;
            Resources.MergedDictionaries.Add(owner.Resources);
        }
    }

    internal static bool TryChoose(RemoteDesktopOperation operation, out string? password, out bool generated)
    {
        var dialog = new RemoteDesktopPasswordDialog();
        if (operation == RemoteDesktopOperation.ResetPassword) dialog.Confirm.Content = "Save password";
        dialog.Loaded += (_, _) => dialog.CustomPassword.Focus();
        var accepted = dialog.ShowDialog() == true;
        password = accepted ? dialog.selectedPassword : null;
        generated = password is not null && password == dialog.generatedSuggestion;
        dialog.CustomPassword.Clear();
        dialog.VisiblePassword.Clear();
        dialog.selectedPassword = null;
        dialog.generatedSuggestion = null;
        return accepted;
    }

    internal static void ShowGenerated(string password)
    {
        var dialog = new RemoteDesktopPasswordDialog();
        dialog.ChoosePanel.Visibility = Visibility.Collapsed;
        dialog.GeneratedPanel.Visibility = Visibility.Visible;
        dialog.GeneratedPassword.Text = password;
        dialog.ShowDialog();
        dialog.GeneratedPassword.Clear();
    }

    private string EnteredPassword => ShowPassword.IsChecked == true ? VisiblePassword.Text : CustomPassword.Password;

    private void PasswordInput_Changed(object sender, RoutedEventArgs e)
    {
        if (Confirm is null) return;
        Confirm.IsEnabled = EnteredPassword.Length > 0;
        ValidationFeedback.Text = "";
    }

    private void ShowPassword_Click(object sender, RoutedEventArgs e)
    {
        if (ShowPassword.IsChecked == true)
        {
            VisiblePassword.Text = CustomPassword.Password;
            CustomPassword.Clear();
            CustomPassword.Visibility = Visibility.Collapsed;
            VisiblePassword.Visibility = Visibility.Visible;
        }
        else
        {
            CustomPassword.Password = VisiblePassword.Text;
            VisiblePassword.Clear();
            VisiblePassword.Visibility = Visibility.Collapsed;
            CustomPassword.Visibility = Visibility.Visible;
        }
    }

    private void Confirm_Click(object sender, RoutedEventArgs e)
    {
        var password = EnteredPassword;
        if (!RemoteDesktopSetup.IsValidPassword(password))
        {
            ValidationFeedback.Text = "Enter 1–8 characters using English letters, numbers, or standard symbols.";
            if (ShowPassword.IsChecked == true) VisiblePassword.Focus();
            else CustomPassword.Focus();
            return;
        }

        selectedPassword = password;
        DialogResult = true;
    }

    private void Generate_Click(object sender, RoutedEventArgs e)
    {
        generatedSuggestion = RemoteDesktopSetup.GeneratePassword();
        if (ShowPassword.IsChecked == true) VisiblePassword.Text = generatedSuggestion;
        else CustomPassword.Password = generatedSuggestion;
    }

    private void Done_Click(object sender, RoutedEventArgs e) => DialogResult = true;

    private void Copy_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            Clipboard.SetText(GeneratedPassword.Text);
            CopyFeedback.Text = "Password copied.";
        }
        catch (ExternalException)
        {
            CopyFeedback.Text = "The clipboard is busy. Try Copy again, or select the password to copy it.";
        }
    }
}
