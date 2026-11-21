import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../services/permission_service.dart';
import '../services/ulink_ble_protocol_config.dart';
import '../services/ulink_ble_provisioning_client.dart';
import '../services/ulink_login_preferences.dart';
import 'ulink_login_screen.dart';
import 'ulink_wifi_provisioning_screen.dart';

typedef UlinkSettingsClientConnector =
    Future<UlinkSettingsClient> Function(
      BluetoothDevice device,
      UlinkBleProtocolConfig config,
    );

class UlinkDevicePickerScreen extends StatefulWidget {
  const UlinkDevicePickerScreen({
    super.key,
    this.config,
    this.loginPreferences,
    this.initialResults = const <ScanResult>[],
    this.startScanning = true,
    this.clientConnector,
  });
  final UlinkBleProtocolConfig? config;
  final UlinkLoginPreferences? loginPreferences;
  final List<ScanResult> initialResults;
  final bool startScanning;
  final UlinkSettingsClientConnector? clientConnector;

  @override
  State<UlinkDevicePickerScreen> createState() =>
      _UlinkDevicePickerScreenState();
}

class _UlinkDevicePickerScreenState extends State<UlinkDevicePickerScreen> {
  late final UlinkBleProtocolConfig _config =
      widget.config ?? UlinkBleProtocolConfig.environment;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  final Map<String, ScanResult> _results = <String, ScanResult>{};
  bool _scanning = false;
  bool _connecting = false;
  bool _loggingOut = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final result in widget.initialResults) {
      _results[result.device.remoteId.str] = result;
    }
    if (widget.startScanning) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startScan());
    }
  }

  Future<void> _startScan() async {
    await _stopScan();
    setState(() {
      _error = null;
      _results.clear();
    });
    try {
      if (!await PermissionService().requestBle()) {
        throw StateError(
          'Bluetooth permission is required to find U-Link devices.',
        );
      }
      if (!await FlutterBluePlus.isSupported) {
        throw StateError('Bluetooth LE is not supported on this device.');
      }
      await _waitForBluetoothOn();
      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        if (!mounted) return;
        setState(() {
          for (final result in results) {
            final name = result.advertisementData.advName;
            if (_matchesName(name)) {
              _results[result.device.remoteId.str] = result;
            }
          }
        });
      });
      if (mounted) setState(() => _scanning = true);
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 12));
      if (mounted) setState(() => _scanning = false);
    } catch (error) {
      if (mounted) {
        setState(() {
          _scanning = false;
          _error = _clean(error);
        });
      }
    }
  }

  bool _matchesName(String name) =>
      name.toUpperCase().startsWith(_config.normalizedNamePrefix);

  Future<void> _waitForBluetoothOn() async {
    // Subscribe before requesting Bluetooth so a phone that changes state
    // immediately still delivers its ON event. The stream, rather than the
    // cached state alone, is the readiness signal for starting a scan.
    final adapterOn = FlutterBluePlus.adapterState
        .where((state) => state == BluetoothAdapterState.on)
        .timeout(
          const Duration(seconds: 10),
          onTimeout: (sink) => sink.addError(
            StateError('Turn on Bluetooth to scan for U-Link devices.'),
          ),
        )
        .first;
    if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
      await FlutterBluePlus.turnOn();
    }
    await adapterOn;
  }

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
      setState(() {
        _error =
            _config.validationError ??
            'U-Link BLE protocol has not been configured yet.';
      });
      return;
    }
    setState(() {
      _connecting = true;
      _error = null;
    });
    final connector = widget.clientConnector;
    UlinkSettingsClient? client;
    try {
      if (connector == null) {
        final bleClient = UlinkBleProvisioningClient(config: _config);
        await bleClient.connect(result.device);
        client = bleClient;
      } else {
        client = await connector(result.device, _config);
      }
      if (!mounted) {
        await client!.disconnect();
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => UlinkWifiProvisioningScreen(client: client!),
        ),
      );
    } catch (error) {
      await client?.disconnect();
      if (mounted) setState(() => _error = _clean(error));
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _logout() async {
    if (_loggingOut) return;
    setState(() => _loggingOut = true);
    try {
      try {
        await (widget.loginPreferences ??
                SharedPreferencesUlinkLoginPreferences())
            .clearEmail();
      } finally {
        if (Firebase.apps.isNotEmpty) await FirebaseAuth.instance.signOut();
      }
      if (!mounted) return;
      await Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const UlinkLoginScreen()),
        (route) => route.isFirst,
      );
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not sign out. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _loggingOut = false);
    }
  }

  String _clean(Object error) =>
      error.toString().replaceFirst(RegExp(r'^(StateError|Exception):\s*'), '');

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
      appBar: AppBar(
        title: const Text('Choose U-Link device'),
        actions: [
          UlinkLogoutButton(
            loginPreferences: widget.loginPreferences,
            onLoggedOut: _logout,
            loggingOut: _loggingOut,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _scanning
                          ? 'Scanning nearby U-Link devices…'
                          : 'Select a nearby U-Link device.',
                    ),
                  ),
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
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Expanded(
              child: devices.isEmpty
                  ? const Center(
                      child: Text('No matching U-Link advertisements found.'),
                    )
                  : ListView.separated(
                      itemCount: devices.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final result = devices[index];
                        final name = result.advertisementData.advName;
                        return ListTile(
                          enabled: !_connecting,
                          title: Text(
                            name.isEmpty ? 'Unnamed U-Link device' : name,
                          ),
                          subtitle: Text(
                            '${result.device.remoteId.str}  •  RSSI ${result.rssi} dBm',
                          ),
                          trailing: _connecting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.chevron_right),
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

class UlinkLogoutButton extends StatelessWidget {
  const UlinkLogoutButton({
    super.key,
    this.loginPreferences,
    this.onLoggedOut,
    this.loggingOut = false,
  });

  final UlinkLoginPreferences? loginPreferences;
  final Future<void> Function()? onLoggedOut;
  final bool loggingOut;

  Future<void> _logout(BuildContext context) async {
    if (onLoggedOut != null) {
      await onLoggedOut!();
      return;
    }
    try {
      try {
        await (loginPreferences ?? SharedPreferencesUlinkLoginPreferences())
            .clearEmail();
      } finally {
        if (Firebase.apps.isNotEmpty) await FirebaseAuth.instance.signOut();
      }
      if (context.mounted) {
        await Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute<void>(builder: (_) => const UlinkLoginScreen()),
          (route) => route.isFirst,
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not sign out. Please try again.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: loggingOut ? null : () => _logout(context),
    icon: const Icon(Icons.logout),
    tooltip: 'Log out',
  );
}
