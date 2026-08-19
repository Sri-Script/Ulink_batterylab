import 'package:flutter/material.dart';

import '../services/device_connection.dart' as device;

class ConnectionStatusPill extends StatelessWidget {
  const ConnectionStatusPill({super.key, required this.state});
  final device.ConnectionState state;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      device.ConnectionState.connected => (
        'Connected',
        Theme.of(context).colorScheme.primary,
      ),
      device.ConnectionState.reconnecting => (
        'Reconnecting',
        Theme.of(context).colorScheme.primary,
      ),
      device.ConnectionState.connecting => (
        'Connecting',
        Theme.of(context).colorScheme.primary,
      ),
      device.ConnectionState.disconnected => (
        'Disconnected',
        Theme.of(context).colorScheme.error,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .13),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
