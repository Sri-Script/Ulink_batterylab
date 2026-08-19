import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/connection_controller.dart';
import 'screens/scanner_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BatteryLabApp());
}

class BatteryLabApp extends StatelessWidget {
  const BatteryLabApp({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => ConnectionController(),
    child: MaterialApp(
      title: 'Ulink BatteryLab',
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