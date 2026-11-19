using TapMyPC.Core.Devices;
using TapMyPC.Core.Feedback;

namespace TapMyPC.Core.Timers;

public record PendingPower(Guid Id, PowerAction Action, DateTimeOffset DueAt);
public record SchedulerState(PendingPower? Pending, string? LastError);

/// <summary>One PC-owned timer. Cancellation and dispatch share a lock, so a canceled timer cannot dispatch later.</summary>
public sealed class PowerScheduler(IDeviceController device, TimeProvider clock) : IDisposable
{
    public ActionFeed Activity { get; } = new(clock);
    private readonly object gate = new();
    private ITimer? timer;
    private PendingPower? pending;
    private Guid? immediateRequest;
    private string? lastError;
    private bool disposed;

    public SchedulerState State { get { lock (gate) return new(pending, lastError); } }

    public PendingPower Schedule(PowerAction action, int delaySeconds)
    {
        var minimum = action is PowerAction.Shutdown or PowerAction.Restart ? 10 : 3;
        if (delaySeconds < minimum || delaySeconds > 86400)
            throw new ArgumentException($"Delay must be between {minimum} and 86400 seconds.");
        ValidateAction(action);
        lock (gate)
        {
            EnsureAvailable();
            var item = new PendingPower(Guid.NewGuid(), action, clock.GetUtcNow().AddSeconds(delaySeconds));
            pending = item;
            lastError = null;
            timer = clock.CreateTimer(_ => Dispatch(item.Id), null, TimeSpan.FromSeconds(delaySeconds), Timeout.InfiniteTimeSpan);
            Activity.Publish(action.ToString(), $"{action} scheduled in {delaySeconds} seconds. You can cancel before it starts.", ActionPhase.Scheduled, dueAt: item.DueAt);
            return item;
        }
    }

    public (ActionNotice Feedback, Action Dispatch) PrepareImmediate(PowerAction action)
    {
        ValidateAction(action);
        if (action is PowerAction.Shutdown or PowerAction.Restart)
            throw new ArgumentException("Shutdown and restart require at least 10 seconds to cancel.");
        lock (gate)
        {
            EnsureAvailable();
            var id = Guid.NewGuid();
            immediateRequest = id;
            lastError = null;
            var feedback = Activity.Publish(action.ToString(), $"{action} requested.", ActionPhase.Requested);
            return (feedback, () => DispatchImmediate(id, action));
        }
    }

    private void ValidateAction(PowerAction action)
    {
        if (!Enum.IsDefined(action)) throw new ArgumentException("Unknown power action.");
        if (action == PowerAction.Sleep && !device.Capabilities.Sleep ||
            action == PowerAction.Hibernate && !device.Capabilities.Hibernate)
            throw new NotSupportedException("This power state is unavailable on this PC.");
    }

    private void EnsureAvailable()
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        if (pending is not null) throw new InvalidOperationException("Cancel the existing timer first.");
        if (immediateRequest is not null) throw new InvalidOperationException("A power request is already being sent.");
    }

    public bool Cancel(Guid id)
    {
        lock (gate)
        {
            if (pending?.Id != id) return false;
            timer?.Dispose(); timer = null; pending = null;
            Activity.Publish("Power action canceled", "The pending power action will not run.", ActionPhase.Canceled);
            return true;
        }
    }

    private void Dispatch(Guid id)
    {
        lock (gate)
        {
            if (disposed || pending?.Id != id) return;
            var action = pending.Action;
            pending = null; timer?.Dispose(); timer = null;
            Execute(action);
        }
    }

    private void DispatchImmediate(Guid id, PowerAction action)
    {
        lock (gate)
        {
            if (disposed || immediateRequest != id) return;
            immediateRequest = null;
            Execute(action);
        }
    }

    private void Execute(PowerAction action)
    {
        Activity.Publish(action.ToString(), $"Sending {action.ToString().ToLowerInvariant()} request to Windows…", ActionPhase.Running);
        try
        {
            device.ExecutePower(action);
            Activity.Publish(action.ToString(), $"{action} request sent to Windows.", ActionPhase.Requested);
        }
        catch (Exception ex)
        {
            lastError = $"{action} failed: {ex.Message}";
            Activity.Publish(action.ToString(), lastError, ActionPhase.Failed);
        }
    }

    public void Dispose()
    {
        lock (gate) { disposed = true; timer?.Dispose(); timer = null; pending = null; immediateRequest = null; }
    }
}
