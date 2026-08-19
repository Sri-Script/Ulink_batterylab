import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/calibration_log_entry.dart';
import '../models/calibration_reading.dart';
import '../models/device_descriptor.dart';
import '../providers/connection_controller.dart';
import '../services/device_connection.dart' as device;
import '../widgets/calibration_action_card.dart';
import '../widgets/connection_status_pill.dart';

class CalibrationScreen extends StatefulWidget {
  const CalibrationScreen({super.key});
  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen> {
  final Set<String> _busy = {};
  final Map<String, String> _lastValues = {};
  int _historyVersion = 0;

  bool _polling = false;
  bool _uploading = false;
  Timer? _pollTimer;
  final List<CalibrationReading> _polledReadings = [];

  static const _pollInterval = Duration(seconds: 5);

  Future<void> _read(String key) async {
    setState(() => _busy.add(key));
    try {
      final reading = await context.read<ConnectionController>().read(key);
      if (!mounted) return;
      setState(() {
        _lastValues[key] = reading.value?.toString() ?? 'null';
        _historyVersion++;
      });
      if (key == 'clock') {
        _message(
          'Device time: ${reading.value} • Phone time: '
              '${DateTime.now().toIso8601String()}',
        );
      } else {
        _message('Read $key successfully.');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _historyVersion++);
        _message(_clean(error), error: true);
      }
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  Future<void> _write(
      String key, {
        required bool timestamped,
        dynamic fixedValue,
      }) async {
    dynamic value = fixedValue;
    if (value == null) {
      value = await _askValue(key);
      if (value == null || !mounted) return;
    }
    setState(() => _busy.add(key));
    try {
      final timestamp = timestamped ? DateTime.now() : null;
      final success = await context.read<ConnectionController>().write(
        key,
        value,
        timestamp: timestamp,
      );
      if (!mounted) return;
      setState(() {
        _lastValues[key] = value.toString();
        _historyVersion++;
      });
      _message(
        success
            ? 'Calibration written successfully.'
            : 'The device rejected the calibration.',
        error: !success,
      );
    } catch (error) {
      if (mounted) {
        setState(() => _historyVersion++);
        _message(_clean(error), error: true);
      }
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  Future<double?> _askValue(String key) async {
    final textController = TextEditingController();
    final title = switch (key) {
      'reference' => 'Set reference point',
      'voltage' => 'Set voltage',
      _ => 'Calibration value',
    };
    final value = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: textController,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          decoration: const InputDecoration(
            labelText: 'Value',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final parsed = double.tryParse(textController.text.trim());
              if (parsed == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Enter a numeric value.')),
                );
                return;
              }
              Navigator.pop(context, parsed);
            },
            child: const Text('Write'),
          ),
        ],
      ),
    );
    textController.dispose();
    return value;
  }

  void _message(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  String _clean(Object error) =>
      error.toString().replaceFirst(RegExp(r'^(StateError|Exception):\s*'), '');

  Future<void> _disconnect() async {
    _stopPolling();
    await context.read<ConnectionController>().disconnect();
    if (mounted) Navigator.pop(context);
  }

  void _startPolling() {
    if (_polling) return;
    setState(() => _polling = true);
    _pollTimer = Timer.periodic(_pollInterval, (_) => _pollOnce());
    _pollOnce();
  }

  Future<void> _pollOnce() async {
    if (!mounted) return;
    final controller = context.read<ConnectionController>();
    if (controller.connectionState != device.ConnectionState.connected) {
      _stopPolling(reason: 'Device disconnected — polling stopped.');
      return;
    }
    try {
      final reading = await controller.read('telemetry');
      if (!mounted) return;
      setState(() => _polledReadings.insert(0, reading));
    } catch (_) {
      _stopPolling(reason: 'Read failed — polling stopped.');
    }
  }

  void _stopPolling({String? reason}) {
    _pollTimer?.cancel();
    _pollTimer = null;
    if (!mounted) return;
    setState(() => _polling = false);
    if (reason != null) _message(reason, error: true);
  }

  Future<void> _upload() async {
    if (_polledReadings.isEmpty) {
      _message('No readings to upload yet.');
      return;
    }
    setState(() => _uploading = true);
    try {
      // TODO: replace with real upload endpoint — currently a local no-op stub.
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (!mounted) return;
      _message('Uploaded ${_polledReadings.length} readings.');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ConnectionController>();
    final descriptor = controller.descriptor;
    if (descriptor == null) {
      return const Scaffold(
        body: Center(child: Text('No device is connected.')),
      );
    }
    final connected =
        controller.connectionState == device.ConnectionState.connected;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 16,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                descriptor.deviceId,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Row(
                children: [
                  Icon(
                    descriptor.mode == TransportType.ble
                        ? Icons.bluetooth
                        : Icons.wifi,
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    descriptor.mode == TransportType.ble
                        ? 'Bluetooth LE'
                        : 'Wi-Fi',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            Center(
              child: ConnectionStatusPill(state: controller.connectionState),
            ),
            IconButton(
              onPressed: _disconnect,
              tooltip: 'Disconnect',
              icon: const Icon(Icons.link_off),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.tune), text: 'Calibration'),
              Tab(icon: Icon(Icons.podcasts), text: 'Live Data'),
              Tab(icon: Icon(Icons.history), text: 'History'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _actions(connected, controller.batteryCount),
            _liveData(connected),
            _HistoryView(
              key: ValueKey(_historyVersion),
              load: controller.history,
            ),
          ],
        ),
      ),
    );
  }

  Widget _actions(bool connected, int? batteryCount) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 720
          ? 3
          : constraints.maxWidth >= 480
          ? 2
          : 1;
      final cards = [
        CalibrationActionCard(
          title: 'Zero Calibration',
          subtitle: 'Reset the sensor zero point.',
          icon: Icons.exposure_zero,
          busy: _busy.contains('zero'),
          lastValue: _lastValues['zero'],
          onRead: connected
              ? () => _read('zero')
              : () => _message('Device is disconnected.', error: true),
          onWrite: connected
              ? () => _write('zero', timestamped: false, fixedValue: 0)
              : () => _message('Device is disconnected.', error: true),
        ),
        CalibrationActionCard(
          title: 'Set Reference Point',
          subtitle: 'Store the supplied sensor reading as baseline.',
          icon: Icons.my_location,
          busy: _busy.contains('reference'),
          lastValue: _lastValues['reference'],
          onRead: connected
              ? () => _read('reference')
              : () => _message('Device is disconnected.', error: true),
          onWrite: connected
              ? () => _write('reference', timestamped: false)
              : () => _message('Device is disconnected.', error: true),
        ),
        CalibrationActionCard(
          title: 'Calibrate with Timestamp',
          subtitle: 'Time-anchor a calibration value.',
          icon: Icons.schedule,
          busy: _busy.contains('timestamped'),
          lastValue: _lastValues['timestamped'],
          onRead: connected
              ? () => _read('timestamped')
              : () => _message('Device is disconnected.', error: true),
          onWrite: connected
              ? () => _write('timestamped', timestamped: true)
              : () => _message('Device is disconnected.', error: true),
        ),
        CalibrationActionCard(
          title: 'Clock Settings',
          subtitle: 'Read the device clock or sync it to this phone.',
          icon: Icons.access_time,
          busy: _busy.contains('clock'),
          lastValue: _lastValues['clock'],
          onRead: connected
              ? () => _read('clock')
              : () => _message('Device is disconnected.', error: true),
          onWrite: connected
              ? () => _write(
            'clock',
            timestamped: false,
            fixedValue: DateTime.now().toIso8601String(),
          )
              : () => _message('Device is disconnected.', error: true),
        ),
        CalibrationActionCard(
          title: 'Voltage Setting',
          subtitle: 'Read or set the voltage calibration value.',
          icon: Icons.bolt,
          busy: _busy.contains('voltage'),
          lastValue: _lastValues['voltage'],
          onRead: connected
              ? () => _read('voltage')
              : () => _message('Device is disconnected.', error: true),
          onWrite: connected
              ? () => _write('voltage', timestamped: false)
              : () => _message('Device is disconnected.', error: true),
        ),
      ];
      return Column(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Theme.of(context).colorScheme.primary),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.battery_charging_full,
                  color: Theme.of(context).colorScheme.primary,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    batteryCount == null
                        ? 'Battery count unavailable'
                        : '$batteryCount ${batteryCount == 1 ? 'battery' : 'batteries'} detected',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: GridView.count(
              padding: const EdgeInsets.all(16),
              crossAxisCount: columns,
              childAspectRatio: columns == 1 ? 1.55 : 1.0,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              children: cards,
            ),
          ),
        ],
      );
    },
  );

  Widget _liveData(bool connected) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: connected
                    ? (_polling ? _stopPolling : _startPolling)
                    : null,
                icon: Icon(_polling ? Icons.stop_circle : Icons.play_circle),
                label: Text(_polling ? 'Stop Polling' : 'Start Polling'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _uploading ? null : _upload,
                icon: _uploading
                    ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : const Icon(Icons.cloud_upload),
                label: Text(_uploading ? 'Uploading...' : 'Upload'),
              ),
            ),
          ],
        ),
      ),
      Expanded(
        child: _polledReadings.isEmpty
            ? const Center(child: Text('No readings yet — start polling.'))
            : ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: _polledReadings.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final reading = _polledReadings[index];
            return ListTile(
              leading: const Icon(Icons.show_chart),
              title: Text(reading.value.toString()),
              subtitle: Text(reading.timestamp.toLocal().toString()),
            );
          },
        ),
      ),
    ],
  );
}

