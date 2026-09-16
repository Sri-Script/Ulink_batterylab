import 'package:flutter/material.dart';

class ScannerStatusCard extends StatelessWidget {
  const ScannerStatusCard({
    super.key,
    required this.active,
    required this.message,
  });

  final bool active;
  final String message;

  @override
  Widget build(BuildContext context) =>
      Card(
        color: Theme
            .of(context)
            .colorScheme
            .surface
            .withValues(alpha: .94),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              if (active)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  Icons.qr_code_scanner,
                  color: Theme
                      .of(context)
                      .colorScheme
                      .primary,
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      );
}