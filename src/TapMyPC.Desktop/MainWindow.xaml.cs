using System.ComponentModel;
using System.Windows;

namespace TapMyPC.Desktop;

public partial class MainWindow : Window
{
    public MainWindow() => InitializeComponent();
    private void Minimize_Click(object sender, RoutedEventArgs e) => SystemCommands.MinimizeWindow(this);
    private void Maximize_Click(object sender, RoutedEventArgs e)
    {
        if (WindowState == WindowState.Maximized) SystemCommands.RestoreWindow(this);
        else SystemCommands.MaximizeWindow(this);
    }
    private void Hide_Click(object sender, RoutedEventArgs e) => Hide();
    protected override void OnClosing(CancelEventArgs e)
    {
        e.Cancel = true;
        Hide();
    }
}
