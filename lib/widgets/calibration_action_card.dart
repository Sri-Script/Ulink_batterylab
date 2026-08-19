import 'package:flutter/material.dart';

class CalibrationActionCard extends StatelessWidget {
  const CalibrationActionCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.busy,
    required this.onRead,
    required this.onWrite,
    this.lastValue,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final bool busy;
  final VoidCallback onRead;
  final VoidCallback onWrite;
  final String? lastValue;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary, size: 30),
          const SizedBox(height: 12),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          if (lastValue != null) ...[
            const SizedBox(height: 8),
            Text(
              'Last value: $lastValue',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const Spacer(),
          if (busy)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(10),
                child: CircularProgressIndicator(),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onRead,
                    icon: const Icon(Icons.download),
                    label: const Text('Read'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onWrite,
                    icon: const Icon(Icons.upload),
                    label: const Text('Write'),
                  ),
                ),
              ],
            ),
        ],
      ),
    ),
  );
}
