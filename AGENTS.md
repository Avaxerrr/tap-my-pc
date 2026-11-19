# Project essentials

- TapMyPC is a local-network remote for a Windows PC, with browser and Flutter Android clients. iOS is deferred. Android supports Wi-Fi and Bluetooth RFCOMM with the same pinned HTTPS authentication.
- Use C# with WPF/MVVM for the Windows tray/settings app. Host the command API and prototype website in the same process.
- Keep feature behavior, Windows-specific implementations, API transport, and WPF presentation separate. UI and endpoints must not implement Windows operations directly.
- Keep the API independent of the prototype UI so Flutter can reuse it. The PC owns timers and persistent settings. Authenticate remote commands; do not force-close applications by default.
- Keep the implementation modular and proportional to this small project. No speculative plugin framework or unnecessary abstraction layers.
- Select the active network IP automatically; localhost is an Advanced debugging override. Keep command feedback visible on both clients and PC, with silent non-modal notifications that do not steal focus.
- Before relevant work, read [architecture](docs/architecture.md), [product scope](docs/product-scope.md), and [implementation plan](docs/implementation-plan.md). The [documentation index](docs/README.md) describes their purpose.
- Follow [versioning guidelines](docs/versioning.md) automatically when delivering app changes; keep desktop and mobile versions independent unless coordinating a release.
- After building a verified TapMyPC Android app APK, automatically install it in place on the owner's connected phone (ADB serial `a8c1d7b2`) and verify the installed version. See [Android delivery](docs/versioning.md#delivery-workflow).
- Update the relevant docs when scope, architecture, or command behavior changes. Keep this file limited to durable essentials and links.
