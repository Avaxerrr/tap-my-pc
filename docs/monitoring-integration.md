# Hardware monitoring

TapMyPC Android shows the selected PC's hardware readings in the **Stats** tab. On Windows, run PC Stats Tray 0.7.1 or newer and choose **Show Stats → Local apps**. The network option, **Show Stats → Apps + Dashboard** in PC Stats Tray 0.7.2, also works and makes the standalone dashboard available on the network.

On TapMyPC Desktop, open **Configure → Hardware monitoring** below **Remote access**. The card shows **Receiving stats** or **Stats out of date** with the last sample time. **Stats unavailable** includes a reminder to enable **Show Stats → Local apps** in PC Stats Tray. TapMyPC checks the local source while the Configure drawer is visible.

## Data flow

PC Stats Tray refreshes the sensors at its configured 1-, 2-, or 5-second interval. Its dashboard and TapMyPC share the cached `/api/metrics` snapshot. TapMyPC reads that endpoint at `http://127.0.0.1:4587/api/metrics` using PC Stats Tray's default port. TapMyPC Desktop serves the data at its authenticated `/api/v1/monitoring` route over the same pinned HTTPS connection as the remote controls.

The Stats tab opens with the same default metric selection as the standalone dashboard. **Show all** includes the rest of the metrics reported by the collector. Android polls at the reported interval while Stats is open and the app is in the foreground. It shows the sample timestamp, labels old readings as **Last known stats**, and shows setup guidance when no readings are available.

PC Stats Tray owns sensor permissions and can run independently. Monitoring availability is per PC and does not determine whether the phone is connected to TapMyPC.

[API contract](api.md#monitoring) · [Setup](setup.md)
