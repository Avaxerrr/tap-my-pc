using System.Text.Json;
using TapMyPC.Windows.Settings;

namespace TapMyPC.Tests;

public sealed class NetworkSettingsTests
{
    [Fact]
    public void OldExplicitTailscaleChoiceBecomesIndependentOptInWithoutLosingPreferences()
    {
        var directory = Path.Combine(Path.GetTempPath(), "TapMyPC-network-settings-" + Guid.NewGuid().ToString("N"));
        try
        {
            var store = new LocalSettings(directory);
            store.SaveHost(new("100.80.90.100", 45840, false, ConnectionsEnabled: false));
            var migrated = store.ReadHost();
            Assert.Equal("auto", migrated.Address);
            Assert.True(migrated.TailscaleEnabled);
            Assert.False(migrated.ConnectionsEnabled);
            Assert.False(migrated.ShowNotifications);
            Assert.Equal(45840, migrated.Port);
            store.SaveHost(migrated);
            Assert.Equal(migrated, store.ReadHost());
        }
        finally { if (Directory.Exists(directory)) Directory.Delete(directory, true); }
    }

    [Fact]
    public void LocalDefaultsDoNotEnableTailscale()
    {
        var directory = Path.Combine(Path.GetTempPath(), "TapMyPC-network-settings-" + Guid.NewGuid().ToString("N"));
        try
        {
            var store = new LocalSettings(directory);
            Assert.False(store.ReadHost().TailscaleEnabled);
            store.SaveHost(new("192.168.1.10"));
            Assert.Equal("192.168.1.10", store.ReadHost().Address);
            Assert.False(store.ReadHost().TailscaleEnabled);
        }
        finally { if (Directory.Exists(directory)) Directory.Delete(directory, true); }
    }
}
