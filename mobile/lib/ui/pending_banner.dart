import 'dart:async';
import 'package:flutter/material.dart';
import 'app_theme.dart';

class PendingActionBanner extends StatefulWidget {
  final Map<String, dynamic> pending;
  final String? serverTime;
  final String pcName;
  final VoidCallback? onCancel;
  const PendingActionBanner({
    super.key,
    required this.pending,
    required this.pcName,
    this.serverTime,
    this.onCancel,
  });
  @override
  State<PendingActionBanner> createState() => _PendingActionBannerState();
}

class _PendingActionBannerState extends State<PendingActionBanner>
    with WidgetsBindingObserver {
  Timer? timer;
  Duration offset = Duration.zero;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    sync();
    start();
  }

  void sync() {
    final server = DateTime.tryParse(widget.serverTime ?? '');
    if (server != null) offset = server.difference(DateTime.now());
  }

  void start() {
    timer?.cancel();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant PendingActionBanner old) {
    super.didUpdateWidget(old);
    if (old.serverTime != widget.serverTime) sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      start();
      setState(() {});
    } else {
      timer?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    final due = DateTime.tryParse(widget.pending['dueAt'] ?? '');
    final seconds = due?.difference(DateTime.now().add(offset)).inSeconds ?? 0;
    final label = seconds > 0
        ? '${seconds ~/ 60}m ${seconds % 60}s'
        : 'Request is due';
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('pending-action'),
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.schedule, color: scheme.onPrimaryContainer, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${widget.pending['action']} · $label',
                  style: TextStyle(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                Text(
                  widget.pcName,
                  style: const TextStyle(
                    color: AppColors.secondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          TextButton(
            key: const Key('cancel-pending'),
            onPressed: widget.onCancel,
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
