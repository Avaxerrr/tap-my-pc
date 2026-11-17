using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using Microsoft.Win32;
using TapMyPC.Core.Shortcuts;

namespace TapMyPC.Desktop.Features.Settings;

public sealed class ShortcutsViewModel : INotifyPropertyChanged
{
    private readonly ShortcutCatalog catalog;
    private string name = "", websiteUrl = "", status = "Approve shortcuts here, then launch them from your phone.";
    public ShortcutsViewModel(ShortcutCatalog catalog)
    {
        this.catalog = catalog;
        AddApp = new RelayCommand(() => Execute(() =>
        {
            var picker = new OpenFileDialog { Title = "Approve an application or Windows shortcut", Filter = "Applications and shortcuts|*.exe;*.lnk", CheckFileExists = true, DereferenceLinks = false };
            if (picker.ShowDialog() != true) return;
            catalog.Add(string.IsNullOrWhiteSpace(Name) ? System.IO.Path.GetFileNameWithoutExtension(picker.FileName) : Name, ShortcutKind.App, picker.FileName);
            Name = "";
            Refresh();
            Status = "Application approved. Refresh shortcuts on your phone.";
        }));
        AddWebsite = new RelayCommand(() => Execute(() =>
        {
            catalog.Add(Name, ShortcutKind.Website, WebsiteUrl);
            Name = ""; WebsiteUrl = "";
            Refresh();
            Status = "Website approved. Refresh shortcuts on your phone.";
        }));
        Remove = new RelayCommand(() => Execute(() =>
        {
            if (Selected is null) { Status = "Select a shortcut to remove."; return; }
            catalog.Remove(Selected.Id);
            Selected = null;
            Refresh();
            Status = "Shortcut removed. Remote launch requests for it will be rejected.";
        }));
        Refresh();
    }
    public ObservableCollection<ApprovedShortcut> Items { get; } = [];
    public ApprovedShortcut? Selected { get; set; }
    public string Name { get => name; set { name = value; Notify(); } }
    public string WebsiteUrl { get => websiteUrl; set { websiteUrl = value; Notify(); } }
    public string Status { get => status; private set { status = value; Notify(); } }
    public RelayCommand AddApp { get; }
    public RelayCommand AddWebsite { get; }
    public RelayCommand Remove { get; }
    private void Refresh() { Items.Clear(); foreach (var item in catalog.All) Items.Add(item); }
    private void Execute(Action action) { try { action(); } catch (Exception ex) { Status = ex.Message; } }
    public event PropertyChangedEventHandler? PropertyChanged;
    private void Notify([CallerMemberName] string? name = null) => PropertyChanged?.Invoke(this, new(name));
}
