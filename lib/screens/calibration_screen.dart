import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/device_contract.dart';
import '../providers/connection_controller.dart';
import '../services/device_connection.dart' as device;
import '../widgets/connection_status_pill.dart';

class CalibrationScreen extends StatefulWidget {
  const CalibrationScreen({super.key});

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen> {
  final Set<String> _busy = {};
  dynamic _lastDetectedTemp;
  dynamic _lastDetectedVoltage;

  Future<void> _run(String key, String command) async {
    setState(() => _busy.add(key));
    try {
      final response = await context.read<ConnectionController>().command(
        command,
        logKey: key,
      );
      if (!mounted) return;
      final decoded = _json(response);
      if (decoded != null && (command.startsWith('CAL_TEMP') || command.startsWith('CAL_VOLT'))) {
        setState(() {
          if (command.startsWith('CAL_TEMP')) {
            _lastDetectedTemp = _firstValue(decoded, const [
              'detected_temp', 'detected_temperature', 'detectedTemp',
            ]);
          } else {
            _lastDetectedVoltage = _firstValue(decoded, const [
              'detected_volt', 'detected_voltage', 'detectedVoltage',
            ]);
          }
        });
      }
      _message(response, error: response.startsWith('ERROR:'));
      if (command == 'GET_CAL' || command.startsWith('RESET_')) {
        await context.read<ConnectionController>().refreshCalibrationStatus();
      }
    } catch (error) {
      if (mounted) _message(_clean(error), error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  Future<void> _reference(bool temperature) async {
    final value = await _ask('True ${temperature ? 'temperature' : 'voltage'} reference');
    if (value != null) {
      await _run(temperature ? 'temp' : 'volt', '${temperature ? 'CAL_TEMP' : 'CAL_VOLT'}:$value');
    }
  }

  Future<String?> _ask(String title, {String? hint, bool allowEmpty = false}) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          decoration: InputDecoration(hintText: hint, border: const OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isEmpty && !allowEmpty) return;
              Navigator.pop(dialogContext, value);
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _serial() async {
    final current = await context.read<ConnectionController>().command('GET_SN', logKey: 'serial');
    if (!mounted) return;
    final value = await _ask('Serial number', hint: 'Current: $current');
    if (value == null) return;
    if (!DeviceContract.serialPattern.hasMatch(value)) {
      _message('Serial must use the BATTERY-... format.', error: true);
      return;
    }
    await _run('serial', 'SET_SN:$value');
  }

  Future<void> _clock() async {
    final value = await _ask('Clock', hint: 'Blank reads; ISO-8601 sets.', allowEmpty: true);
    if (value != null) await _run('clock', value.isEmpty ? 'GET_TIME' : 'SET_TIME:$value');
  }

  Future<void> _role() async {
    final current = await context.read<ConnectionController>().command('GET_ROLE', logKey: 'role');
    if (!mounted) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Node role'), content: Text(current),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, 'MAKE_AVAILABLE'), child: const Text('Make available')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, 'MAKE_MASTER'), child: const Text('Make master')),
        ],
      ),
    );
    if (choice != null) await _run('role', choice);
  }

  void _message(String message, {bool error = false}) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message.trim()), backgroundColor: error ? Theme.of(context).colorScheme.error : null),
  );
  String _clean(Object error) => error.toString().replaceFirst(RegExp(r'^(StateError|Exception):\s*'), '');
  Map<String, dynamic>? _json(String value) {
    try { final decoded = jsonDecode(value); return decoded is Map ? Map<String, dynamic>.from(decoded) : null; }
    on FormatException { return null; }
  }
  dynamic _firstValue(Map<String, dynamic> values, List<String> keys) {
    for (final key in keys) { if (values[key] != null) return values[key]; }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ConnectionController>();
    final descriptor = controller.descriptor;
    if (descriptor == null) return const Scaffold(body: Center(child: Text('No device connected.')));
    final connected = controller.connectionState == device.ConnectionState.connected;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(descriptor.deviceId),
          actions: [
            Center(child: ConnectionStatusPill(state: controller.connectionState)),
            IconButton(onPressed: () async { await controller.disconnect(); if (context.mounted) Navigator.pop(context); }, icon: const Icon(Icons.link_off)),
          ],
          bottom: const TabBar(tabs: [Tab(icon: Icon(Icons.monitor_heart), text: 'Live'), Tab(icon: Icon(Icons.tune), text: 'Calibration')]),
        ),
        body: TabBarView(children: [_live(controller), _actions(connected, controller)]),
      ),
    );
  }

  Widget _live(ConnectionController controller) {
    final status = controller.calibrationStatus;
    final statusSerial = _firstValue(
      status ?? const <String, dynamic>{},
      const ['serial', 'serial_number', 'serialNumber'],
    )?.toString();
    Map<String, dynamic>? directReading;
    if (statusSerial != null) {
      for (final reading in controller.liveDevices) {
        if (reading['serial']?.toString() == statusSerial) {
          directReading = reading;
          break;
        }
      }
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Connected device', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        _CalibrationBlock(status: status, liveReading: directReading, detectedTemp: _lastDetectedTemp, detectedVoltage: _lastDetectedVoltage),
        const SizedBox(height: 20),
        Text('Live devices', style: Theme.of(context).textTheme.titleLarge),
        const Text('Each dot flashes once when that device sends a new reading.'),
        const SizedBox(height: 12),
        if (controller.liveDevices.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Waiting for live data…'))),
        ...controller.liveDevices.map((reading) {
          final serial = reading['serial']?.toString() ?? 'Unknown serial';
          return _LiveDeviceCard(key: ValueKey(serial), reading: reading, sequence: controller.liveUpdateSequence(serial));
        }),
      ],
    );
  }

  Widget _actions(bool connected, ConnectionController controller) {
    final actions = <_Action>[
      _Action('Calibrate Temperature', Icons.thermostat, () => _reference(true)),
      _Action('Calibrate Voltage', Icons.bolt, () => _reference(false)),
      _Action('View Calibration Status', Icons.fact_check, () => _run('status', 'GET_CAL')),
      _Action('Reset Temperature Calibration', Icons.restart_alt, () => _run('resetTemp', 'RESET_TEMP_CAL')),
      _Action('Reset Voltage Calibration', Icons.restart_alt, () => _run('resetVolt', 'RESET_VOLT_CAL')),
      _Action('Reset All Calibration', Icons.delete_sweep, () => _run('resetAll', 'RESET_CAL')),
      _Action('Serial Number', Icons.tag, _serial), _Action('Role', Icons.account_tree, _role), _Action('Clock', Icons.schedule, _clock),
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Detected values are saved only from the immediately preceding calibration response; firmware does not provide them continuously.'),
        const SizedBox(height: 8),
        ...actions.map((action) => Card(child: ListTile(leading: Icon(action.icon), title: Text(action.title), trailing: _busy.contains(action.title) ? const CircularProgressIndicator() : const Icon(Icons.chevron_right), onTap: connected ? action.run : null))),
      ],
    );
  }
}

