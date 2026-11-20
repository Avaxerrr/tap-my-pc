import 'package:flutter/material.dart';

import '../connection.dart';
import 'network_address_editor.dart';

const _connectionModes = [
  (
    id: 'auto',
    title: 'Automatic',
    description:
        'Local network → Tailscale → Bluetooth. No commands are resent.',
  ),
  (
    id: 'local',
    title: 'Local network only',
    description: 'Stay on your home or office network.',
  ),
  (
    id: 'tailscale',
    title: 'Tailscale only',
    description: 'Stay on Tailscale; no local or Bluetooth fallback.',
  ),
  (
    id: 'bluetooth',
    title: 'Bluetooth only',
    description: 'Use Bluetooth without the local network.',
  ),
];

class ConnectionSettingsDialog extends StatefulWidget {
  final PcProfile Function() readProfile;
  final String? Function() readTransport;
  final Future<String?> Function(
    PcProfile profile,
    String endpoint, {
    String? modeAfterSave,
  })
  onSaveAddress;
  final Future<void> Function() onOpenBluetoothSettings;

  const ConnectionSettingsDialog({
    super.key,
    required this.readProfile,
    required this.readTransport,
    required this.onSaveAddress,
    required this.onOpenBluetoothSettings,
  });

  @override
  State<ConnectionSettingsDialog> createState() =>
      _ConnectionSettingsDialogState();
}

class _ConnectionSettingsDialogState extends State<ConnectionSettingsDialog> {
  bool addressSaved = false;

  Future<void> editAddress(
    PcProfile profile, {
    required bool tailscale,
    String? modeAfterSave,
  }) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => NetworkAddressEditor(
        profile: profile,
        tailscale: tailscale,
        onSave: (endpoint) => widget.onSaveAddress(
          profile,
          endpoint,
          modeAfterSave: modeAfterSave,
        ),
      ),
    );
    if (mounted && saved == true) {
      setState(() => addressSaved = true);
    }
  }

  void chooseMode(PcProfile profile, String mode) {
    if (mode == 'tailscale' && profile.tailscaleEndpoint == null) {
      editAddress(profile, tailscale: true, modeAfterSave: mode);
    } else {
      Navigator.pop(context, mode);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.readProfile();
    final transport = widget.readTransport() ?? 'Disconnected';
    final local = profile.localEndpoint;
    final tailscale = profile.tailscaleEndpoint;
    return AlertDialog(
      title: Text('Connection for ${profile.name}'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Current: $transport'),
              if (addressSaved) const Text('Address saved.'),
              const SizedBox(height: 12),
              for (final mode in _connectionModes)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(mode.title),
                  subtitle: Text(mode.description),
                  trailing: profile.connectionMode == mode.id
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => chooseMode(profile, mode.id),
                ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Local network address'),
                subtitle: Text(
                  local == null
                      ? 'Discovered automatically when nearby'
                      : endpointHost(local),
                ),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () => editAddress(profile, tailscale: false),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Tailscale address'),
                subtitle: Text(
                  tailscale == null
                      ? 'Set up remote access'
                      : endpointHost(tailscale),
                ),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () => editAddress(profile, tailscale: true),
              ),
              if (profile.bluetoothAddress == null)
                const Text(
                  'Connect over a network once to save this PC’s Bluetooth connection.',
                ),
              TextButton(
                onPressed: widget.onOpenBluetoothSettings,
                child: const Text('Phone Bluetooth settings'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Back'),
        ),
      ],
    );
  }
}

class ConnectionHelpDialog extends StatelessWidget {
  const ConnectionHelpDialog({super.key});

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('How connections work'),
    content: const SingleChildScrollView(
      child: Text(
        'Pair once: open TapMyPC on your PC and scan its temporary QR. '
        'The QR hides after pairing.\n\n'
        'Normal use: open both apps. This phone looks for your saved PCs, '
        'verifies their certificates, and reconnects without another code. '
        'Each PC has its own pairing.\n\n'
        'Stop connections on the PC pauses access and stays stopped after '
        'restart. Start connections to resume.\n\n'
        'Use the PC selector to switch. Commands always target the named PC. '
        'Discovery never grants access.\n\n'
        'First pairing needs a reachable network address. In Connection '
        'settings, Automatic tries local network, then Tailscale, then '
        'Bluetooth. The three Only modes stay on the chosen route. '
        'Commands are never resent across connections.\n\n'
        'For remote access, connect Tailscale on both devices and enable '
        'Allow access through Tailscale on the PC. Your phone learns the '
        'address when it connects. You can also enter just the Tailscale IP; '
        'the existing port is reused. Local and Tailscale addresses are saved '
        'separately.\n\n'
        'Bluetooth can work nearby even without the same Wi-Fi. '
        'Allow Nearby devices and complete system Bluetooth pairing if '
        'prompted. The PC must be awake and running TapMyPC',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Got it'),
      ),
    ],
  );
}
