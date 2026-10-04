import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'session.dart';

const brandBlue = Color(0xFF1B4FD8);
const brandOrange = Color(0xFFFF7A1A);

/// خط Cairo متخزن كـ variable font، فلازم نحدد وزن الخط عن طريق محور 'wght'.
List<FontVariation> weightAxis(FontWeight w) => [FontVariation('wght', w.value.toDouble())];

extension TextWeight on TextStyle {
  TextStyle weight(FontWeight w) => copyWith(fontWeight: w, fontVariations: weightAxis(w));
  TextStyle get bold => weight(FontWeight.w700);
  TextStyle get semiBold => weight(FontWeight.w600);
}

TextTheme _cairo(TextTheme t) {
  TextStyle? f(TextStyle? s) =>
      s?.copyWith(fontFamily: 'Cairo', fontVariations: weightAxis(s.fontWeight ?? FontWeight.w400));
  return TextTheme(
    displayLarge: f(t.displayLarge),
    displayMedium: f(t.displayMedium),
    displaySmall: f(t.displaySmall),
    headlineLarge: f(t.headlineLarge),
    headlineMedium: f(t.headlineMedium),
    headlineSmall: f(t.headlineSmall),
    titleLarge: f(t.titleLarge),
    titleMedium: f(t.titleMedium),
    titleSmall: f(t.titleSmall),
    bodyLarge: f(t.bodyLarge),
    bodyMedium: f(t.bodyMedium),
    bodySmall: f(t.bodySmall),
    labelLarge: f(t.labelLarge),
    labelMedium: f(t.labelMedium),
    labelSmall: f(t.labelSmall),
  );
}

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: brandBlue,
    brightness: brightness,
    secondary: brandOrange,
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, fontFamily: 'Cairo');
  final text = _cairo(base.textTheme);
  return base.copyWith(
    textTheme: text,
    primaryTextTheme: _cairo(base.primaryTextTheme),
    scaffoldBackgroundColor: brightness == Brightness.light ? const Color(0xFFF5F7FB) : scheme.surface,
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: text.titleLarge?.bold.copyWith(color: scheme.onSurface),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLowest,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: text.labelLarge?.semiBold.copyWith(fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: text.labelLarge?.semiBold.copyWith(fontSize: 15),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => switch (ref.read(appConfigProvider).themeMode) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  Future<void> set(ThemeMode mode) async {
    state = mode;
    await ref.read(appConfigProvider).setThemeMode(mode.name);
  }
}
