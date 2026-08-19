class AppConfig {
  const AppConfig._();

  /// Assumption: demo is the safest default for emulator-first development.
  /// Run with --dart-define=DEMO_MODE=false when using physical hardware.
  static const bool demoMode = bool.fromEnvironment(
    'DEMO_MODE',
    defaultValue: true,
  );

  static const Duration connectionTimeout = Duration(seconds: 10);
}
