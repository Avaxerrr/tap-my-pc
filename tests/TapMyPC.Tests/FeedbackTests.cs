using Microsoft.Extensions.Time.Testing;
using TapMyPC.Core.Devices;
using TapMyPC.Core.Feedback;
using TapMyPC.Core.Timers;

namespace TapMyPC.Tests;

public class FeedbackTests
{
    [Fact]
    public void FailedCommandsPublishFailureWithoutReportingSuccess()
    {
        var feed = new ActionFeed(new FakeTimeProvider());
        var commands = new RemoteCommands(new FakeDevice { FailAudio = true }, feed);
        Assert.Throws<InvalidOperationException>(() => commands.SetVolume(60));
        Assert.Equal(ActionPhase.Failed, feed.Recent[0].Phase);
        Assert.DoesNotContain(feed.Recent, item => item.Phase == ActionPhase.Succeeded);
    }

    [Fact]
    public void AudioFeedbackReportsActualStateAndOrderedProgress()
    {
        var device = new FakeDevice();
        var feed = new ActionFeed(new FakeTimeProvider());
        var commands = new RemoteCommands(device, feed);
        var observed = new List<ActionNotice>();
        feed.Published += observed.Add;
        var result = commands.SetVolume(67);
        Assert.Equal(new[] { ActionPhase.Running, ActionPhase.Succeeded }, observed.Select(n => n.Phase));
        Assert.Equal(67, result.Audio?.Volume);
        Assert.Equal("Volume 67%", result.Message);
        Assert.True(observed[0].Sequence < observed[1].Sequence);
        Assert.True(commands.SetMute(true).Audio?.Muted);
    }

    [Fact]
    public void ObserversCannotFailACommandAndHistoryIsBounded()
    {
        var device = new FakeDevice();
        var feed = new ActionFeed(new FakeTimeProvider());
        feed.Published += _ => throw new InvalidOperationException("Presentation error");
        var commands = new RemoteCommands(device, feed);
        for (var i = 0; i < 25; i++) commands.SetVolume(i);
        Assert.Equal(24, device.Audio.Volume);
        Assert.Equal(30, feed.Recent.Count);
        Assert.Equal(50, feed.Recent[0].Sequence);
    }

    [Fact]
    public void MediaReportsRequestRatherThanClaimingPlaybackSucceeded()
    {
        var feed = new ActionFeed(new FakeTimeProvider());
        var result = new RemoteCommands(new FakeDevice(), feed).Media(MediaAction.PlayPause);
        Assert.Equal(ActionPhase.Requested, result.Phase);
        Assert.Contains("sent to Windows", result.Message);
    }

    [Fact]
    public void TimersPublishScheduleCancelAndExecutionFailure()
    {
        var clock = new FakeTimeProvider();
        using var scheduler = new PowerScheduler(new FakeDevice { FailPower = true }, clock);
        var pending = scheduler.Schedule(PowerAction.Shutdown, 10);
        Assert.Equal(ActionPhase.Scheduled, scheduler.Activity.Recent[0].Phase);
        Assert.Equal(pending.DueAt, scheduler.Activity.Recent[0].DueAt);
        scheduler.Cancel(pending.Id);
        Assert.Equal(ActionPhase.Canceled, scheduler.Activity.Recent[0].Phase);
        scheduler.Schedule(PowerAction.Restart, 10);
        clock.Advance(TimeSpan.FromSeconds(10));
        Assert.Equal(ActionPhase.Failed, scheduler.Activity.Recent[0].Phase);
    }
}
