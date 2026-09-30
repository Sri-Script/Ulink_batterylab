import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../config/device_contract.dart';
import '../models/virtual_battery_slot.dart';
import '../providers/connection_controller.dart';
import '../services/calibration_database.dart';

class DesignModeScreen extends StatefulWidget {
  const DesignModeScreen({super.key});

  @override
  State<DesignModeScreen> createState() => _DesignModeScreenState();
}

class _DesignModeScreenState extends State<DesignModeScreen> {
  static const int _gridCount = 9;
  final _database = CalibrationDatabase.instance;
  final Map<int, VirtualBatterySlot> _slots = {};
  final Map<String, _DetectedModule> _detected = {};
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  bool _loading = true;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _loadLayout();
  }

  Future<void> _loadLayout() async {
    final slots = await _database.virtualBatterySlots();
    if (!mounted) return;
    setState(() {
      _slots.addEntries(slots.map((slot) => MapEntry(slot.position, slot)));
      for (final slot in slots) {
        if (slot.isMatched) continue;
      }
      _loading = false;
    });
  }

  Future<void> _save(VirtualBatterySlot slot) async {
    await _database.saveVirtualBatterySlot(slot);
    if (mounted) setState(() => _slots[slot.position] = slot);
  }

  Future<void> _editSlot(int position) async {
    final existing = _slots[position];
    final name = TextEditingController(
      text: existing?.name ?? 'Battery${position + 1}',
    );
    final serial = TextEditingController(text: existing?.serial ?? '');
    var role = existing?.role ?? 'Slave';
    final result = await showDialog<_SlotEditResult>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            existing == null
                ? 'Configure position ${position + 1}'
                : 'Edit position ${position + 1}',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'String name'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: const [
                  DropdownMenuItem(value: 'Master', child: Text('Master')),
                  DropdownMenuItem(value: 'Slave', child: Text('Slave')),
                ],
                onChanged: (value) =>
                    setDialogState(() => role = value ?? role),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: serial,
                decoration: const InputDecoration(
                  labelText: 'Serial number (optional)',
                ),
              ),
            ],
          ),
          actions: [
            if (existing != null)
              TextButton(
                onPressed: () =>
                    Navigator.pop(dialogContext, const _SlotEditResult.clear()),
                child: const Text('Clear'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final value = name.text.trim();
                if (value.isNotEmpty) {
                  Navigator.pop(
                    dialogContext,
                    _SlotEditResult.save(value, role, serial.text.trim()),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    serial.dispose();
    if (result == null) return;
    if (result.clear) {
      await _clearSlot(position);
      return;
    }
    await _save(
      VirtualBatterySlot(
        position: position,
        name: result.name!,
        role: result.role!,
        serial: result.serial!.isEmpty ? null : result.serial,
        matchedDeviceId: existing?.matchedDeviceId,
        matchedDeviceName: existing?.matchedDeviceName,
      ),
    );
  }

  Future<void> _showMatchedMenu(VirtualBatterySlot slot) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.link_off),
              title: const Text('Unmatch'),
              onTap: () => Navigator.pop(context, 'unmatch'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Clear'),
              onTap: () => Navigator.pop(context, 'clear'),
            ),
          ],
        ),
      ),
    );
    if (action == 'unmatch') {
      final id = slot.matchedDeviceId!;
      await _save(slot.copyWith(clearMatch: true));
      if (!mounted) return;
      setState(
        () => _detected[id] = _DetectedModule(id, slot.matchedDeviceName ?? id),
      );
    } else if (action == 'edit') {
      await _editSlot(slot.position);
    } else if (action == 'clear') {
      await _clearSlot(slot.position);
    }
  }

  Future<void> _clearSlot(int position) async {
    final slot = _slots[position];
    await _database.deleteVirtualBatterySlot(position);
    if (!mounted) return;
    setState(() {
      _slots.remove(position);
      if (slot?.matchedDeviceId case final id?) {
        _detected[id] = _DetectedModule(id, slot?.matchedDeviceName ?? id);
      }
    });
  }

  Future<void> _startDetecting() async {
    if (_scanning) return;
    setState(() => _scanning = true);
    try {
      if (AppConfig.demoMode) {
        setState(
          () => _detected['demo-node-1'] = const _DetectedModule(
            'demo-node-1',
            'VoltTHERM Node1',
          ),
        );
        return;
      }
      if (!await context.read<ConnectionController>().requestBle()) {
        throw StateError('Bluetooth permission is required to detect modules.');
      }
      if (!await FlutterBluePlus.isSupported) {
        throw StateError('Bluetooth LE is not supported on this device.');
      }
      if (FlutterBluePlus.adapterStateNow == BluetoothAdapterState.off) {
        await FlutterBluePlus.turnOn();
      }
      if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
        throw StateError('Turn Bluetooth on, then try again.');
      }
      await _scanSubscription?.cancel();
      _scanSubscription = FlutterBluePlus.scanResults.listen(_collectMatches);
      await FlutterBluePlus.startScan(timeout: AppConfig.bleScanTimeout);
      await FlutterBluePlus.isScanning
          .where((value) => !value)
          .first
          .timeout(AppConfig.bleScanTimeout + const Duration(seconds: 2));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Detection failed: $error')));
      }
    } finally {
      await FlutterBluePlus.stopScan();
      if (mounted) setState(() => _scanning = false);
    }
  }

  void _collectMatches(List<ScanResult> results) {
    var changed = false;
    for (final result in results) {
      final advertisedName = result.advertisementData.advName;
      final services = result.advertisementData.serviceUuids.map(
        (uuid) => uuid.toString(),
      );
      if (!DeviceContract.matchesBleAdvertisement(
        advertisedName: advertisedName,
        serviceUuids: services,
        advertisedBleDeviceId: result.device.remoteId.str,
      )) {
        continue;
      }
      final id = result.device.remoteId.str;
      if (_slots.values.any((slot) => slot.matchedDeviceId == id)) {
        continue;
      }
      final label = advertisedName.isNotEmpty
          ? advertisedName
          : result.device.platformName.isNotEmpty
          ? result.device.platformName
          : id;
      _detected[id] = _DetectedModule(id, label);
      changed = true;
    }
    if (changed && mounted) setState(() {});
  }

  Future<void> _match(int position, _DetectedModule module) async {
    final slot = _slots[position];
    if (slot == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Configure this position before matching a module.'),
        ),
      );
      return;
    }
    if (slot.isMatched) return;
    await _save(
      slot.copyWith(matchedDeviceId: module.id, matchedDeviceName: module.name),
    );
    if (mounted) setState(() => _detected.remove(module.id));
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matched = _slots.values.where((slot) => slot.isMatched).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Design Mode')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  '$matched of $_gridCount positions matched',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                _BatteryGrid(
                  count: _gridCount,
                  slots: _slots,
                  onTap: _editSlot,
                  onLongPress: _showMatchedMenu,
                  onDrop: _match,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _scanning ? null : _startDetecting,
                  icon: _scanning
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.bluetooth_searching),
                  label: Text(
                    _scanning ? 'Detecting…' : 'Start detecting (BLE)',
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Detected VoltTHERM modules',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (_detected.isEmpty)
                  const Text('No unassigned modules detected yet.')
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _detected.values
                        .map(
                          (module) => Draggable<_DetectedModule>(
                            data: module,
                            feedback: Material(
                              color: Colors.transparent,
                              child: Chip(label: Text(module.name)),
                            ),
                            childWhenDragging: Opacity(
                              opacity: .35,
                              child: Chip(
                                avatar: const Icon(Icons.bluetooth, size: 18),
                                label: Text(module.name),
                              ),
                            ),
                            child: Chip(
                              avatar: const Icon(
                                Icons.drag_indicator,
                                size: 18,
                              ),
                              label: Text(module.name),
                            ),
                          ),
                        )
                        .toList(),
                  ),
              ],
            ),
    );
  }
}

