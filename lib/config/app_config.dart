class AppConfig {
  const AppConfig._();

  /// Assumption: demo is the safest default for emulator-first development.
  /// Run with --dart-define=DEMO_MODE=false when using physical hardware.
  static const bool demoMode = bool.fromEnvironment(
    'DEMO_MODE',
    defaultValue: true,
  );

  static const Duration connectionTimeout = Duration(seconds: 10);

  /// A BLE peripheral in deep sleep only listens during its own periodic
  /// advertising bursts — the phone can't push a wake signal to it. This is
  /// the bounded window we keep re-scanning for before giving up.
  static const Duration bleWakeRetryWindow = Duration(seconds: 60);
}