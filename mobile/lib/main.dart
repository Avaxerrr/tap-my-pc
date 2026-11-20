import 'dart:async';

import 'package:flutter/material.dart';

import 'about_licenses.dart';
import 'home_screen.dart';
import 'ui/app_theme.dart';
import 'ui/remote_page.dart';

export 'ui/remote_page.dart' show RemotePage;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  registerBundledLicenses();
  runApp(const TapMyPcApp());
}

@pragma('vm:entry-point')
Future<void> homeActionMain(List<String> arguments) => runHomeAction(arguments);

class TapMyPcApp extends StatefulWidget {
  const TapMyPcApp({super.key});
  @override
  State<TapMyPcApp> createState() => _TapMyPcAppState();
}

class _TapMyPcAppState extends State<TapMyPcApp> with WidgetsBindingObserver {
  final appearance = AppearanceController();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(appearance.load());
  }

  @override
  void didChangeAccessibilityFeatures() => setState(() {});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: appearance,
    builder: (context, _) => AppearanceScope(
      controller: appearance,
      child: MaterialApp(
        title: 'TapMyPC',
        debugShowCheckedModeBanner: false,
        theme: appTheme(appearance.palette),
        themeAnimationDuration:
            WidgetsBinding
                .instance
                .platformDispatcher
                .accessibilityFeatures
                .disableAnimations
            ? Duration.zero
            : const Duration(milliseconds: 180),
        home: const RemotePage(),
      ),
    ),
  );
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    appearance.dispose();
    super.dispose();
  }
}
