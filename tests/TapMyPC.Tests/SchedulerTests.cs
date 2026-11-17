using Microsoft.Extensions.Time.Testing;
using TapMyPC.Core.Devices;
using TapMyPC.Core.Timers;

namespace TapMyPC.Tests;

public class SchedulerTests
{
    [Fact]
    public void TimerDispatchesExactlyOnceWithoutAClient()
    {
        var device = new FakeDevice(); var clock = new FakeTimeProvider(); using var scheduler = new PowerScheduler(device, clock);
        scheduler.Schedule(PowerAction.Shutdown, 10);
        clock.Advance(TimeSpan.FromSeconds(9)); Assert.Empty(device.PowerActions);
        clock.Advance(TimeSpan.FromSeconds(1)); Assert.Equal(PowerAction.Shutdown, Assert.Single(device.PowerActions));
        clock.Advance(TimeSpan.FromDays(2)); Assert.Single(device.PowerActions); Assert.Null(scheduler.State.Pending);
    }

    [Fact]
    public void CancelCannotCancelANewerTimerAndPreventsDispatch()
    {
        var device = new FakeDevice(); var clock = new FakeTimeProvider(); using var scheduler = new PowerScheduler(device, clock);
        var first = scheduler.Schedule(PowerAction.Restart, 10); Assert.True(scheduler.Cancel(first.Id));
        var second = scheduler.Schedule(PowerAction.Hibernate, 30); Assert.False(scheduler.Cancel(first.Id));
        Assert.Equal(second, scheduler.State.Pending); Assert.True(scheduler.Cancel(second.Id));
        clock.Advance(TimeSpan.FromMinutes(2)); Assert.Empty(device.PowerActions);
    }

    [Fact]
    public void ConflictAndInvalidRequestsPreserveExistingTimer()
    {
        var device = new FakeDevice(); var clock = new FakeTimeProvider(); using var scheduler = new PowerScheduler(device, clock);
        Assert.Throws<ArgumentException>(() => scheduler.Schedule(PowerAction.Restart, 9));
        Assert.Throws<ArgumentException>(() => scheduler.Schedule((PowerAction)999, 30));
        var item = scheduler.Schedule(PowerAction.Sleep, 10);
        Assert.Throws<InvalidOperationException>(() => scheduler.Schedule(PowerAction.Restart, 30));
        Assert.Equal(item, scheduler.State.Pending);
    }

    [Fact]
    public void UnsupportedStatesAreRejectedAndExecutionFailuresAreVisible()
    {
        var device = new FakeDevice { FailPower = true, Capabilities = new(true, true, true, false, false) };
        var clock = new FakeTimeProvider(); using var scheduler = new PowerScheduler(device, clock);
        Assert.Throws<NotSupportedException>(() => scheduler.Schedule(PowerAction.Sleep, 10));
        scheduler.Schedule(PowerAction.Shutdown, 10); clock.Advance(TimeSpan.FromSeconds(10));
        Assert.Contains("Simulated Windows rejection", scheduler.State.LastError);
        Assert.Null(scheduler.State.Pending);
    }

    [Fact]
    public void ExitCancelsPendingTimers()
    {
        var device = new FakeDevice(); var clock = new FakeTimeProvider(); var scheduler = new PowerScheduler(device, clock);
        scheduler.Schedule(PowerAction.Shutdown, 10); scheduler.Dispose(); clock.Advance(TimeSpan.FromMinutes(1));
        Assert.Empty(device.PowerActions);
    }
}
