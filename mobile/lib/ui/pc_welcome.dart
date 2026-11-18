import 'package:flutter/material.dart';
import 'app_theme.dart';

/// First connection: one task, with the action alongside its instructions.
class PcWelcome extends StatelessWidget {
  final VoidCallback? onAdd;
  final String message;
  const PcWelcome({super.key, required this.onAdd, required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.desktop_windows_outlined,
                            color: theme.colorScheme.onPrimaryContainer,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            'Connect your PC',
                            style: theme.textTheme.titleLarge,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Sound, screens, and power. All from your phone.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.secondary,
                      ),
                    ),
                    const Divider(height: 40),
                    const _SetupStep(
                      number: '1',
                      title: 'Open TapMyPC on your PC',
                      detail: 'Connect both devices to the same local network.',
                    ),
                    const SizedBox(height: 20),
                    const _SetupStep(
                      number: '2',
                      title: 'Scan its pairing QR',
                      detail:
                          'Select Pair a Phone on the PC, then add it here.',
                    ),
                    const SizedBox(height: 28),
                    FilledButton.icon(
                      onPressed: onAdd,
                      icon: const Icon(Icons.qr_code_scanner, size: 20),
                      label: const Text('Add your PC'),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Pair once. Reconnect over Wi-Fi or Bluetooth.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            if (message.isNotEmpty &&
                message != 'Add your first PC to get started.')
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    message,
                    key: const Key('connection-status'),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SetupStep extends StatelessWidget {
  final String number, title, detail;
  const _SetupStep({
    required this.number,
    required this.title,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.elevated,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(
          number,
          style: const TextStyle(fontSize: 12, color: AppColors.secondary),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 5),
            Text(detail, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    ],
  );
}