class _BatteryGrid extends StatelessWidget {
  const _BatteryGrid({
    required this.count,
    required this.slots,
    required this.onTap,
    required this.onLongPress,
    required this.onDrop,
  });
  final int count;
  final Map<int, VirtualBatterySlot> slots;
  final ValueChanged<int> onTap;
  final ValueChanged<VirtualBatterySlot> onLongPress;
  final void Function(int, _DetectedModule) onDrop;
  @override
  Widget build(BuildContext context) => GridView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    itemCount: count,
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 3,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
    ),
    itemBuilder: (context, position) {
      final slot = slots[position];
      return DragTarget<_DetectedModule>(
        onWillAcceptWithDetails: (_) => slot == null || !slot.isMatched,
        onAcceptWithDetails: (details) => onDrop(position, details.data),
        builder: (context, _, __) => _BatteryBox(
          slot: slot,
          onTap: () => onTap(position),
          onLongPress: slot?.isMatched == true
              ? () => onLongPress(slot!)
              : null,
        ),
      );
    },
  );
}

class _BatteryBox extends StatelessWidget {
  const _BatteryBox({
    required this.slot,
    required this.onTap,
    this.onLongPress,
  });
  final VirtualBatterySlot? slot;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  @override
  Widget build(BuildContext context) {
    final configured = slot != null;
    final color = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(10),
      child: CustomPaint(
        painter: _BoxBorderPainter(
          color: configured ? color : Theme.of(context).dividerColor,
          dashed: !configured,
        ),
        child: Center(
          child: configured
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      slot!.isMatched
                          ? Icons.battery_full
                          : Icons.battery_1_bar_outlined,
                      color: color,
                      size: 30,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      slot!.name,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      slot!.role,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                )
              : const SizedBox(),
        ),
      ),
    );
  }
}

class _BoxBorderPainter extends CustomPainter {
  const _BoxBorderPainter({required this.color, required this.dashed});
  final Color color;
  final bool dashed;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(10),
    );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    if (!dashed) {
      canvas.drawRRect(rect, paint);
      return;
    }
    final path = Path()..addRRect(rect);
    for (final metric in path.computeMetrics()) {
      for (var distance = 0.0; distance < metric.length; distance += 8) {
        canvas.drawPath(metric.extractPath(distance, distance + 4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_BoxBorderPainter old) =>
      old.color != color || old.dashed != dashed;
}

class _DetectedModule {
  const _DetectedModule(this.id, this.name);
  final String id;
  final String name;
}

class _SlotEditResult {
  const _SlotEditResult.save(this.name, this.role, this.serial) : clear = false;
  const _SlotEditResult.clear()
    : name = null,
      role = null,
      serial = null,
      clear = true;
  final String? name;
  final String? role;
  final String? serial;
  final bool clear;
}
