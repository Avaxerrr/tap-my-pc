# TapMyPC

*Your PC, a tap away.*

A personal Windows PC remote for controlling audio, media, displays, and power from bed.

The planned Windows host uses C# and WPF. A phone-friendly website will be the first client; a Flutter Android/iOS app will follow. Communication starts over the home Wi-Fi network, with Bluetooth deferred.

The prototype includes a frameless WPF tray/dashboard host, automatic network-address selection, authenticated HTTPS API, a responsive web remote, and command feedback with PC notifications and countdowns. Flutter and Bluetooth remain future work.

## Run

Requires Windows and the .NET 10 SDK for development.

```powershell
dotnet build TapMyPC.sln -c Release -m:1
dotnet test TapMyPC.sln -c Release -m:1
dotnet run --project src/TapMyPC.Desktop -c Release
```

Normal launch opens the dashboard with the listener stopped and the network IP selected automatically. Start the host when ready. Localhost, port overrides, certificates, and paired-device management are under Advanced settings. Read [setup](docs/setup.md) for phone pairing, HTTPS, firewall details, and applying staged updates.

For development without changing any actual PC controls, use the [simulator](docs/setup.md#simulator).

See the [documentation index](docs/README.md) for scope, architecture, and the implementation sequence. Project-wide coding guidance is in [AGENTS.md](AGENTS.md).