class _CalibrationBlock extends StatelessWidget {
  const _CalibrationBlock({required this.status, required this.liveReading, required this.detectedTemp, required this.detectedVoltage});
  final Map<String, dynamic>? status;
  final Map<String, dynamic>? liveReading;
  final dynamic detectedTemp;
  final dynamic detectedVoltage;

  dynamic _value(List<String> keys, {dynamic fallback}) {
    for (final key in keys) { if (liveReading?[key] != null) return liveReading![key]; if (status?[key] != null) return status![key]; }
    return fallback;
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: status == null ? const Text('Calibration status unavailable.') : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Calibration status', style: Theme.of(context).textTheme.titleMedium), const SizedBox(height: 10),
        _Field('Serial Number', _value(const ['serial', 'serial_number', 'serialNumber'])),
        _Field('Last Cal Temp Ref', _value(const ['temp_true_ref', 'last_cal_temp_ref'])),
        _Field('Temp Factor', _value(const ['temp_factor'])),
        _Field('Calibrated Temp', _value(const ['temperature', 'temp', 'temp_calibrated', 'calibrated_temp'])),
        _Field('Detected Temp (last calibration run)', detectedTemp, placeholder: 'not measured yet this session'),
        _Field('Last Cal Volt Ref', _value(const ['volt_true_ref', 'last_cal_volt_ref'])),
        _Field('Voltage Factor', _value(const ['volt_factor', 'voltage_factor'])),
        _Field('Calibrated Voltage', _value(const ['voltage', 'volt', 'volt_calibrated', 'calibrated_voltage'])),
        _Field('Detected Voltage (last calibration run)', detectedVoltage, placeholder: 'not measured yet this session'),
      ]),
    ),
  );
}

class _Field extends StatelessWidget {
  const _Field(this.label, this.value, {this.placeholder = '—'});
  final String label; final dynamic value; final String placeholder;
  @override Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 190, child: Text('$label:', style: const TextStyle(fontWeight: FontWeight.w600))),
      Expanded(child: Text(value?.toString() ?? placeholder)),
    ]),
  );
}

class _LiveDeviceCard extends StatefulWidget {
  const _LiveDeviceCard({super.key, required this.reading, required this.sequence});
  final Map<String, dynamic> reading; final int sequence;
  @override State<_LiveDeviceCard> createState() => _LiveDeviceCardState();
}

class _LiveDeviceCardState extends State<_LiveDeviceCard> {
  Timer? _timer; bool _flashing = false;
  @override void initState() { super.initState(); if (widget.sequence > 0) _pulse(); }
  @override void didUpdateWidget(covariant _LiveDeviceCard oldWidget) { super.didUpdateWidget(oldWidget); if (widget.sequence != oldWidget.sequence) _pulse(); }
  void _pulse() { _timer?.cancel(); if (mounted) setState(() => _flashing = true); _timer = Timer(const Duration(milliseconds: 400), () { if (mounted) setState(() => _flashing = false); }); }
  @override void dispose() { _timer?.cancel(); super.dispose(); }
  @override Widget build(BuildContext context) {
    final reading = widget.reading;
    return Card(child: ListTile(
      leading: AnimatedContainer(duration: const Duration(milliseconds: 100), width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: _flashing ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.primary.withValues(alpha: .25))),
      title: Text(reading['serial']?.toString() ?? 'Unknown serial'),
      subtitle: Text('Calibrated Temp: ${reading['temperature'] ?? reading['temp'] ?? '—'}\nCalibrated Voltage: ${reading['voltage'] ?? reading['volt'] ?? '—'}\nDatetime: ${reading['datetime'] ?? 'UNSYNCED'}'),
      isThreeLine: true,
    ));
  }
}

class _Action { const _Action(this.title, this.icon, this.run); final String title; final IconData icon; final VoidCallback run; }
