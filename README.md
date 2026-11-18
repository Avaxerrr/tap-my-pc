# TapMyPC

*Your PC, a tap away.*

A personal Windows PC remote for controlling audio, media, displays, and power from bed.

The Windows host uses C# and WPF, with a responsive browser remote and a native Flutter Android client. Communication uses the local network; iOS and Bluetooth transport remain planned.

Current desktop/server development version: **0.3.2 (build 5)**. Android is **0.4.2 (build 6)**, with the desktop-matched dark design, grouped controls, saved accent themes, and a visible installed version. See [versioning guidelines](docs/versioning.md). The prototype includes a WPF tray/dashboard host, authenticated HTTPS API, audio output switching, approved app/website shortcuts, monitor controls, power timers, and command feedback. Android supports one-time QR pairing, protected saved profiles, automatic discovery/reconnection, and independent PC selection.

## Run

Requires Windows and the .NET 10 SDK for development.

```powershell
dotnet build TapMyPC.sln -c Release -m:1
dotnet test TapMyPC.sln -c Release -m:1
dotnet run --project src/TapMyPC.Desktop -c Release
```

Normal launch resumes connections on a Windows Private/Domain network unless previously paused. The initial QR appears automatically; scan it from Android Add PC to pair once. After pairing, the QR hides and saved PCs reconnect automatically when reachable. Stop connections persists across restarts; Add another phone creates a fresh QR. Localhost, port overrides, certificates, and paired-device management are under Advanced settings. Read [setup](docs/setup.md) for phone pairing, HTTPS, firewall details, and applying staged updates.

For Android build and device-test instructions, see [mobile setup](mobile/README.md). Both devices need a reachable local network; saved pairing cannot bypass AP isolation or enable internet access.

For development without changing any actual PC controls, use the [simulator](docs/setup.md#simulator).

See the [documentation index](docs/README.md) for scope, architecture, and the implementation sequence. Project-wide coding guidance is in [AGENTS.md](AGENTS.md).
