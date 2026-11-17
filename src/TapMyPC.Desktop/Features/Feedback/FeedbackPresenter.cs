using System.Windows.Threading;
using TapMyPC.Core.Feedback;
using TapMyPC.Core.Timers;

namespace TapMyPC.Desktop.Features.Feedback;

/// <summary>Silent, non-modal feedback. Only shows in response to remote activity or a pending action's final countdown.</summary>
public sealed class FeedbackPresenter : IDisposable
{
    private readonly PowerScheduler scheduler;
    private readonly Func<bool> enabled;
    private readonly Dispatcher dispatcher;
    private readonly FeedbackWindow window = new();
    private readonly DispatcherTimer timer;
    private DateTimeOffset hideAt;
    private ActionNotice? current;
    private bool disposed;

    public FeedbackPresenter(PowerScheduler scheduler, Func<bool> enabled, Dispatcher dispatcher)
    {
        this.scheduler = scheduler; this.enabled = enabled; this.dispatcher = dispatcher;
        scheduler.Activity.Published += OnNotice;
        window.CancelRequested += Cancel;
        timer = new DispatcherTimer(TimeSpan.FromSeconds(1), DispatcherPriority.Background, (_, _) => Tick(), dispatcher);
    }

    private void OnNotice(ActionNotice item) => dispatcher.BeginInvoke(() =>
    {
        if (disposed || !enabled()) return;
        current = item;
        hideAt = DateTimeOffset.UtcNow.AddSeconds(item.Phase == ActionPhase.Failed ? 7 : 4);
        Tick();
    });

    private void Tick()
    {
        if (disposed) return;
        if (!enabled()) { window.Hide(); return; }
        var pending = scheduler.State.Pending;
        var remaining = pending is null ? (double?)null : (pending.DueAt - DateTimeOffset.UtcNow).TotalSeconds;
        if (pending is not null && remaining <= 10)
        {
            var countdown = new ActionNotice(0, $"{pending.Action} coming up", "Requested from your remote. Cancel now to keep this PC on.", ActionPhase.Scheduled, DateTimeOffset.UtcNow, DueAt: pending.DueAt);
            window.Present(countdown, remaining);
            if (!window.IsVisible) window.Show();
        }
        else if (current is not null && DateTimeOffset.UtcNow < hideAt)
        {
            // Display-off requests must not create a new window after the monitors have been told to sleep.
            if (current.Title == "Displays" && current.Phase != ActionPhase.Failed) { window.Hide(); return; }
            window.Present(current, current.Phase == ActionPhase.Scheduled ? remaining : null);
            if (!window.IsVisible) window.Show();
        }
        else window.Hide();
    }

    private void Cancel()
    {
        if (scheduler.State.Pending is { } item) scheduler.Cancel(item.Id);
    }

    public void Dispose()
    {
        if (disposed) return;
        disposed = true;
        scheduler.Activity.Published -= OnNotice;
        timer.Stop();
        window.Close();
    }
}