class _HistoryView extends StatefulWidget {
  const _HistoryView({super.key, required this.load});
  final Future<List<CalibrationLogEntry>> Function() load;
  @override
  State<_HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends State<_HistoryView> {
  late Future<List<CalibrationLogEntry>> _entries = widget.load();

  Future<void> _refresh() async {
    setState(() => _entries = widget.load());
    await _entries;
  }

  @override
  Widget build(
      BuildContext context,
      ) => FutureBuilder<List<CalibrationLogEntry>>(
    future: _entries,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return Center(child: Text('Could not load history: ${snapshot.error}'));
      }
      final entries = snapshot.data ?? [];
      if (entries.isEmpty) {
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            children: const [
              SizedBox(height: 180),
              Center(child: Text('No calibration history yet.')),
            ],
          ),
        );
      }
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: entries.length + 1,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            if (index == 0) {
              return ListTile(
                title: const Text(
                  'Local calibration log',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                trailing: IconButton(
                  onPressed: () {
                    /* TODO: Firebase sync hook. */
                  },
                  tooltip: 'Sync (coming later)',
                  icon: const Icon(Icons.sync_disabled),
                ),
              );
            }
            final entry = entries[index - 1];
            return ListTile(
              leading: CircleAvatar(
                child: Icon(
                  entry.direction == 'read' ? Icons.download : Icons.upload,
                  size: 18,
                ),
              ),
              title: Text(entry.action),
              subtitle: Text(
                '${entry.value ?? '—'} • ${entry.timestamp.toLocal()}',
              ),
              trailing: Icon(
                entry.status == 'success' ? Icons.check_circle : Icons.error,
                color: entry.status == 'success'
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.error,
              ),
            );
          },
        ),
      );
    },
  );
}