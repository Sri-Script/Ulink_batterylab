class AppConfig {
  const AppConfig._();

  /// Assumption: demo is the safest default for emulator-first development.
  /// Run with --dart-define=DEMO_MODE=false when using physical hardware.
  static const bool demoMode = bool.fromEnvironment(
    'DEMO_MODE',
    defaultValue: true,
  );

  static const Duration connectionTimeout = Duration(seconds: 10);
  static const Duration bleScanTimeout = Duration(seconds: 12);

  /// Startup services are best-effort. Never leave the user on the splash
  /// screen indefinitely when a platform service is unavailable.
  static const Duration splashMaxWait = Duration(seconds: 5);

  /// Enable with --dart-define=BLE_SCAN_DIAGNOSTICS=true while validating
  /// firmware advertising names and service UUIDs. Debug builds only log it.
  static const bool bleScanDiagnostics = bool.fromEnvironment(
    'BLE_SCAN_DIAGNOSTICS',
    defaultValue: false,
  );

  /// A BLE peripheral in deep sleep only listens during its own periodic
  /// advertising bursts — the phone can't push a wake signal to it. This is
  /// the bounded window we keep re-scanning for before giving up.
  static const Duration bleWakeRetryWindow = Duration(seconds: 60);
}
