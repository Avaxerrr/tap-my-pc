using TapMyPC.Core.Feedback;

namespace TapMyPC.Core.Shortcuts;

public enum ShortcutKind { App, Website }
public record ApprovedShortcut(Guid Id, string Name, ShortcutKind Kind, string Target);
public record ShortcutSummary(Guid Id, string Name, ShortcutKind Kind);
public interface IShortcutStore
{
    IReadOnlyList<ApprovedShortcut> LoadShortcuts();
    void SaveShortcuts(IReadOnlyList<ApprovedShortcut> shortcuts);
}
public interface IShortcutLauncher { void Launch(ApprovedShortcut shortcut); }

/// <summary>Only the local settings UI can approve targets. Remote clients receive IDs and labels.</summary>
public sealed class ShortcutCatalog
{
    private readonly IShortcutStore store;
    private readonly IShortcutLauncher launcher;
    private readonly ActionFeed activity;
    private readonly object gate = new();
    private IReadOnlyList<ApprovedShortcut> items;

    public ShortcutCatalog(IShortcutStore store, IShortcutLauncher launcher, ActionFeed activity)
    {
        this.store = store; this.launcher = launcher; this.activity = activity;
        items = store.LoadShortcuts().ToArray();
        if (items.Count > 30 || items.Select(s => s.Id).Distinct().Count() != items.Count)
            throw new ArgumentException("The saved shortcut list is invalid.");
        foreach (var item in items) Validate(item.Name, item.Kind, item.Target);
    }
    public IReadOnlyList<ApprovedShortcut> All { get { lock (gate) return items.ToArray(); } }
    public IReadOnlyList<ShortcutSummary> List() => All.Select(s => new ShortcutSummary(s.Id, s.Name, s.Kind)).ToArray();

    public void Add(string name, ShortcutKind kind, string target)
    {
        name = name.Trim(); target = target.Trim();
        Validate(name, kind, target);
        lock (gate)
        {
            if (items.Count >= 30) throw new InvalidOperationException("Keep up to 30 approved shortcuts.");
            var updated = items.Append(new ApprovedShortcut(Guid.NewGuid(), name, kind, target)).ToArray();
            store.SaveShortcuts(updated);
            items = updated;
        }
    }

    public void Remove(Guid id)
    {
        lock (gate)
        {
            var updated = items.Where(s => s.Id != id).ToArray();
            store.SaveShortcuts(updated);
            items = updated;
        }
    }

    public ActionNotice Launch(Guid id)
    {
        var shortcut = All.SingleOrDefault(s => s.Id == id) ?? throw new ArgumentException("This shortcut was removed or is not approved.");
        activity.Publish("Shortcut", $"Opening {shortcut.Name}…", ActionPhase.Running);
        try
        {
            launcher.Launch(shortcut);
            return activity.Publish("Shortcut", $"Open request sent: {shortcut.Name}", ActionPhase.Requested);
        }
        catch
        {
            activity.Publish("Shortcut", $"Could not open {shortcut.Name}. Check its saved target on the PC.", ActionPhase.Failed);
            throw;
        }
    }

    private static void Validate(string name, ShortcutKind kind, string target)
    {
        if (string.IsNullOrWhiteSpace(name) || name.Length > 60) throw new ArgumentException("Use a shortcut name of 1–60 characters.");
        if (string.IsNullOrWhiteSpace(target) || target.Length > 2048) throw new ArgumentException("Choose a valid shortcut target.");
        if (kind == ShortcutKind.Website)
        {
            if (!Uri.TryCreate(target, UriKind.Absolute, out var uri) || (uri.Scheme != "https" && uri.Scheme != "http") || uri.UserInfo.Length != 0)
                throw new ArgumentException("Use an http:// or https:// website address without embedded credentials.");
        }
        else if (kind == ShortcutKind.App)
        {
            if (!Path.IsPathFullyQualified(target) || !new[] { ".exe", ".lnk" }.Contains(Path.GetExtension(target), StringComparer.OrdinalIgnoreCase))
                throw new ArgumentException("Choose an application (.exe) or Windows shortcut (.lnk) using its full path.");
        }
        else throw new ArgumentException("Unknown shortcut type.");
    }
}
