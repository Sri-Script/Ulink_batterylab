import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config/app_config.dart';
import 'providers/connection_controller.dart';
import 'screens/calibration_history_screen.dart';
import 'screens/design_mode_screen.dart';
import 'screens/live_data_viewer_screen.dart';
import 'screens/login_screen.dart';
import 'screens/scanner_screen.dart';
import 'screens/wifi_provisioning_screen.dart';
import 'services/app_telemetry_notification_controller.dart';
import 'services/local_notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BatteryLabApp());
}

class BatteryLabApp extends StatefulWidget {
  const BatteryLabApp({super.key});

  @override
  State<BatteryLabApp> createState() => _BatteryLabAppState();
}

class _BatteryLabAppState extends State<BatteryLabApp> {
  final _telemetryNotifications = AppTelemetryNotificationController();

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _telemetryNotifications.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => ConnectionController(),
    child: MaterialApp(
      title: 'BattMobile',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF2EC6D6),
          onPrimary: Color(0xFF102124),
          secondary: Color(0xFF2EC6D6),
          onSecondary: Color(0xFF102124),
          surface: Color(0xFF2D3033),
          onSurface: Color(0xFFE2E4E5),
          error: Color(0xFFFF5C68),
          onError: Color(0xFF250006),
        ),
        scaffoldBackgroundColor: const Color(0xFF1B1D1F),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Color(0xFF35383B),
          border: OutlineInputBorder(),
        ),
        cardTheme: const CardThemeData(
          margin: EdgeInsets.zero,
          color: Color(0xFF303336),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF242729),
          foregroundColor: Color(0xFFE2E4E5),
        ),
        dividerColor: const Color(0xFF4A4E51),
      ),
      home: _LaunchGate(onServicesReady: _telemetryNotifications.start),
    ),
  );
}

class _LaunchGate extends StatefulWidget {
  const _LaunchGate({required this.onServicesReady});

  final VoidCallback onServicesReady;

  @override
  State<_LaunchGate> createState() => _LaunchGateState();
}

class _LaunchGateState extends State<_LaunchGate> {
  static const _disclaimerAcknowledgedKey = 'disclaimer_acknowledged';
  bool? _showDisclaimer;
  bool _bluetoothNeedsAttention = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    var disclaimerAcknowledged = false;
    final loadDisclaimer = _loadDisclaimerAcknowledgement()
        .then((value) {
          disclaimerAcknowledged = value;
        })
        .catchError((_) {
          // Treat an unavailable preference store as a first launch.
        });

