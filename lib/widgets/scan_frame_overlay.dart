import 'package:flutter/material.dart';

class ScanFrameOverlay extends StatelessWidget {
  const ScanFrameOverlay({super.key, this.size = 270});

  final double size;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Center(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.primary,
            width: 3,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 10)],
        ),
      ),
    ),
  );
}
