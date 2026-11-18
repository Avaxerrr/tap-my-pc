import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract final class AppColors {
  static const background = Color(0xff0b0c0e);
  static const surface = Color(0xff16181d);
  static const elevated = Color(0xff1c1f26);
  static const subtle = Color(0xff262a34);
  static const border = Color(0xff2d323d);
  static const text = Color(0xfff5f5f7);
  static const secondary = Color(0xffa5a8b1);
  static const error = Color(0xffffb4ab);
}

class AccentPalette {
  final String name;
  final Color fill, soft, text, foreground;
  const AccentPalette(
    this.name,
    this.fill,
    this.soft,
    this.text,
    this.foreground,
  );
  static const choices = [
    AccentPalette(
      'Blue',
      Color(0xff0875df),
      Color(0xff122338),
      Color(0xff8ec6ff),
      Colors.white,
    ),
    AccentPalette(
      'Mint',
      Color(0xffb8e593),
      Color(0xff1c2b20),
      Color(0xffc8edac),
      Color(0xff132110),
    ),
    AccentPalette(
      'Purple',
      Color(0xffac8cff),
      Color(0xff261f38),
      Color(0xffc8b3ff),
      Color(0xff1b102d),
    ),
    AccentPalette(
      'Teal',
      Color(0xff42d3c4),
      Color(0xff142c2b),
      Color(0xff8be4da),
      Color(0xff092523),
    ),
    AccentPalette(
      'Amber',
      Color(0xfff0b454),
      Color(0xff302719),
      Color(0xfff5cb86),
      Color(0xff291b07),
    ),
  ];
}

class AppearanceController extends ChangeNotifier {
  static const storageKey = 'tapmypc.appearance.v1';
  final FlutterSecureStorage storage;
  AppearanceController([this.storage = const FlutterSecureStorage()]);
  AccentPalette palette = AccentPalette.choices.first;

  String error = '';
  int _revision = 0;
  bool _disposed = false;
  Future<void> _pending = Future.value();

  Future<void> load() async {
    final revision = _revision;
    try {
      final raw = await storage.read(key: storageKey);
      if (_disposed || revision != _revision || raw == null) return;
      final saved = jsonDecode(raw) as Map;
      palette =
          AccentPalette.choices
              .where((p) => p.name == saved['accent'])
              .firstOrNull ??
          AccentPalette.choices.first;
    } catch (_) {
      if (!_disposed) {
        error =
            'Appearance could not be loaded. Your saved PCs are unaffected.';
      }
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> setAccent(AccentPalette value) {
    palette = value;
    return _save();
  }

  Future<void> _save() {
    _revision++;
    error = '';
    final value = jsonEncode({'accent': palette.name});
    notifyListeners();
    _pending = _pending.then((_) async {
      try {
        await storage.write(key: storageKey, value: value);
      } catch (_) {
        if (!_disposed) {
          error = 'Preview applied, but appearance could not be saved.';
          notifyListeners();
        }
      }
    });
    return _pending;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class AppearanceScope extends InheritedNotifier<AppearanceController> {
  const AppearanceScope({
    super.key,
    required AppearanceController controller,
    required super.child,
  }) : super(notifier: controller);
  static AppearanceController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppearanceScope>()!.notifier!;
}

ThemeData appTheme(AccentPalette palette) {
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(8));
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    fontFamily: 'Inter',
  );
  final scheme = ColorScheme.dark(
    primary: palette.fill,
    onPrimary: palette.foreground,
    primaryContainer: palette.soft,
    onPrimaryContainer: palette.text,
    secondary: palette.fill,
    onSecondary: palette.foreground,
    surface: AppColors.surface,
    onSurface: AppColors.text,
    onSurfaceVariant: AppColors.secondary,
    outline: AppColors.border,
    error: AppColors.error,
    onError: const Color(0xff3b1416),
  );
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    textTheme: base.textTheme
        .copyWith(
          headlineMedium: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.8,
          ),
          titleLarge: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.4,
          ),
          titleMedium: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          bodyMedium: const TextStyle(fontSize: 13, height: 1.5),
          bodySmall: const TextStyle(
            fontSize: 11.5,
            height: 1.4,
            color: AppColors.secondary,
          ),
        )
        .apply(
          fontFamily: 'Inter',
          bodyColor: AppColors.text,
          displayColor: AppColors.text,
        ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      foregroundColor: AppColors.text,
      elevation: 0,
      centerTitle: false,
      titleSpacing: 20,
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: shape,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        textStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: shape,
        minimumSize: const Size(48, 48),
        foregroundColor: AppColors.text,
        backgroundColor: AppColors.elevated,
        side: const BorderSide(color: AppColors.border),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: shape,
        minimumSize: const Size(48, 48),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        shape: shape,
        minimumSize: const Size(48, 48),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.background,
      contentPadding: const EdgeInsets.all(14),
      labelStyle: const TextStyle(color: AppColors.secondary),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: palette.fill, width: 1.5),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      clipBehavior: Clip.antiAlias,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      elevation: 0,
      height: 72,
      indicatorColor: palette.soft,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? Colors.white
              : AppColors.secondary,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontFamily: 'Inter',
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? palette.text
              : AppColors.secondary,
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.elevated,
      contentTextStyle: const TextStyle(
        fontFamily: 'Inter',
        color: AppColors.text,
        fontSize: 13,
      ),
      shape: shape,
    ),
    sliderTheme: SliderThemeData(
      trackHeight: 4,
      activeTrackColor: palette.fill,
      inactiveTrackColor: AppColors.subtle,
      thumbColor: palette.fill,
      overlayColor: palette.fill.withValues(alpha: 0.12),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.border,
      thickness: 1,
      space: 24,
    ),
  );
}
