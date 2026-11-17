using TapMyPC.Core.Devices;

namespace TapMyPC.Core.Feedback;

public enum ActionPhase { Running, Succeeded, Requested, Scheduled, Canceled, Failed }
public record ActionNotice(long Sequence, string Title, string Message, ActionPhase Phase,
    DateTimeOffset At, AudioState? Audio = null, DateTimeOffset? DueAt = null);

/// <summary>Bounded, in-memory activity shared by every client and the desktop presentation.</summary>
public sealed class ActionFeed(TimeProvider clock)
{
    private readonly object gate = new();
    private readonly Queue<ActionNotice> history = new();
    private long sequence;
    public event Action<ActionNotice>? Published;
    public IReadOnlyList<ActionNotice> Recent { get { lock (gate) return history.Reverse().ToArray(); } }

    public ActionNotice Publish(string title, string message, ActionPhase phase, AudioState? audio = null, DateTimeOffset? dueAt = null)
    {
        ActionNotice item;
        lock (gate)
        {
            item = new(++sequence, title, message, phase, clock.GetUtcNow(), audio, dueAt);
            history.Enqueue(item);
            while (history.Count > 30) history.Dequeue();
        }
        // Presentation errors must never turn a successful Windows command into an API failure.
        foreach (var subscriber in Published?.GetInvocationList() ?? [])
        {
            try { ((Action<ActionNotice>)subscriber)(item); }
            catch { /* Observers do not own command execution. */ }
        }
        return item;
    }
}
