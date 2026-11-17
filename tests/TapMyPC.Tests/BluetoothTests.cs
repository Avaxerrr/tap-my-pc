using TapMyPC.Core.Bluetooth;
using TapMyPC.Core.Feedback;

namespace TapMyPC.Tests;

public sealed class BluetoothTests
{
    [Fact]
    public async Task AcceptedChangeIsNotClaimedAsCompletedUntilStateMatches()
    {
        var device = new FakeBluetooth { ConfirmChange = false };
        var feed = new ActionFeed(TimeProvider.System);
        var commands = new BluetoothCommands(device, feed);
        var notice = await commands.SetEnabledAsync(false);
        Assert.Equal(ActionPhase.Requested, notice.Phase);
        Assert.Contains("current state: on", notice.Message);
        Assert.Equal(ActionPhase.Running, feed.Recent[1].Phase);
        device.ConfirmChange = true;
        notice = await commands.SetEnabledAsync(false);
        Assert.Equal(ActionPhase.Succeeded, notice.Phase);
        Assert.Equal("Bluetooth off", notice.Message);
    }
}
