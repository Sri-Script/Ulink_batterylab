import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/connection_controller.dart';
import 'screens/scanner_screen.dart';
import 'services/app_telemetry_notification_controller.dart';
import 'services/local_notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Firestore uploads show a retryable setup error if initialization fails.
  }
  await LocalNotificationService.instance.initialize();
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
    _telemetryNotifications.start();
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
      title: 'Ulink Programmer',
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
      home: const ScannerScreen(),
    ),
  );
}
//to be updated
