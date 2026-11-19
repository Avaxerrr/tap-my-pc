import 'package:flutter/material.dart';

import 'remote_desktop_preferences.dart';

class RemoteDesktopStreamOptions extends StatefulWidget {
  const RemoteDesktopStreamOptions({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  final RemoteDesktopStreamSettings settings;
  final ValueChanged<RemoteDesktopStreamSettings> onChanged;

  @override
  State<RemoteDesktopStreamOptions> createState() =>
      _RemoteDesktopStreamOptionsState();
}

class _RemoteDesktopStreamOptionsState
    extends State<RemoteDesktopStreamOptions> {
  late var settings = widget.settings;
  final _advanced = ExpansibleController();

  @override
  void dispose() {
    _advanced.dispose();
    super.dispose();
  }

  void _apply(RemoteDesktopStreamSettings next) {
    setState(() => settings = next);
    widget.onChanged(next);
  }

  Widget _slider(
    String label,
    int level,
    ValueChanged<int> preview, {
    int minimum = 0,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('$label  $level/9'),
      Slider(
        value: level.toDouble(),
        min: minimum.toDouble(),
        max: 9,
        divisions: 9 - minimum,
        label: '$level',
        semanticFormatterCallback: (value) =>
            '$label ${value.round()} out of 9',
        onChanged: (value) => preview(value.round()),
        onChangeEnd: (_) => widget.onChanged(settings),
      ),
    ],
  );

  Widget _dropdown<T>(
    String label,
    T selected,
    Iterable<T> choices,
    String Function(T) name,
    ValueChanged<T> select, {
    String Function(T)? selectedName,
  }) => InputDecorator(
    decoration: InputDecoration(
      labelText: label,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        isExpanded: true,
        isDense: true,
        itemHeight: null,
        value: selected,
        selectedItemBuilder: (context) => [
          for (final choice in choices)
            Text(
              (selectedName ?? name)(choice),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
        items: [
          for (final choice in choices)
            DropdownMenuItem(
              value: choice,
              child: Container(
                alignment: Alignment.centerLeft,
                constraints: const BoxConstraints(
                  minHeight: kMinInteractiveDimension,
                ),
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(name(choice)),
              ),
            ),
        ],
        onChanged: (value) {
          if (value != null) select(value);
        },
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final encoding = settings.encoding;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Image quality', style: text.titleMedium),
        const SizedBox(height: 16),
        _dropdown(
          'Preferred encoding',
          encoding,
          RemoteDesktopEncoding.values,
          (choice) => choice.displayName,
          (choice) => _apply(settings.copyWith(encoding: choice)),
          selectedName: (choice) => choice.label,
        ),
        if (encoding.usesJpeg) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in RemoteDesktopQuality.values)
                ChoiceChip(
                  label: Text(preset.label),
                  selected: settings.preset == preset,
                  onSelected: (_) {
                    _apply(settings.applyPreset(preset));
                    if (preset == RemoteDesktopQuality.custom) {
                      _advanced.expand();
                    }
                  },
                ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        ExpansionTile(
          controller: _advanced,
          initiallyExpanded: settings.preset == RemoteDesktopQuality.custom,
          maintainState: true,
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(top: 12, bottom: 10),
          title: const Text('Advanced stream settings'),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (encoding.usesJpeg) ...[
              _slider('JPEG quality', settings.quality, (level) {
                setState(
                  () => settings = settings.copyWith(
                    preset: RemoteDesktopQuality.custom,
                    quality: level,
                  ),
                );
              }),
              const SizedBox(height: 12),
            ],
            if (encoding.usesCompressionLevel) ...[
              _slider(
                'Compression level',
                settings.compression,
                (level) {
                  setState(
                    () => settings = settings.copyWith(
                      preset: RemoteDesktopQuality.custom,
                      compression: level,
                    ),
                  );
                },
                minimum: encoding.minimumCompression,
              ),
              const SizedBox(height: 12),
            ],
            _dropdown(
              'Server-side stream scale',
              settings.divisor,
              [1, 2, 3, 4],
              (divisor) => divisor == 1
                  ? 'Original resolution'
                  : '1/$divisor width and height',
              (divisor) => _apply(settings.copyWith(divisor: divisor)),
            ),
            const SizedBox(height: 8),
            Text(
              'Stream details shows the received size.',
              style: text.bodySmall,
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () => _apply(const RemoteDesktopStreamSettings()),
              icon: const Icon(Icons.restart_alt),
              label: const Text('Reset stream settings'),
            ),
          ],
        ),
      ],
    );
  }
}
