import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../config/device_contract.dart';
import '../models/device_descriptor.dart';
import '../providers/connection_controller.dart';
import 'wifi_provisioning_screen.dart';

class ProgrammerHomeScreen extends StatefulWidget {
  const ProgrammerHomeScreen({super.key});

  @override
  State<ProgrammerHomeScreen> createState() => _ProgrammerHomeScreenState();
}

class _ProgrammerHomeScreenState extends State<ProgrammerHomeScreen> {
  final Map<String, DeviceDescriptor> _devices = {};
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  bool _scanning = false;
  bool _connecting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
  }

  Future<void> _scan() async {
    if (_scanning || _connecting) return;
    setState(() {
      _devices.clear();
      _error = null;
      _scanning = true;
    });
    try {
      if (AppConfig.demoMode) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        _devices['ULINK-GW-TEST01'] = _descriptorFor('ULINK-GW-TEST01');
      } else {
        final permitted = await context.read<ConnectionController>().requestBle();
        if (!permitted) {
          throw StateError('Bluetooth scan permission was denied.');
        }
        await _scanSubscription?.cancel();
        _scanSubscription = FlutterBluePlus.scanResults.listen(_collectResults);
        await FlutterBluePlus.startScan(
          withServices: [Guid(DeviceContract.defaultBleServiceUuid)],
        );
        await Future<void>.delayed(const Duration(seconds: 5));
        await FlutterBluePlus.stopScan();
      }
      if (!mounted) return;
      if (_devices.length == 1) {
        await _connect(_devices.values.single);
      } else if (_devices.isEmpty) {
        setState(() => _error = 'No Ulink devices found nearby.');
      }
    } catch (error) {
      if (mounted) setState(() => _error = _clean(error));
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  void _collectResults(List<ScanResult> results) {
    for (final result in results) {
      final name = result.advertisementData.advName;
      if (!name.startsWith(DeviceContract.advertisingNamePrefix)) continue;
      _devices[name] = _descriptorFor(name);
    }
    if (mounted) setState(() {});
  }

  DeviceDescriptor _descriptorFor(String advertisedName) => DeviceDescriptor(
    mode: TransportType.ble,
    deviceId: advertisedName,
    gatewayId: advertisedName,
    serviceUuid: DeviceContract.defaultBleServiceUuid,
    advertisingName: advertisedName,
  );

  Future<void> _connect(DeviceDescriptor descriptor) async {
    if (_connecting) return;
    setState(() => _connecting = true);
    final controller = context.read<ConnectionController>();
    final success = await controller.connect(descriptor);
    if (!mounted) return;
    if (success) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const WifiProvisioningScreen()),
      );
    } else {
      setState(() => _error = _clean(controller.errorMessage ?? 'Connection failed.'));
    }
    if (mounted) setState(() => _connecting = false);
  }

  String _clean(Object error) =>
      error.toString().replaceFirst(RegExp(r'^(StateError|Exception):\s*'), '');

  @override
  void dispose() {
    _scanSubscription?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final devices = _devices.values.toList()..sort((a, b) => a.deviceId.compareTo(b.deviceId));
    return Scaffold(
      appBar: AppBar(title: const Text('Program a Device')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Searching for nearby Ulink gateways over Bluetooth.',
            ),
            const SizedBox(height: 20),
            if (_scanning || _connecting)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (devices.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.bluetooth_disabled, size: 48),
                      const SizedBox(height: 12),
                      Text(_error ?? 'No Ulink devices found nearby.'),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _scan,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              Text(
                'Select a device to program:',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.separated(
                  itemCount: devices.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final device = devices[index];
                    return ListTile(
                      leading: const Icon(Icons.memory),
                      title: Text(device.deviceId),
                      subtitle: const Text('Ulink BLE gateway'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _connect(device),
                    );
                  },
                ),
              ),
              OutlinedButton.icon(
                onPressed: _scan,
                icon: const Icon(Icons.refresh),
                label: const Text('Scan again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
