import 'package:flutter/material.dart';

import 'scanner_screen.dart';
import 'ulink_login_screen.dart';

class ArchitectureChoiceScreen extends StatelessWidget {
  const ArchitectureChoiceScreen({
    super.key,
    this.batteryMonitorBuilder,
    this.ulinkBuilder,
  });

  final WidgetBuilder? batteryMonitorBuilder;
  final WidgetBuilder? ulinkBuilder;

  void _open(BuildContext context, WidgetBuilder builder) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: builder));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Ulink BatteryLab')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.account_tree_outlined, size: 56),
              const SizedBox(height: 20),
              Text('Choose your workspace', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 10),
              const Text('Battery Monitor and U-Link provisioning use separate device flows.'),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: () => _open(
                  context,
                  ulinkBuilder ?? (_) => const UlinkLoginScreen(),
                ),
                icon: const Icon(Icons.link),
                label: const Text('Continue with U-Link'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _open(
                  context,
                  batteryMonitorBuilder ?? (_) => const ScannerScreen(),
                ),
                icon: const Icon(Icons.battery_charging_full),
                label: const Text('Continue with Battery Monitor'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
