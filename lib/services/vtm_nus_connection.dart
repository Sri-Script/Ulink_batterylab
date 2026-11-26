import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../config/app_config.dart';
import '../config/vtm_nus_contract.dart';

typedef VtmBleConnection = VtmNusConnection;

/// Isolated Nordic UART client for Battery Mobile ESP programming.
///
/// It intentionally does not implement the Ulink DeviceConnection API: VTM is
/// a UART terminal and must never receive Ulink protocol commands on connect.
class VtmNusConnection {
  static const _vtmScanTimeout = Duration(seconds: 15);
  VtmNusConnection({
    required this.selectedName,
    required this.selectedRemoteId,
  });

  final String selectedName;
  final String selectedRemoteId;
  final _receivedTextController = StreamController<String>.broadcast();
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  StreamSubscription<List<int>>? _notificationSubscription;
  BluetoothDevice? _device;
  BluetoothCharacteristic? _rxCharacteristic;
  BluetoothCharacteristic? _txCharacteristic;
  bool _notificationsEnabled = false;
  bool _connected = false;
  Future<void>? _connectInFlight;
  String _diagnostics = '';

  Stream<String> get receivedText => _receivedTextController.stream;
  bool get isConnected => _connected;
  String get diagnostics => _diagnostics;

  Future<void> connect() {
    final inFlight = _connectInFlight;
    if (inFlight != null) {
      _log('connect ignored: an attempt is already active');
      return inFlight;
    }
    final attempt = _connectInternal();
    _connectInFlight = attempt;
    return attempt.whenComplete(() => _connectInFlight = null);
  }

  Future<void> _connectInternal() async {
    try {
      Object? lastError;
      for (var attempt = 1; attempt <= 3; attempt++) {
        try {
          await _connectAttempt(attempt);
          return;
        } catch (error) {
          lastError = error;
          await _cleanup(disconnect: true);
          if (attempt < 3) {
            _log('retrying VTM connection after attempt $attempt failure');
            await Future<void>.delayed(const Duration(seconds: 1));
          }
        }
      }
      throw lastError!;
    } catch (error) {
      _log('connect failure: $error');
      await _cleanup(disconnect: true);
      rethrow;
    }
  }

  Future<void> _connectAttempt(int attempt) async {
      final freshResult = await _findFreshSelectedAdvertisement();
      _device = freshResult.device;
      _log('fresh-scan match attempt=$attempt: name="$selectedName" id=${_device!.remoteId.str} rssi=${freshResult.rssi}');
      await FlutterBluePlus.stopScan();
      _log('scan stopped immediately before connect');

      final connected = Completer<void>();
      await _connectionSubscription?.cancel();
      _connectionSubscription = _device!.connectionState.listen((state) {
        _connected = state == BluetoothConnectionState.connected;
        _log('connection state: $state');
        if (_connected && !connected.isCompleted) connected.complete();
        if (!_connected) {
          _notificationsEnabled = false;
          _notificationSubscription?.cancel();
          _notificationSubscription = null;
        }
      });
      _log('connecting with autoConnect=false');
      try {
        await _device!.connect(
          autoConnect: false,
          timeout: AppConfig.connectionTimeout,
          mtu: null,
        );
        await connected.future.timeout(AppConfig.connectionTimeout);
      } on TimeoutException {
        throw TimeoutException(
          'VTM device was found but did not accept the Bluetooth connection. '
          'Scan again and retry.',
        );
      }

      await Future<void>.delayed(const Duration(milliseconds: 750));
      try {
        await (_device! as dynamic).clearGattCache();
        _log('VTM-only GATT cache cleared');
      } catch (error) {
        _log('VTM GATT cache clear unavailable/failed: $error');
      }
      var services = await _device!.discoverServices();
      _logGatt(services);
      var service = services.cast<BluetoothService?>().firstWhere(
            (candidate) => candidate != null &&
                VtmNusContract.sameUuid(
                  candidate.uuid,
                  VtmNusContract.serviceUuid,
                ),
            orElse: () => null,
          );
      if (service == null) {
        _log('NUS service absent; rediscovering after 1 second.');
        await Future<void>.delayed(const Duration(seconds: 1));
        services = await _device!.discoverServices();
        _logGatt(services);
        service = services.cast<BluetoothService?>().firstWhere(
          (candidate) => candidate != null && VtmNusContract.sameUuid(candidate.uuid, VtmNusContract.serviceUuid),
          orElse: () => null,
        );
        // If NUS is still absent, continue with the generic terminal fallback.
      }

      if (service == null) {
        service = _fallbackService(services);
        if (service == null) {
          _diagnostics = _servicesDescription(services);
          throw StateError('VTM device connected, but no usable data service was discovered. Restart the device, scan again, and retry.');
        }
        _log('generic VTM UART profile selected: ${service.uuid}');
      }

      _rxCharacteristic = service.characteristics.cast<BluetoothCharacteristic?>().firstWhere(
            (candidate) => candidate != null &&
                VtmNusContract.sameUuid(candidate.uuid, VtmNusContract.rxUuid),
            orElse: () => null,
          );
      _txCharacteristic = service.characteristics.cast<BluetoothCharacteristic?>().firstWhere(
            (candidate) => candidate != null &&
                VtmNusContract.sameUuid(candidate.uuid, VtmNusContract.txUuid),
            orElse: () => null,
          );
      _rxCharacteristic ??= service.characteristics.firstWhere(
        (candidate) => candidate.properties.write || candidate.properties.writeWithoutResponse,
        orElse: () => throw StateError('VTM fallback service has no writable characteristic.'),
      );
      _txCharacteristic ??= service.characteristics.firstWhere(
        (candidate) => candidate.properties.notify || candidate.properties.indicate || candidate.properties.read,
        orElse: () => throw StateError('VTM fallback service has no readable or notifying characteristic.'),
      );
      if (_rxCharacteristic == null || _txCharacteristic == null) {
        _log('NUS RX/TX missing; discovered characteristics: '
            '${service.characteristics.map(_characteristicDescription).join('; ')}');
        _diagnostics = 'Characteristics: ${service.characteristics.map(_characteristicDescription).join('; ')}';
        throw StateError('The selected VTM device is missing Nordic UART RX or TX.');
      }
      if (!_rxCharacteristic!.properties.write &&
          !_rxCharacteristic!.properties.writeWithoutResponse) {
        throw StateError('VTM Nordic UART RX is not writable.');
      }

      await _notificationSubscription?.cancel();
      _notificationSubscription = _txCharacteristic!.onValueReceived.listen((bytes) {
        final text = utf8.decode(bytes, allowMalformed: true);
        _log('TX notification: $bytes -> "$text"');
        _receivedTextController.add(text);
      });
      if (_txCharacteristic!.properties.notify || _txCharacteristic!.properties.indicate) {
        await _txCharacteristic!.setNotifyValue(true);
        _notificationsEnabled = true;
        _log('VTM notification subscription enabled');
      }
      _log('NUS ready: RX=${_rxCharacteristic!.uuid}, TX=${_txCharacteristic!.uuid}');
  }

