import 'package:flutter/material.dart';

import '../connection.dart';

class NetworkAddressEditor extends StatefulWidget {
  final PcProfile profile;
  final bool tailscale;
  final Future<String?> Function(String endpoint) onSave;

  const NetworkAddressEditor({
    super.key,
    required this.profile,
    required this.tailscale,
    required this.onSave,
  });

  @override
  State<NetworkAddressEditor> createState() => _NetworkAddressEditorState();
}

class _NetworkAddressEditorState extends State<NetworkAddressEditor> {
  final portField = GlobalKey();
  late String address, port;
  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    final saved = widget.tailscale
        ? widget.profile.tailscaleEndpoint
        : widget.profile.localEndpoint;
    address = saved == null ? '' : endpointHost(saved);
    port = Uri.parse(saved ?? widget.profile.address).port.toString();
  }

  Future<void> save() async {
    if (saving) return;
    final String endpoint;
    try {
      endpoint = configuredNetworkAddress(
        address,
        widget.profile,
        tailscale: widget.tailscale,
        port: port,
      );
    } on FormatException catch (e) {
      setState(() => error = e.message);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      saving = true;
      error = null;
    });
    final failure = await widget.onSave(endpoint);
    if (!mounted) return;
    if (failure == null) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        saving = false;
        error = failure;
      });
    }
  }

  void revealPort(bool expanded) {
    if (!expanded) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final field = portField.currentContext;
      if (field == null) return;
      Scrollable.ensureVisible(
        field,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: AlertDialog(
      title: Text(
        widget.tailscale ? 'Tailscale address' : 'Local network address',
      ),
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.tailscale
                  ? 'Enter the PC’s Tailscale IPv4 address.'
                  : 'Enter the IPv4 address shown in the PC app.',
            ),
            const SizedBox(height: 16),
            TextFormField(
              initialValue: address,
              enabled: !saving,
              keyboardType: TextInputType.url,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: widget.tailscale ? 'Tailscale IP' : 'Local IP',
                hintText: widget.tailscale ? '100.80.90.100' : '192.168.1.10',
              ),
              onChanged: (value) => address = value,
              onFieldSubmitted: (_) => save(),
            ),
            const SizedBox(height: 8),
            Text(
              'Port $port · uses the same TapMyPC port as your PC.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            ExpansionTile(
              expansionAnimationStyle: AnimationStyle.noAnimation,
              onExpansionChanged: revealPort,
              tilePadding: EdgeInsets.zero,
              title: const Text('Advanced'),
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: TextFormField(
                    key: portField,
                    initialValue: port,
                    enabled: !saving,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'TapMyPC port',
                      helperText: 'Use the port shown on the PC.',
                      helperMaxLines: 2,
                    ),
                    onChanged: (value) => port = value,
                    onFieldSubmitted: (_) => save(),
                  ),
                ),
              ],
            ),
            if (error != null)
              Semantics(
                liveRegion: true,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('Back'),
        ),
        FilledButton(
          onPressed: saving ? null : save,
          child: Text(saving ? 'Verifying…' : 'Verify and save'),
        ),
      ],
    ),
  );
}
