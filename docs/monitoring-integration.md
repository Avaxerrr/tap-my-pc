# Hardware monitoring integration — planned

Hardware monitoring is the next implementation as of November 18, 2026. Bluetooth secondary connectivity and the Android Wake-on-LAN sender are implemented. The laptop Wi-Fi wake investigation is closed for its current configuration. This supersedes the earlier monitoring deferral. The bridge and mobile monitoring screen remain unimplemented. See [wake investigation](wake-investigation.md) for the hardware findings.

## Existing project and goal

Source: C:\Users\Work\Documents\Coding Projects\Coding\HardwareMonitoring (PC Stats Tray).

Bring its hardware stats into the existing Android app while preserving PC Stats Tray as a standalone app, including its website, tray, desktop overlay, and optional RTSS output.

Reuse candidates in PCStatsTray include:
- Services/OverlayMetricCollector.cs: sensor collection/selection, currently coupled to OverlayConfig and formatted display values.
- Services/DashboardSnapshotBuilder.cs and DashboardMetricCatalog.cs.
- Models/DashboardSnapshot.cs.
- Services/LanDashboardServer.cs: read-only /api/metrics and /api/health.
- Sensor identities, fan classification, and existing tests.

The source uses .NET 10/WinForms and LibreHardwareMonitor-related binaries. Its manifest requests administrator privileges; TapMyPC currently runs as the invoking user.

## Proposed first integration

PC Stats Tray -> local snapshot bridge -> TapMyPC authenticated HTTPS API -> mobile app

Collect sensors once and reuse cached snapshots for all views. Phone connects only to its selected TapMyPC host. No integration has been implemented.

Keep PC Stats Tray and its existing website independent. Preserve its LAN-dashboard option and add a separate loopback-only bridge option, so integration neither requires another unauthenticated LAN endpoint nor removes the website. Constrain the bridge to the locally configured collector; do not expose arbitrary remote proxy URLs.

When the collector is closed or a sensor is missing, controls remain usable and monitoring reports unavailable/stale data with timestamps. Each PC has independent monitoring availability.

## Contract and reuse work

- Define numeric values, units, stable device/sensor IDs, collection timestamps, and unavailable states. Existing snapshots mostly contain formatted text.
- Reuse collection and sensor-selection logic/tests; do not copy the entire WinForms app or embed its website as the mobile UI.
- Serve cached samples without updating physical sensors for every request/client.
- Start with CPU/GPU temperatures and usage, RAM, storage, and network rates.
- Bound graph history and pause/reduce mobile updates when its screen is hidden.
- Avoid duplicate low-level collectors when both apps are running.
- Preserve upstream dependency notices.

## Optional later extraction

If the user wants TapMyPC to work without the separate collector app, adapt/extract a reusable sensor component later while keeping the original app intact.

Account for sensor permissions and driver/backend requirements without elevating the network-facing TapMyPC host. A narrowly scoped local collector/helper is an option to evaluate, not an implemented service.

No new collector, metrics endpoint, driver installation, shared-library extraction, merged app, or mobile monitoring screen is part of this documentation update.
