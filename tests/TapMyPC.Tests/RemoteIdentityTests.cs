using Microsoft.Extensions.Time.Testing;
using TapMyPC.Core.Devices;

namespace TapMyPC.Tests;

public sealed class RemoteIdentityTests
{
    [Fact]
    public void ReportsActualTransportAndMigratesGenericNameWithoutChangingCredentials()
    {
        var store = new MemoryStore();
        var pairing = new PairingService(store, new FakeTimeProvider());
        var token = pairing.Pair(pairing.OpenPairing().Code, "TapMyPC Android");
        var before = Assert.Single(store.Devices);
        Assert.True(pairing.Authorize(token, RemoteTransport.WiFi, "POCO X6 5G"));
        var active = Assert.Single(pairing.ActiveClients);
        Assert.Equal("POCO X6 5G", active.Name);
        Assert.Equal(RemoteTransport.WiFi, active.Transport);
        Assert.Equal(before.TokenHash, Assert.Single(store.Devices).TokenHash);
        Assert.Equal(before.Id, active.Id);
        Assert.True(pairing.Authorize(token, RemoteTransport.Bluetooth, "POCO X6 5G"));
        Assert.Equal(RemoteTransport.Bluetooth, Assert.Single(pairing.ActiveClients).Transport);
        var restored = new PairingService(store, new FakeTimeProvider());
        Assert.Equal("POCO X6 5G", Assert.Single(restored.Clients).Name);
        Assert.Empty(restored.ActiveClients);
    }

    [Fact]
    public void LocalRenamePersistsAndTakesPriorityOverPhoneReportedName()
    {
        var store = new MemoryStore();
        var pairing = new PairingService(store, new FakeTimeProvider());
        var token = pairing.Pair(pairing.OpenPairing().Code, "POCO");
        pairing.Rename(Assert.Single(pairing.Clients).Id, " My phone ");
        var restored = new PairingService(store, new FakeTimeProvider());
        Assert.True(restored.Authorize(token, RemoteTransport.Bluetooth, "Changed OS device name"));
        Assert.Equal("My phone", Assert.Single(restored.ActiveClients).Name);
        Assert.True(Assert.Single(store.Devices).NameCustomized);
        Assert.Throws<ArgumentException>(() => restored.Rename(Assert.Single(restored.Clients).Id, "bad\nname"));
        Assert.Throws<ArgumentException>(() => restored.Rename(Assert.Single(restored.Clients).Id, " "));
    }

    [Fact]
    public void RejectedTokensAndInvalidNamesCannotRenameOtherPhones()
    {
        var pairing = new PairingService(new MemoryStore(), new FakeTimeProvider());
        var first = pairing.Pair(pairing.OpenPairing().Code, "First");
        var second = pairing.Pair(pairing.OpenPairing().Code, "Second");
        Assert.False(pairing.Authorize(new string('0', 64), RemoteTransport.Bluetooth, "Spoofed"));
        foreach (var name in new[] { " ", "bad\nname", new string('x', 61) })
            Assert.True(pairing.Authorize(first, RemoteTransport.WiFi, name));
        Assert.Equal("First", pairing.Clients[0].Name);
        Assert.Equal("Second", pairing.Clients[1].Name);
        pairing.Authorize(second, RemoteTransport.Bluetooth, "Second phone");
        Assert.Collection(pairing.ActiveClients,
            c => Assert.Equal(RemoteTransport.WiFi, c.Transport),
            c => Assert.Equal(RemoteTransport.Bluetooth, c.Transport));
    }

    [Fact]
    public void OptionalNamePersistenceFailureDoesNotRejectAnAuthorizedCommand()
    {
        var store = new FailingStore();
        var pairing = new PairingService(store, new FakeTimeProvider());
        var token = pairing.Pair(pairing.OpenPairing().Code, "Old name");
        store.Fail = true;
        Assert.True(pairing.Authorize(token, RemoteTransport.Bluetooth, "New name"));
        Assert.Equal("Old name", Assert.Single(pairing.ActiveClients).Name);
        Assert.Equal(RemoteTransport.Bluetooth, Assert.Single(pairing.ActiveClients).Transport);
        Assert.Throws<IOException>(() => pairing.Rename(Assert.Single(pairing.Clients).Id, "Custom"));
        Assert.Equal("Old name", Assert.Single(pairing.Clients).Name);
    }

    private sealed class FailingStore : IDeviceStore
    {
        public bool Fail { get; set; }
        private IReadOnlyList<PairedDevice> devices = [];
        public IReadOnlyList<PairedDevice> Load() => devices;
        public void Save(IReadOnlyList<PairedDevice> value) {
            if (Fail) throw new IOException("Simulated storage failure.");
            devices = value;
        }
    }
}
