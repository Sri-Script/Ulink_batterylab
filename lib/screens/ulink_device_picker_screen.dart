import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../services/permission_service.dart';
import '../services/ulink_ble_protocol_config.dart';
import '../services/ulink_ble_provisioning_client.dart';
import 'ulink_wifi_provisioning_screen.dart';

class UlinkDevicePickerScreen extends StatefulWidget {
  const UlinkDevicePickerScreen({super.key, this.config});
  final UlinkBleProtocolConfig? config;

  @override
  State<UlinkDevicePickerScreen> createState() => _UlinkDevicePickerScreenState();
}

class _UlinkDevicePickerScreenState extends State<UlinkDevicePickerScreen> {
  late final UlinkBleProtocolConfig _config = widget.config ?? UlinkBleProtocolConfig.environment;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  final Map<String, ScanResult> _results = <String, ScanResult>{};
  bool _scanning = false;
  bool _connecting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startScan());
  }

  Future<void> _startScan() async {
    await _stopScan();
    setState(() {
      _error = null;
      _results.clear();
    });
    try {
      if (!await PermissionService().requestBle()) {
        throw StateError('Bluetooth permission is required to find U-Link devices.');
      }
      if (!await FlutterBluePlus.isSupported) {
        throw StateError('Bluetooth LE is not supported on this device.');
      }
      if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
        await FlutterBluePlus.turnOn();
      }
      if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
        throw StateError('Turn on Bluetooth to scan for U-Link devices.');
      }
      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        if (!mounted) return;
        setState(() {
          for (final result in results) {
            final name = result.advertisementData.advName;
            if (_matchesName(name)) _results[result.device.remoteId.str] = result;
          }
        });
      });
      if (mounted) setState(() => _scanning = true);
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 12));
      if (mounted) setState(() => _scanning = false);
    } catch (error) {
      if (mounted) setState(() {
        _scanning = false;
        _error = _clean(error);
      });
    }
  }

  bool _matchesName(String name) => name.toUpperCase().startsWith(_config.normalizedNamePrefix);

  Future<void> _stopScan() async {
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    if (mounted) setState(() => _scanning = false);
  }

  Future<void> _connect(ScanResult result) async {
    await _stopScan();
    if (!_config.isConfigured) {
      setState(() => _error = 'U-Link BLE protocol has not been configured yet.');
      return;
    }
    setState(() {
      _connecting = true;
      _error = null;
    });
    final client = UlinkBleProvisioningClient(config: _config);
    try {
      await client.connect(result.device);
      if (!mounted) {
        await client.disconnect();
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => UlinkWifiProvisioningScreen(client: client),
        ),
      );
    } catch (error) {
      await client.disconnect();
      if (mounted) setState(() => _error = _clean(error));
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  String _clean(Object error) => error.toString().replaceFirst(RegExp(r'^(StateError|Exception):\s*'), '');

  @override
  void dispose() {
    _stopScan();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final devices = _results.values.toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));
    return Scaffold(
      appBar: AppBar(title: const Text('Choose U-Link device')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(child: Text(_scanning ? 'Scanning nearby U-Link devices…' : 'Select a nearby U-Link device.')),
                  IconButton(
                    onPressed: _connecting ? null : _startScan,
                    tooltip: 'Scan again',
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            Expanded(
              child: devices.isEmpty
                  ? const Center(child: Text('No matching U-Link advertisements found.'))
                  : ListView.separated(
                      itemCount: devices.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final result = devices[index];
                        final name = result.advertisementData.advName;
                        return ListTile(
                          enabled: !_connecting,
                          title: Text(name.isEmpty ? 'Unnamed U-Link device' : name),
                          subtitle: Text('${result.device.remoteId.str}  •  RSSI ${result.rssi} dBm'),
                          trailing: _connecting ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.chevron_right),
                          onTap: () => _connect(result),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
