import 'dart:async';

import 'package:flutter/foundation.dart';
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
  final _nearby = <String, ScanResult>{};
  final _rawAdvertisementIds = <String>{};
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothAdapterState>? _adapterSubscription;
  BluetoothAdapterState _adapterState = BluetoothAdapterState.unknown;
  bool _scanning = false;
  bool _connecting = false;
  String _status = 'Preparing Bluetooth…';
  String? _error;
  String? _selectedId;
  DeviceDescriptor? _connected;

  @override
  void initState() {
    super.initState();
    if (!AppConfig.demoMode) {
      _adapterSubscription = FlutterBluePlus.adapterState.listen((state) {
        _log('adapter state: $state');
        if (mounted) setState(() => _adapterState = state);
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
  }

  Future<void> _scan() async {
    if (_scanning || _connecting) return;
    setState(() {
      _nearby.clear(); _rawAdvertisementIds.clear(); _selectedId = null; _connected = null; _error = null;
      _scanning = true; _status = 'Requesting Bluetooth permissions…';
    });
    try {
      if (AppConfig.demoMode) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        if (mounted) setState(() => _status = 'Demo gateway found. Select it to connect.');
        return;
      }
      final allowed = await context.read<ConnectionController>().requestBle();
      _log('BLE scan/connect permissions granted: $allowed');
      if (!allowed) throw StateError('Bluetooth permission is required. Allow Nearby devices/Bluetooth access, then retry.');
      if (!await FlutterBluePlus.isSupported) throw StateError('Bluetooth LE is not supported on this device.');
      _adapterState = FlutterBluePlus.adapterStateNow;
      if (_adapterState == BluetoothAdapterState.off) {
        await FlutterBluePlus.turnOn();
        _adapterState = FlutterBluePlus.adapterStateNow;
      }
      if (_adapterState != BluetoothAdapterState.on) throw StateError(_adapterMessage(_adapterState));

      await _scanSubscription?.cancel();
      _scanSubscription = FlutterBluePlus.scanResults.listen(_collect, onError: (Object error) {
        _log('scan stream failure: $error');
        if (mounted) setState(() => _error = 'BLE scan error: $error');
      });
      if (kDebugMode) FlutterBluePlus.setLogLevel(LogLevel.verbose, color: false);
      _log('starting unfiltered BLE scan for ${AppConfig.bleScanTimeout.inSeconds}s');
      await FlutterBluePlus.startScan(timeout: AppConfig.bleScanTimeout);
      await FlutterBluePlus.isScanning.where((scanning) => !scanning).first.timeout(
        AppConfig.bleScanTimeout + const Duration(seconds: 2),
      );
      if (mounted) {
        setState(() => _status = _rawAdvertisementIds.isEmpty
            ? 'No BLE advertisements were captured. UBM-Node1 may be Bluetooth Classic only, or ESP firmware may not be advertising a BLE local name/service.'
            : 'Scan complete: ${_nearby.length} recognized nearby device(s). Select one.');
      }
    } on TimeoutException {
      _log('scan completion timed out');
      if (mounted) setState(() => _status = 'Scan timed out. Select a result or retry.');
    } catch (error) {
      _log('scan failure: $error');
      if (mounted) setState(() => _error = _clean(error));
    } finally {
      await FlutterBluePlus.stopScan();
      _log('scan stopped');
      if (mounted) setState(() => _scanning = false);
    }
  }

  void _collect(List<ScanResult> results) {
    for (final result in results) {
      _rawAdvertisementIds.add(result.device.remoteId.str);
      final accepted = DeviceContract.matchesAdvertisingName(result.advertisementData.advName);
      _logAdvertisement(result, accepted: accepted);
      if (accepted) _nearby[result.device.remoteId.str] = result;
    }
    if (mounted) setState(() {});
  }

  void _logAdvertisement(ScanResult result, {required bool accepted}) {
    if (!kDebugMode) return;
    final data = result.advertisementData;
    final reason = accepted
        ? 'accepted: recognized ESP name (ULINK-GW-* or exact UBM-Node1)'
        : 'rejected: name is outside the intentional ESP allowlist';
    debugPrint('Ulink BLE scan: id=${result.device.remoteId.str} advName="${data.advName}" '
        'platformName="${result.device.platformName}" services=${data.serviceUuids} '
        'rssi=${result.rssi}; $reason');
  }

  DeviceDescriptor _descriptor(ScanResult result) {
    final name = result.advertisementData.advName;
    final label = name.isNotEmpty ? name : result.device.platformName.isNotEmpty
        ? result.device.platformName : 'BLE-${result.device.remoteId.str}';
    return DeviceDescriptor(
      mode: TransportType.ble, deviceId: label, gatewayId: label,
      serviceUuid: DeviceContract.defaultBleServiceUuid,
      advertisingName: name.isEmpty ? null : name,
      bleDeviceId: result.device.remoteId.str,
    );
  }

  Future<void> _connect() async {
    final result = _selectedId == null ? null : _nearby[_selectedId];
    if (result == null || _connecting) return;
    final descriptor = _descriptor(result);
    setState(() { _connecting = true; _error = null; _status = 'Connecting and discovering GATT services…'; });
    final success = await context.read<ConnectionController>().connect(descriptor);
    if (!mounted) return;
    setState(() {
      _connecting = false; _connected = success ? descriptor : null;
      _error = success ? null : _clean(context.read<ConnectionController>().errorMessage ?? 'Connection failed.');
      _status = success ? 'Connected. GATT services and characteristics were discovered.' : 'Disconnected. Select the device and retry.';
    });
  }

  Future<void> _connectDemo() async {
    final descriptor = DeviceDescriptor(mode: TransportType.ble, deviceId: 'ULINK-GW-TEST01', gatewayId: 'ULINK-GW-TEST01', serviceUuid: DeviceContract.defaultBleServiceUuid, advertisingName: 'ULINK-GW-TEST01');
    setState(() { _connecting = true; _status = 'Connecting to demo gateway…'; });
    final success = await context.read<ConnectionController>().connect(descriptor);
    if (mounted) setState(() { _connecting = false; _connected = success ? descriptor : null; _error = success ? null : context.read<ConnectionController>().errorMessage; _status = success ? 'Connected to demo gateway.' : 'Demo connection failed.'; });
  }

  String _name(ScanResult result) => result.advertisementData.advName.isNotEmpty
      ? result.advertisementData.advName : result.device.platformName.isNotEmpty
      ? result.device.platformName : 'Unnamed BLE device';

  String _adapterMessage(BluetoothAdapterState state) => switch (state) {
    BluetoothAdapterState.on => 'Bluetooth is ready.',
    BluetoothAdapterState.off => 'Bluetooth is off. Turn it on, then retry.',
    BluetoothAdapterState.unauthorized => 'Bluetooth permission is denied. Allow it in system settings.',
    BluetoothAdapterState.unavailable => 'Bluetooth is unavailable on this device.',
    BluetoothAdapterState.turningOn => 'Bluetooth is turning on…',
    BluetoothAdapterState.turningOff => 'Bluetooth is turning off…',
    BluetoothAdapterState.unknown => 'Bluetooth state is unavailable. Check adapter and permissions.',
  };
  String _clean(Object error) => error.toString().replaceFirst(RegExp(r'^(StateError|Exception):\s*'), '');
  void _log(String message) { if (kDebugMode) debugPrint('Ulink BLE: $message'); }

  @override
  void dispose() { _scanSubscription?.cancel(); _adapterSubscription?.cancel(); FlutterBluePlus.stopScan(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final devices = _nearby.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi));
    final demo = AppConfig.demoMode;
    return Scaffold(
      appBar: AppBar(title: const Text('Program a Device')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ListTile(contentPadding: EdgeInsets.zero, leading: Icon(demo || _adapterState == BluetoothAdapterState.on ? Icons.bluetooth_connected : Icons.bluetooth_disabled), title: Text(demo ? 'Demo Bluetooth mode' : _adapterMessage(_adapterState)), subtitle: Text(_status)),
          if (_error != null) _ErrorBanner(message: _error!),
          if (_scanning || _connecting) const LinearProgressIndicator(),
          const SizedBox(height: 8),
          Text('Nearby programmable BLE devices (${demo ? 1 : devices.length})', style: Theme.of(context).textTheme.titleMedium),
          const Text('Recognized ESP names only: ULINK-GW-* and UBM-Node1.'),
          Expanded(child: demo ? RadioListTile<String>(value: 'demo', groupValue: _selectedId, onChanged: (_) => setState(() => _selectedId = 'demo'), title: const Text('ULINK-GW-TEST01'), subtitle: const Text('Demo gateway')) : devices.isEmpty ? const Center(child: Text('No recognized BLE advertisements captured. Check debug logs, Bluetooth, and permissions, then scan again.')) : ListView.separated(itemCount: devices.length, separatorBuilder: (_, _) => const Divider(height: 1), itemBuilder: (_, index) {
            final result = devices[index]; final services = result.advertisementData.serviceUuids;
            return RadioListTile<String>(value: result.device.remoteId.str, groupValue: _selectedId, onChanged: _connecting ? null : (value) => setState(() => _selectedId = value), title: Text(_name(result)), subtitle: Text('ID: ${result.device.remoteId.str}\nRSSI: ${result.rssi} dBm • services: ${services.isEmpty ? 'none advertised' : services.join(', ')}'), isThreeLine: true, secondary: const Icon(Icons.bluetooth));
          })),
          OutlinedButton.icon(onPressed: _scanning || _connecting ? null : _scan, icon: const Icon(Icons.refresh), label: const Text('Scan again')),
          if (_selectedId != null) FilledButton.icon(onPressed: _connecting ? null : (demo ? _connectDemo : _connect), icon: const Icon(Icons.link), label: Text(_connecting ? 'Connecting / discovering…' : 'Connect selected device')),
          if (_connected != null) FilledButton.icon(onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const WifiProvisioningScreen())), icon: const Icon(Icons.arrow_forward), label: const Text('Continue to provisioning')),
        ]),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Theme.of(context).colorScheme.errorContainer, borderRadius: BorderRadius.circular(8)), child: Text(message, style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)));
}