    await Future.wait<dynamic>([_initializeServices(), loadDisclaimer]).timeout(
      AppConfig.splashMaxWait,
      onTimeout: () {
        // Services continue in the background; the app remains usable.
        return const <dynamic>[];
      },
    );
    if (!disclaimerAcknowledged) {
      if (mounted) setState(() => _showDisclaimer = true);
      return;
    }
    await _openScanner();
  }

  Future<bool> _loadDisclaimerAcknowledgement() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_disclaimerAcknowledgedKey) == true;
  }

  Future<void> _initializeServices() async {
    try {
      await Firebase.initializeApp();
    } catch (_) {
      // Firebase is optional until an upload/login action needs it.
    }
    try {
      await LocalNotificationService.instance.initialize();
    } catch (_) {
      // Notifications are optional during startup and in widget tests.
    }
    widget.onServicesReady();
  }

  Future<void> _acknowledgeDisclaimer() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_disclaimerAcknowledgedKey, true);
    await _openScanner();
  }

  /// On Android, this asks the system to enable Bluetooth while the user is
  /// still in the launch flow. A declined request is deliberately non-fatal:
  /// ScannerScreen presents an inline retry action instead.
  Future<void> _openScanner() async {
    var needsAttention = false;
    if (!AppConfig.demoMode) {
      try {
        if (FlutterBluePlus.adapterStateNow == BluetoothAdapterState.off) {
          await FlutterBluePlus.turnOn();
          needsAttention =
              FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on;
        }
      } catch (_) {
        // Platform/plugin failures must not prevent access to Wi-Fi features.
        needsAttention = true;
      }
    }
    if (mounted) {
      setState(() {
        _bluetoothNeedsAttention = needsAttention;
        _showDisclaimer = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final showDisclaimer = _showDisclaimer;
    if (showDisclaimer == null) return const _SplashScreen();
    if (!showDisclaimer) {
      return _RootNavigation(bluetoothNeedsAttention: _bluetoothNeedsAttention);
    }
    return _DisclaimerScreen(onAcknowledge: _acknowledgeDisclaimer);
  }
}

class _RootNavigation extends StatefulWidget {
  const _RootNavigation({required this.bluetoothNeedsAttention});
  final bool bluetoothNeedsAttention;
  @override
  State<_RootNavigation> createState() => _RootNavigationState();
}

class _RootNavigationState extends State<_RootNavigation> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(
      index: _selectedIndex,
      children: [
        ScannerScreen(bluetoothNeedsAttention: widget.bluetoothNeedsAttention),
        DesignModeScreen(),
        CalibrationHistoryScreen(),
        const _LiveDataTab(),
      ],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _selectedIndex,
      onDestinationSelected: (index) => setState(() => _selectedIndex = index),
      indicatorColor: Theme.of(
        context,
      ).colorScheme.primary.withValues(alpha: .24),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.qr_code_scanner_outlined),
          selectedIcon: Icon(Icons.qr_code_scanner),
          label: 'Scan / Connect',
        ),
        NavigationDestination(
          icon: Icon(Icons.dashboard_outlined),
          selectedIcon: Icon(Icons.dashboard),
          label: 'Design Mode',
        ),
        NavigationDestination(
          icon: Icon(Icons.history_outlined),
          selectedIcon: Icon(Icons.history),
          label: 'History',
        ),
        NavigationDestination(
          icon: Icon(Icons.cloud_outlined),
          selectedIcon: Icon(Icons.cloud),
          label: 'Live Data',
        ),
      ],
    ),
    drawer: Drawer(
      child: SafeArea(
        child: ListView(
          children: [
            const DrawerHeader(child: Text('BattMobile')),
            ListTile(
              leading: const Icon(Icons.wifi),
              title: const Text('Wi-Fi Provisioning'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const WifiProvisioningScreen(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
}

/// Keeps the existing LoginScreen -> LiveDataViewerScreen Navigator flow
/// inside the Live Data tab. LoginScreen's pushReplacement therefore replaces
/// only this tab's page and never the outer navigation shell.
class _LiveDataTab extends StatelessWidget {
  const _LiveDataTab();

  @override
  Widget build(BuildContext context) {
    Widget initialPage;
    try {
      initialPage = FirebaseAuth.instance.currentUser == null
          ? const LoginScreen()
          : const LiveDataViewerScreen();
    } catch (_) {
      initialPage = const LoginScreen();
    }
    return Navigator(
      onGenerateRoute: (_) =>
          MaterialPageRoute<void>(builder: (_) => initialPage),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.battery_charging_full, size: 72),
          SizedBox(height: 16),
          Text('Ulink BatteryLab', style: TextStyle(fontSize: 24)),
          SizedBox(height: 20),
          SizedBox(width: 28, height: 28, child: CircularProgressIndicator()),
        ],
      ),
    ),
  );
}

class _DisclaimerScreen extends StatelessWidget {
  const _DisclaimerScreen({required this.onAcknowledge});

  final Future<void> Function() onAcknowledge;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Before you continue')),
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.privacy_tip_outlined, size: 44),
          const SizedBox(height: 20),
          Text(
            'Important information',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          const Text(
            'Placeholder disclaimer: this app handles BLE/Wi-Fi connection credentials and presents device data that may be delayed, incomplete, or inaccurate. Confirm critical readings using approved equipment and follow your organization\'s data-handling requirements. Replace this text with approved legal language before release.',
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onAcknowledge,
              child: const Text('I acknowledge'),
            ),
          ),
        ],
      ),
    ),
  );
}

//to be updated
