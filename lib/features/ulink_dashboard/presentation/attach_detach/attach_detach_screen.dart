import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';
import '../widgets/dashboard_widgets.dart';

class AttachDetachScreen extends StatelessWidget {
  const AttachDetachScreen({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(AppTokens.s24),
      child: AppCard(
        padding: const EdgeInsets.all(AppTokens.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                color: AppTokens.teal.withValues(alpha: .12),
                shape: BoxShape.circle,
                border: Border.all(color: AppTokens.teal.withValues(alpha: .35)),
              ),
              child: const Stack(
                alignment: Alignment.center,
                children: [
                  Icon(Icons.hub_outlined, size: 46, color: AppTokens.teal),
                  Positioned(right: 18, bottom: 17, child: Icon(Icons.link, size: 22, color: AppTokens.success)),
                ],
              ),
            ),
            const SizedBox(height: AppTokens.s24),
            Text('Attach / Detach Devices', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: AppTokens.s12),
            const Text('Device attachment will be available in a future update.', textAlign: TextAlign.center, style: TextStyle(color: AppTokens.mutedText)),
            const SizedBox(height: AppTokens.s8),
            const Text('No devices or U-Links are changed from this screen.', textAlign: TextAlign.center, style: AppTokens.labelStyle),
          ],
        ),
      ),
    ),
  );
}