  BluetoothService? _fallbackService(List<BluetoothService> services) {
    const system = {'1800', '1801', '180a', '180f'};
    for (final candidate in services) {
      final uuid = candidate.uuid.toString().toLowerCase();
      if (system.contains(uuid) || system.any((id) => uuid.endsWith(id))) continue;
      final writable = candidate.characteristics.any((c) => c.properties.write || c.properties.writeWithoutResponse);
      final incoming = candidate.characteristics.any((c) => c.properties.notify || c.properties.indicate || c.properties.read);
      if (writable && incoming) return candidate;
    }
    return null;
  }

  String _servicesDescription(List<BluetoothService> services) => services.map((s) => '${s.uuid} [${s.characteristics.map(_characteristicDescription).join(', ')}]').join('; ');

  Future<ScanResult> _findFreshSelectedAdvertisement() async {
    await FlutterBluePlus.stopScan();
    _log('starting unfiltered fresh scan for "$selectedName"');
    await FlutterBluePlus.startScan(timeout: _vtmScanTimeout);
    try {
      return await FlutterBluePlus.scanResults
          .expand((results) => results)
          .firstWhere((result) {
        final data = result.advertisementData;
        final name = data.advName;
        _log('advertisement: name="$name" id=${result.device.remoteId.str} '
            'rssi=${result.rssi} services=${data.serviceUuids}');
        return VtmNusContract.matchesFreshAdvertisement(
          advertisedName: name,
          remoteId: result.device.remoteId.str,
          selectedName: selectedName,
          selectedRemoteId: selectedRemoteId,
        );
      }).timeout(_vtmScanTimeout);
    } on TimeoutException {
      throw TimeoutException(
        'VTM device is not advertising. Restart or wake the device, then scan again.',
      );
    }
  }

  Future<void> writeText(String text) async {
    final characteristic = _rxCharacteristic;
    if (!_connected || characteristic == null) {
      throw StateError('VTM UART is disconnected. Reconnect before writing.');
    }
    final bytes = utf8.encode(text);
    final withoutResponse = !characteristic.properties.write &&
        characteristic.properties.writeWithoutResponse;
    _log('RX write (${withoutResponse ? 'without response' : 'with response'}): '
        '$bytes -> "$text"');
    await characteristic.write(bytes, withoutResponse: withoutResponse);
  }

  Future<void> disconnect() => _cleanup(disconnect: true);

  Future<void> _cleanup({required bool disconnect}) async {
    _log('cleanup start (disconnect=$disconnect)');
    final tx = _txCharacteristic;
    if (_notificationsEnabled && tx != null) {
      try {
        await tx.setNotifyValue(false);
        _log('notifications disabled');
      } catch (error) {
        _log('could not disable notifications during cleanup: $error');
      }
    }
    await _notificationSubscription?.cancel();
    await _connectionSubscription?.cancel();
    _notificationSubscription = null;
    _connectionSubscription = null;
    if (disconnect) {
      try {
        await _device?.disconnect();
        _log('device disconnected');
      } catch (error) {
        _log('disconnect during cleanup failed: $error');
      }
    }
    _notificationsEnabled = false;
    _connected = false;
    _rxCharacteristic = null;
    _txCharacteristic = null;
    _device = null;
    _log('cleanup complete; VTM handles cleared');
  }

  Future<void> dispose() async {
    await _cleanup(disconnect: true);
    await _receivedTextController.close();
  }

  String _characteristicDescription(BluetoothCharacteristic characteristic) =>
      '${characteristic.uuid} (${characteristic.properties})';

  void _logGatt(List<BluetoothService> services) {
    _log('discovered services/characteristics: ${_servicesDescription(services)}');
  }

  void _log(String message) {
    if (kDebugMode) debugPrint('VTM NUS: $message');
  }
}
