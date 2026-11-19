import 'package:flutter/material.dart';

import '../connection.dart';
import '../wake_on_lan.dart';

class WakeOnLanEditor extends StatefulWidget {
  final PcProfile profile;
  const WakeOnLanEditor({super.key, required this.profile});

  @override
  State<WakeOnLanEditor> createState() => _WakeOnLanEditorState();
}

class _WakeOnLanEditorState extends State<WakeOnLanEditor> {
  late final initial = widget.profile.effectiveWakeOnLan;
  late String mac = initial?.mac ?? '';
  late String destination = initial?.destination ?? '255.255.255.255';
  late String port = (initial?.port ?? 9).toString();
  FormatException? error;

  void save() {
    try {
      final settings = WakeOnLanSettings.parse(mac, destination, port);
      Navigator.pop(context, (
        settings: settings == widget.profile.automaticWakeOnLan
            ? null
            : settings,
      ));
    } on FormatException catch (e) {
      setState(() => error = e);
    }
  }

  InputDecoration decoration(String label, String field, {String? hint}) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        errorText: error?.source == field ? error?.message : null,
        errorMaxLines: 2,
      );

  void clearError(String field) {
    if (error?.source == field) setState(() => error = null);
  }

  @override
  Widget build(BuildContext context) {
    final automatic = widget.profile.automaticWakeOnLan != null;
    final manual = widget.profile.wakeOnLan != null;
    final description = manual
        ? 'Using custom settings for ${widget.profile.name}.'
        : automatic
        ? 'Detected from ${widget.profile.name}. Edit to override.'
        : 'Enter the PC’s network adapter details to wake it over local Wi-Fi.';
    return AlertDialog(
      title: const Text('Wake-on-LAN'),
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(description),
            const SizedBox(height: 20),
            TextFormField(
              initialValue: mac,
              textInputAction: TextInputAction.next,
              autocorrect: false,
              enableSuggestions: false,
              decoration: decoration(
                'PC MAC address',
                'mac',
                hint: '02:12:34:56:78:9A',
              ),
              onChanged: (value) {
                mac = value;
                clearError('mac');
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              initialValue: destination,
              textInputAction: TextInputAction.next,
              keyboardType: TextInputType.url,
              autocorrect: false,
              enableSuggestions: false,
              decoration: decoration('Destination IPv4', 'destination'),
              onChanged: (value) {
                destination = value;
                clearError('destination');
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              initialValue: port,
              textInputAction: TextInputAction.done,
              keyboardType: TextInputType.number,
              decoration: decoration('UDP port', 'port'),
              onChanged: (value) {
                port = value;
                clearError('port');
              },
              onFieldSubmitted: (_) => save(),
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      actions: [
        if (manual)
          TextButton(
            onPressed: () => Navigator.pop(context, (settings: null)),
            child: Text(automatic ? 'Use automatic' : 'Remove'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: save, child: const Text('Save')),
      ],
    );
  }
}
