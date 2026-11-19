import 'package:flutter/material.dart';
import '../connection.dart';

class NetworkAddressEditor extends StatefulWidget {
  final PcProfile profile;
  final bool tailscale;
  const NetworkAddressEditor({
    super.key,
    required this.profile,
    required this.tailscale,
  });
  @override
  State<NetworkAddressEditor> createState() => _NetworkAddressEditorState();
}

class _NetworkAddressEditorState extends State<NetworkAddressEditor> {
  late String address, port;
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

  void save() {
    try {
      final endpoint = configuredNetworkAddress(
        address,
        widget.profile,
        tailscale: widget.tailscale,
        port: port,
      );
      Navigator.pop(context, endpoint);
    } on FormatException catch (e) {
      setState(() => error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.tailscale ? 'Tailscale address' : 'Local network address',
    ),
    content: SizedBox(
      width: 360,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.tailscale
                  ? 'Turn on Tailscale on both devices and enable it in the PC app. Enter the PC’s 100.x IP.'
                  : 'Usually discovered automatically. Enter the local IP shown on the PC if discovery cannot find it.',
            ),
            const SizedBox(height: 16),
            TextFormField(
              initialValue: address,
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
              tilePadding: EdgeInsets.zero,
              title: const Text('Advanced'),
              children: [
                TextFormField(
                  initialValue: port,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'TapMyPC port',
                    helperText:
                        'Change only if you changed the port on the PC.',
                  ),
                  onChanged: (value) => port = value,
                ),
              ],
            ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: save, child: const Text('Verify and save')),
    ],
  );
}
