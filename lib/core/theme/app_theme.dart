import 'package:flutter/material.dart';

class UlinkThemeTokens extends ThemeExtension<UlinkThemeTokens> {
  const UlinkThemeTokens({
    required this.surfaceElevated,
    required this.textMuted,
    required this.success,
    required this.warning,
    required this.glow,
    required this.cardShadow,
    required this.primaryGradientStart,
    required this.primaryGradientEnd,
    required this.onPrimaryAction,
  });

  final Color surfaceElevated;
  final Color textMuted;
  final Color success;
  final Color warning;
  final Color glow;
  final Color cardShadow;
  final Color primaryGradientStart;
  final Color primaryGradientEnd;
  final Color onPrimaryAction;

  @override
  UlinkThemeTokens copyWith({
    Color? surfaceElevated,
    Color? textMuted,
    Color? success,
    Color? warning,
    Color? glow,
    Color? cardShadow,
    Color? primaryGradientStart,
    Color? primaryGradientEnd,
    Color? onPrimaryAction,
  }) => UlinkThemeTokens(
    surfaceElevated: surfaceElevated ?? this.surfaceElevated,
    textMuted: textMuted ?? this.textMuted,
    success: success ?? this.success,
    warning: warning ?? this.warning,
    glow: glow ?? this.glow,
    cardShadow: cardShadow ?? this.cardShadow,
    primaryGradientStart: primaryGradientStart ?? this.primaryGradientStart,
    primaryGradientEnd: primaryGradientEnd ?? this.primaryGradientEnd,
    onPrimaryAction: onPrimaryAction ?? this.onPrimaryAction,
  );

  @override
  UlinkThemeTokens lerp(UlinkThemeTokens? other, double t) {
    if (other is! UlinkThemeTokens) return this;
    return UlinkThemeTokens(
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      glow: Color.lerp(glow, other.glow, t)!,
      cardShadow: Color.lerp(cardShadow, other.cardShadow, t)!,
      primaryGradientStart: Color.lerp(primaryGradientStart, other.primaryGradientStart, t)!,
      primaryGradientEnd: Color.lerp(primaryGradientEnd, other.primaryGradientEnd, t)!,
      onPrimaryAction: Color.lerp(onPrimaryAction, other.onPrimaryAction, t)!,
    );
  }
}

abstract final class UlinkAppTheme {
  static ThemeData forBrightness(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final background = dark ? const Color(0xFF0B1218) : const Color(0xFFF4F7FA);
    final surface = dark ? const Color(0xFF121C26) : const Color(0xFFFFFFFF);
    final elevated = dark ? const Color(0xFF17232F) : const Color(0xFFFFFFFF);
    final border = dark ? const Color(0xFF1F3340) : const Color(0xFFE1E8EF);
    final primary = dark ? const Color(0xFF2DD4BF) : const Color(0xFF0FA394);
    final text = dark ? const Color(0xFFE6EDF3) : const Color(0xFF0F1B26);
    final muted = dark ? const Color(0xFF8CA0B3) : const Color(0xFF5B6F80);
    final danger = dark ? const Color(0xFFF87171) : const Color(0xFFDC2626);
    final tokens = UlinkThemeTokens(
      surfaceElevated: elevated,
      textMuted: muted,
      success: dark ? const Color(0xFF34D399) : const Color(0xFF059669),
      warning: dark ? const Color(0xFFF59E0B) : const Color(0xFFB45309),
      glow: dark ? primary.withValues(alpha: .15) : Colors.transparent,
      cardShadow: dark ? Colors.transparent : const Color(0x0D0F1B26),
      primaryGradientStart: const Color(0xFF12B3A2),
      primaryGradientEnd: const Color(0xFF0B8A7D),
      onPrimaryAction: dark ? const Color(0xFF0B1218) : Colors.white,
    );
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
    ).copyWith(
      primary: primary,
      onPrimary: dark ? const Color(0xFF0B1218) : Colors.white,
      secondary: primary,
      onSecondary: dark ? const Color(0xFF0B1218) : Colors.white,
      error: danger,
      onError: Colors.white,
      surface: surface,
      onSurface: text,
      surfaceContainerHighest: elevated,
      onSurfaceVariant: muted,
      outline: border,
      outlineVariant: border,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      extensions: [tokens],
      appBarTheme: AppBarTheme(backgroundColor: background, foregroundColor: text, elevation: 0),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: primary.withValues(alpha: dark ? .25 : .18),
        labelTextStyle: WidgetStatePropertyAll(TextStyle(color: muted, fontWeight: FontWeight.w600)),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(color: states.contains(WidgetState.selected) ? primary : muted)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: elevated,
        hintStyle: TextStyle(color: muted),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: border)),
      ),
      snackBarTheme: SnackBarThemeData(backgroundColor: elevated, contentTextStyle: TextStyle(color: text)),
      dividerColor: border,
    );
  }
}
