import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'connection.dart';
import 'phone_identity.dart';
import 'pairing_invitation.dart';
import 'ui/app_theme.dart';

class PairPage extends StatefulWidget {
  final PcProfile? recovering;
  const PairPage({super.key, this.recovering});
  @override
  State<PairPage> createState() => _PairPageState();
}

class _PairPageState extends State<PairPage> {
  final name = TextEditingController(),
      address = TextEditingController(),
      pin = TextEditingController(),
      code = TextEditingController();
  PairingInvitation? invitation;
  bool busy = false;
  String error = '';

  @override
  void initState() {
    super.initState();
    name.text = widget.recovering?.name ?? '';
    address.text = widget.recovering?.address ?? '';
  }

  Future<void> scan() async {
    final result = await Navigator.push<PairingInvitation>(
      context,
      MaterialPageRoute(builder: (_) => const ScanPairPage()),
    );
    if (!mounted || result == null) return;
    setState(() {
      invitation = result;
      error = '';
    });
  }

  Future<void> pair({bool qr = false}) async {
    setState(() {
      busy = true;
      error = '';
    });
    PcApi? client;
    try {
      PcProfile profile;
      if (qr) {
        profile = await invitation!.redeem();
      } else {
        final draft = PcProfile(
          name.text.trim(),
          address.text.trim(),
          normalizePin(pin.text),
          '',
        );
        if (draft.name.isEmpty) {
          throw const FormatException('Give this PC a name.');
        }
        client = PcApi(draft);
        final result = await client.request(
          '/pair',
          method: 'POST',
          body: {
            'name': await PhoneIdentity.name() ?? 'Android phone',
            'code': code.text.trim(),
          },
        );
        profile = client.verifiedProfile.withToken(result['token']);
      }
      if (!mounted) return;
      Navigator.pop(context, profile);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      client?.close();
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.recovering == null ? 'Add PC' : 'Re-pair selected PC'),
    ),
    body: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (widget.recovering != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Text(
                  'Replace the saved pairing for ${widget.recovering!.name}. Scan a fresh QR displayed by that PC. Other saved PCs stay unchanged.',
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.qr_code_scanner,
                  size: 28,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Scan. Pair. You’re in.',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            const Text(
              'Open Pair a Phone in the PC app, then scan its temporary QR here. Both devices need a reachable local network.',
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: busy ? null : scan,
              icon: const Icon(Icons.camera_alt_outlined),
              label: Text(
                invitation == null ? 'Scan PC QR' : 'Scan another QR',
              ),
            ),
            if (invitation != null)
              Card(
                margin: const EdgeInsets.symmetric(vertical: 20),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        invitation!.name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(invitation!.address),
                      const SizedBox(height: 12),
                      const Text(
                        'Pair only with a QR displayed by your PC. Its certificate will be verified before pairing.',
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: busy ? null : () => pair(qr: true),
                        child: Text(
                          busy
                              ? 'Pairing…'
                              : widget.recovering == null
                              ? 'Pair with this PC'
                              : 'Replace saved pairing',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (busy) const LinearProgressIndicator(),
            const SizedBox(height: 20),
            ExpansionTile(
              title: const Text(
                'Enter details manually',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: const BorderSide(color: AppColors.border),
              ),
              collapsedShape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: const BorderSide(color: AppColors.border),
              ),
              backgroundColor: AppColors.surface,
              collapsedBackgroundColor: AppColors.surface,
              childrenPadding: const EdgeInsets.all(16),
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Text(
                    'Copy the address and SHA-256 fingerprint from the PC’s Advanced settings, then generate a pairing code.',
                  ),
                ),
                for (final field in [
                  (name, 'PC name'),
                  (address, 'HTTPS address'),
                  (pin, 'SHA-256 fingerprint'),
                  (code, 'Pairing code'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: TextField(
                      controller: field.$1,
                      enabled: !busy,
                      autocorrect: false,
                      decoration: InputDecoration(labelText: field.$2),
                    ),
                  ),
                OutlinedButton(
                  onPressed: busy ? null : pair,
                  child: const Text('Pair manually'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  @override
  void dispose() {
    for (final c in [name, address, pin, code]) {
      c.dispose();
    }
    super.dispose();
  }
}

class ScanPairPage extends StatefulWidget {
  const ScanPairPage({super.key});
  @override
  State<ScanPairPage> createState() => _ScanPairPageState();
}

class _ScanPairPageState extends State<ScanPairPage>
    with WidgetsBindingObserver {
  final controller = MobileScannerController(formats: [BarcodeFormat.qrCode]);
  bool handled = false;
  String hint = 'Point the camera at the pairing QR on your PC.';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!controller.value.hasCameraPermission || handled) return;
    if (state == AppLifecycleState.resumed) {
      unawaited(controller.start());
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(controller.stop());
    }
  }

  void detected(BarcodeCapture capture) {
    if (handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;
      try {
        final invitation = PairingInvitation.parse(raw);
        handled = true;
        unawaited(controller.stop());
        Navigator.pop(context, invitation);
        return;
      } on FormatException catch (error) {
        setState(() => hint = error.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scan PC QR')),
    body: Column(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              MobileScanner(
                controller: controller,
                onDetect: detected,
                errorBuilder: (context, error) => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Camera unavailable. Allow camera access in Android settings, or go back and enter the PC details manually.',
                    ),
                  ),
                ),
              ),
              IgnorePointer(
                child: Center(
                  child: Container(
                    width: 240,
                    height: 240,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(padding: const EdgeInsets.all(24), child: Text(hint)),
        ),
      ],
    ),
  );
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(controller.dispose());
    super.dispose();
  }
}
