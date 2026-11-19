import 'dart:async';

import 'package:flutter/material.dart';

import '../connection.dart';
import 'widgets.dart';

class StatsPanel extends StatefulWidget {
  final PcApi? api;

  const StatsPanel({super.key, required this.api});

  @override
  State<StatsPanel> createState() => _StatsPanelState();
}

class _StatsPanelState extends State<StatsPanel> with WidgetsBindingObserver {
  Timer? _timer;
  int _generation = 0;
  bool _foreground = true;
  bool _showAll = false;
  bool _stale = false;
  String? _error;
  _StatsSnapshot? _snapshot;

  @override
  void initState() {
    super.initState();
    final binding = WidgetsBinding.instance;
    _foreground =
        binding.lifecycleState == null ||
        binding.lifecycleState == AppLifecycleState.resumed;
    binding.addObserver(this);
    unawaited(_poll());
  }

  @override
  void didUpdateWidget(covariant StatsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.api, oldWidget.api)) {
      _error = null;
      _restart();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (foreground == _foreground) return;
    _foreground = foreground;
    _restart();
  }

  void _restart() {
    _generation++;
    _timer?.cancel();
    unawaited(_poll());
  }

  Future<void> _poll() async {
    final client = widget.api;
    if (!_foreground || client == null) return;
    final generation = _generation;
    var interval = const Duration(seconds: 5);
    try {
      final response = await client.request('/monitoring') as Map;
      if (!mounted || generation != _generation) return;
      final data = response['snapshot'];
      final snapshot = data is Map ? _StatsSnapshot.fromJson(data) : null;
      setState(() {
        if (snapshot != null) _snapshot = snapshot;
        _stale = snapshot == null || response['stale'] == true;
        _error = snapshot == null
            ? 'Open PC Stats Tray on your PC and select Show Stats → Local apps.'
            : null;
      });
      if (snapshot != null) interval = snapshot.interval;
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _stale = true;
        _error = error is PcApiException && error.statusCode == 404
            ? 'Update TapMyPC on this PC to enable Stats.'
            : 'Could not refresh stats. Retrying while this tab is open.';
      });
    }
    _timer = Timer(interval, _poll);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final connected = widget.api != null;
    final description = !connected
        ? 'Connect to this PC to see its stats.'
        : _error;
    if (snapshot == null) {
      return SectionCard(
        title: 'PC stats',
        child: description == null
            ? const Row(
                children: [
                  SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Expanded(child: Text('Loading stats…')),
                ],
              )
            : Text(description),
      );
    }

    final groups = <String, List<_StatsMetric>>{};
    for (final metric in snapshot.metrics) {
      if (_showAll || metric.defaultVisible) {
        (groups[metric.group] ??= []).add(metric);
      }
    }

    final updated = snapshot.generatedAt.toLocal();
    final formatter = MaterialLocalizations.of(context);
    final date = formatter.formatShortDate(updated);
    final time = formatter.formatTimeOfDay(
      TimeOfDay.fromDateTime(updated),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    final stale = _stale || !connected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          title: stale ? 'Last known stats' : 'PC stats',
          subtitle: 'Updated $date at $time',
          trailing: TextButton(
            onPressed: () => setState(() => _showAll = !_showAll),
            child: Text(_showAll ? 'Default view' : 'Show all'),
          ),
          child: Text(
            description ??
                (stale
                    ? 'PC Stats Tray has not sent a recent sample.'
                    : _showAll
                    ? 'All available metrics'
                    : 'Default view'),
          ),
        ),
        if (groups.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No metrics in this view.'),
          ),
        for (final group in groups.entries)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: SectionCard(
              title: group.key,
              child: Column(
                children: [
                  for (final metric in group.value)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: _MetricRow(metric: metric),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _MetricRow extends StatelessWidget {
  final _StatsMetric metric;

  const _MetricRow({required this.metric});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(metric.label),
              if (metric.source.isNotEmpty &&
                  (metric.group == 'Storage' || metric.group == 'Network'))
                Text(metric.source, style: theme.bodySmall),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            metric.value,
            textAlign: TextAlign.end,
            style: theme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _StatsSnapshot {
  final DateTime generatedAt;
  final Duration interval;
  final List<_StatsMetric> metrics;

  _StatsSnapshot.fromJson(Map data)
    : generatedAt = DateTime.parse(data['generatedAtUtc'] as String),
      interval = Duration(
        milliseconds: switch (data['refreshIntervalMs']) {
          1000 => 1000,
          2000 => 2000,
          _ => 5000,
        },
      ),
      metrics = (data['metrics'] as List)
          .whereType<Map>()
          .map(_StatsMetric.fromJson)
          .toList();
}

class _StatsMetric {
  final String label, value, group, source;
  final bool defaultVisible;

  _StatsMetric.fromJson(Map data)
    : label = data['label'] as String,
      value = data['available'] == true
          ? data['value'] as String? ?? 'Unavailable'
          : 'Unavailable',
      group = data['group'] as String,
      source = data['sourceName'] as String? ?? '',
      defaultVisible = data['defaultVisible'] == true;
}
