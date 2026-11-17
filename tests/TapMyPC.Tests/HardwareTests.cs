using TapMyPC.Core.Audio;
using TapMyPC.Core.Devices;
using TapMyPC.Core.Display;
using TapMyPC.Core.Feedback;
using TapMyPC.Core.Shortcuts;

namespace TapMyPC.Tests;

internal sealed class FakeHardware : IAudioOutputController, IMonitorController
{
    public string DefaultOutput { get; private set; } = "speakers";
    public int OutputChanges { get; private set; }
    public List<MonitorStatus> Monitors { get; } =
    [
        new("monitor-1", "Main monitor", 60, true, true, true),
        new("monitor-2", "Second monitor", null, false, false, null, "Unsupported monitor.")
    ];
    public IReadOnlyList<AudioOutput> List() => new[] { "speakers", "headphones" }.Select(id => new AudioOutput(id, id, DefaultOutput == id)).ToArray();
    public void Select(string id) { DefaultOutput = id; OutputChanges++; }
    public Task<IReadOnlyList<MonitorStatus>> ListAsync() => Task.FromResult<IReadOnlyList<MonitorStatus>>(Monitors.ToArray());
    public Task SetBrightnessAsync(string id, int brightness)
    {
        var index = Monitors.FindIndex(m => m.Id == id);
        Monitors[index] = Monitors[index] with { Brightness = brightness };
        return Task.CompletedTask;
    }
    public Task SetPowerAsync(string id, bool enabled)
    {
        var index = Monitors.FindIndex(m => m.Id == id);
        Monitors[index] = Monitors[index] with { IsOn = enabled };
        return Task.CompletedTask;
    }
}
internal sealed class MemoryShortcutStore : IShortcutStore
{
    public IReadOnlyList<ApprovedShortcut> Items { get; private set; } = [];
    public bool FailSave { get; set; }
    public IReadOnlyList<ApprovedShortcut> LoadShortcuts() => Items;
    public void SaveShortcuts(IReadOnlyList<ApprovedShortcut> value)
    {
        if (FailSave) throw new IOException("Simulated save failure.");
        Items = value.ToArray();
    }
}
internal sealed class FakeShortcutLauncher : IShortcutLauncher
{
    public List<ApprovedShortcut> Launched { get; } = [];
    public void Launch(ApprovedShortcut shortcut) => Launched.Add(shortcut);
}

public sealed class HardwareTests
{
    [Fact]
    public async Task AudioSelectRejectsStaleIdsAndConfirmsTheNewDefault()
    {
        var hardware = new FakeHardware();
        var commands = new HardwareCommands(new ActionFeed(TimeProvider.System));
        await Assert.ThrowsAsync<ArgumentException>(() => commands.SelectOutputAsync(hardware, "removed"));
        Assert.Equal(0, hardware.OutputChanges);
        var feedback = await commands.SelectOutputAsync(hardware, "headphones");
        Assert.Equal("headphones", hardware.DefaultOutput);
        Assert.Equal(ActionPhase.Succeeded, feedback.Phase);
    }

    [Fact]
    public async Task MonitorCommandsValidateRangeAndSupportAndTargetOneDisplay()
    {
        var hardware = new FakeHardware();
        var commands = new HardwareCommands(new ActionFeed(TimeProvider.System));
        await Assert.ThrowsAsync<ArgumentException>(() => commands.SetBrightnessAsync(hardware, "monitor-1", -1));
        await Assert.ThrowsAsync<ArgumentException>(() => commands.SetBrightnessAsync(hardware, "monitor-1", 101));
        await Assert.ThrowsAsync<ArgumentException>(() => commands.SetMonitorPowerAsync(hardware, "removed", false));
        await Assert.ThrowsAsync<NotSupportedException>(() => commands.SetBrightnessAsync(hardware, "monitor-2", 50));
        await Assert.ThrowsAsync<NotSupportedException>(() => commands.SetMonitorPowerAsync(hardware, "monitor-2", false));
        Assert.Equal(60, hardware.Monitors[0].Brightness);
        var result = await commands.SetBrightnessAsync(hardware, "monitor-1", 25);
        Assert.Equal(ActionPhase.Requested, result.Phase);
        await commands.SetMonitorPowerAsync(hardware, "monitor-1", false);
        Assert.Equal(25, hardware.Monitors[0].Brightness);
        Assert.False(hardware.Monitors[0].IsOn);
        Assert.Null(hardware.Monitors[1].IsOn);
    }

    [Fact]
    public void ShortcutsPersistLocallyAndRemovedIdsCannotLaunch()
    {
        var store = new MemoryShortcutStore();
        var launcher = new FakeShortcutLauncher();
        var catalog = new ShortcutCatalog(store, launcher, new ActionFeed(TimeProvider.System));
        catalog.Add("Example", ShortcutKind.Website, "https://example.com/path?q=test");
        var id = Assert.Single(catalog.List()).Id;
        var reloaded = new ShortcutCatalog(store, launcher, new ActionFeed(TimeProvider.System));
        reloaded.Launch(id);
        Assert.Equal("https://example.com/path?q=test", Assert.Single(launcher.Launched).Target);
        reloaded.Remove(id);
        Assert.Throws<ArgumentException>(() => reloaded.Launch(id));
        Assert.Single(launcher.Launched);
        store.FailSave = true;
        Assert.Throws<IOException>(() => reloaded.Add("Unsaved", ShortcutKind.Website, "https://example.com"));
        Assert.Empty(reloaded.List());
    }

    [Theory]
    [InlineData("javascript:alert(1)")]
    [InlineData("file:///C:/Windows/notepad.exe")]
    [InlineData("https://user:password@example.com")]
    [InlineData("not a url")]
    public void WebsitesRejectNonWebTargetsAndCredentials(string target)
    {
        var catalog = new ShortcutCatalog(new MemoryShortcutStore(), new FakeShortcutLauncher(), new ActionFeed(TimeProvider.System));
        Assert.Throws<ArgumentException>(() => catalog.Add("Invalid", ShortcutKind.Website, target));
        Assert.Empty(catalog.List());
    }

    [Theory]
    [InlineData("relative.exe")]
    [InlineData("script.cmd")]
    public void AppsRequireApprovedExecutableOrShortcutPaths(string target)
    {
        var catalog = new ShortcutCatalog(new MemoryShortcutStore(), new FakeShortcutLauncher(), new ActionFeed(TimeProvider.System));
        Assert.Throws<ArgumentException>(() => catalog.Add("Invalid", ShortcutKind.App, target));
    }
}
