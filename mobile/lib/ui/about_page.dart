import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'connection_dialogs.dart';
import 'widgets.dart';

Future<void> showAboutPage(
  BuildContext context, {
  required String appVersion,
  required String? hostVersion,
}) => showAppSheet<void>(
  context,
  title: 'About TapMyPC',
  child: _AboutContent(appVersion: appVersion, hostVersion: hostVersion),
);

class _AboutContent extends StatefulWidget {
  const _AboutContent({required this.appVersion, required this.hostVersion});

  final String appVersion;
  final String? hostVersion;

  @override
  State<_AboutContent> createState() => _AboutContentState();
}

class _AboutContentState extends State<_AboutContent> {
  String? message;

  String get appVersion => widget.appVersion.startsWith('v')
      ? widget.appVersion.substring(1)
      : widget.appVersion;

  String? get hostVersion {
    final version = widget.hostVersion?.trim();
    if (version == null || version.isEmpty) return null;
    final parts = version.split('+');
    return parts.length == 2 ? '${parts[0]} (build ${parts[1]})' : version;
  }

  Future<void> copyVersions() async {
    final host = hostVersion;
    final lines = [
      if (appVersion.isNotEmpty && appVersion != 'Version unavailable')
        'TapMyPC Android app: $appVersion',
      if (host != null) 'TapMyPC PC host: $host',
    ];
    try {
      await Clipboard.setData(ClipboardData(text: lines.join('\n')));
      report('Version info copied.');
    } on PlatformException {
      report('Could not copy version info. Try again.');
    }
  }

  Future<void> openGithubLink(String method, String label) async {
    try {
      await const MethodChannel('dev.tapmypc/app').invokeMethod<void>(method);
    } on PlatformException {
      report('Could not open the $label.');
    } on MissingPluginException {
      report('Could not open the $label.');
    }
  }

  void report(String text) {
    if (mounted) setState(() => message = text);
  }

  @override
  Widget build(BuildContext context) {
    final host = hostVersion;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Control your Windows PC from your phone.'),
        const SizedBox(height: 20),
        Text('Android app', style: textTheme.bodySmall),
        Text(
          appVersion.isEmpty ? 'Reading installed version…' : appVersion,
          key: const Key('about-version'),
        ),
        if (host != null) ...[
          const SizedBox(height: 12),
          Text('PC host', style: textTheme.bodySmall),
          Text(host),
        ],
        const Divider(height: 28),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.copy_outlined),
          title: const Text('Copy version info'),
          onTap:
              host != null ||
                  (appVersion.isNotEmpty && appVersion != 'Version unavailable')
              ? copyVersions
              : null,
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.help_outline),
          title: const Text('Setup guide'),
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => const ConnectionHelpDialog(title: 'Setup guide'),
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.description_outlined),
          title: const Text('Third-party licenses'),
          onTap: () => showLicensePage(
            context: context,
            applicationName: 'TapMyPC',
            applicationVersion: appVersion,
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.code),
          title: const Text('GitHub repository'),
          trailing: const Icon(Icons.open_in_new, size: 18),
          onTap: () => openGithubLink('openRepository', 'GitHub repository'),
        ),
        const Divider(height: 24),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () =>
                openGithubLink('openDeveloperProfile', 'GitHub profile'),
            child: const Text('Developed by @Avaxerrr'),
          ),
        ),
        if (message case final text?)
          Semantics(liveRegion: true, child: Text(text)),
      ],
    );
  }
}
