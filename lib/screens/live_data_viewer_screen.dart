import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../config/app_config.dart';

class LiveDataViewerScreen extends StatelessWidget {
  const LiveDataViewerScreen({super.key});

  Future<void> _logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (context.mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _simulateEsp32Data(BuildContext context) async {
    final value = 3.55 + (DateTime.now().millisecond / 1000 * .15);
    await FirebaseFirestore.instance
        .collection('devices')
        .doc('ULINK-GW-TEST01')
        .collection('telemetry')
        .add({
          'key': 'battery_voltage',
          'value': double.parse(value.toStringAsFixed(2)),
          'timestamp': FieldValue.serverTimestamp(),
        });
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Simulated ESP32 telemetry uploaded.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Live Device Data'),
      actions: [
        if (AppConfig.demoMode)
          IconButton(
            onPressed: () => _simulateEsp32Data(context),
            tooltip: 'Simulate ESP32 Data',
            icon: const Icon(Icons.science),
          ),
        IconButton(
          onPressed: () => _logout(context),
          tooltip: 'Logout',
          icon: const Icon(Icons.logout),
        ),
      ],
    ),
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('devices').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Could not load live data: ${snapshot.error}'),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final devices = snapshot.data!.docs;
        if (devices.isEmpty) {
          return const Center(child: Text('No uploaded device data yet.'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: devices.length,
          itemBuilder: (context, index) {
            final device = devices[index];
            return _DeviceDataCard(deviceId: device.id);
          },
        );
      },
    ),
  );
}

class _DeviceDataCard extends StatelessWidget {
  const _DeviceDataCard({required this.deviceId});

  final String deviceId;

  @override
  Widget build(BuildContext context) {
    final device = FirebaseFirestore.instance.collection('devices').doc(deviceId);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(deviceId, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _RecentCollection(
              title: 'Recent telemetry',
              stream: device
                  .collection('telemetry')
                  .orderBy('timestamp', descending: true)
                  .limit(5)
                  .snapshots(),
              itemBuilder: (data) => '${data['key']}: ${data['value']}',
            ),
            const Divider(),
            _RecentCollection(
              title: 'Recent live status snapshots',
              stream: device
                  .collection('live_status_snapshots')
                  .orderBy('uploadedAt', descending: true)
                  .limit(3)
                  .snapshots(),
              itemBuilder: (data) {
                final devices = data['devices'] as List? ?? const [];
                return '${data['gatewayId'] ?? deviceId}: ${devices.length} devices';
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentCollection extends StatelessWidget {
  const _RecentCollection({
    required this.title,
    required this.stream,
    required this.itemBuilder,
  });

  final String title;
  final Stream<QuerySnapshot<Map<String, dynamic>>> stream;
  final String Function(Map<String, dynamic>) itemBuilder;

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: stream,
    builder: (context, snapshot) {
      if (snapshot.hasError) return Text('$title unavailable');
      if (!snapshot.hasData) return const LinearProgressIndicator();
      final documents = snapshot.data!.docs;
      if (documents.isEmpty) return Text('$title: none');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.labelLarge),
          ...documents.map(
            (document) => Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(itemBuilder(document.data())),
            ),
          ),
        ],
      );
    },
  );
}
