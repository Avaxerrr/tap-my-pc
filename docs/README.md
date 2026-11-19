# Documentation index

| Document | Purpose |
| --- | --- |
| [Product scope](product-scope.md) | User goals, controls, priorities, and expected behavior |
| [Architecture](architecture.md) | Project boundaries, dependencies, communication, and code organization |
| [Implementation plan](implementation-plan.md) | Delivery phases, verification, and unresolved implementation choices |
| [Setup](setup.md) | Build, launch, phone connection, certificate/firewall setup, simulator, and limitations |
| [API contract](api.md) | Versioned routes, authentication, payloads, errors, and Flutter integration |
| [Tailscale remote access](tailscale.md) | Remote access alongside the local listener, Android route selection, and firewall setup |
| [Bluetooth](bluetooth.md) | Secondary RFCOMM connection, transport selection, authentication, and hardware tests |
| [Mobile connections](mobile-connections.md) | Implemented QR pairing, discovery, persistent trust, certificate renewal/recovery, multi-PC profiles, and network limits |
| [Wake-on-LAN setup](setup.md#android-wake-on-lan) | Android wake settings and use on the PC’s local network |
| [Remote wake investigation](wake-investigation.md) | Closed laptop Wi-Fi investigation and desktop wake test status |
| [Monitoring integration](monitoring-integration.md) | Planned PC Stats Tray bridge, Android monitoring, and standalone website preservation |
| [Versioning](versioning.md) | Automatic version/build decisions, component ownership, and release verification |
| [Verification](verification.md) | Checks performed and remaining device testing |
| [Action feedback](action-feedback.md) | Command progress, PC overlays, native volume keys, and UX behavior |
| [AGENTS.md](../AGENTS.md) | Minimal durable guidance for agents working in this repository |

These documents describe the current prototype and planned extensions. The API contract records implemented routes. Future controls and phases remain plans. Update the appropriate document when a decision changes rather than expanding AGENTS.md with feature details.