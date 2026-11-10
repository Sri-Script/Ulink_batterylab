import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ulink_ble_protocol_config.dart';

/// The provisional ESP contract is newline-delimited UTF-8 JSON:
/// {"op":"set_wifi","requestId":"...","ssid":"...","password":"..."}\n
/// and the ESP must reply with a matching `ack` message. This is intentionally
/// separate from the legacy Battery Monitor BLE transport.
class UlinkProvisioningProtocol {
  const UlinkProvisioningProtocol._();

  static String? validateCredentials(String ssid, String password) {
    final ssidBytes = utf8.encode(ssid).length;
    if (ssidBytes < 1 || ssidBytes > 32) {
      return 'SSID must be between 1 and 32 UTF-8 bytes.';
    }
    if (password.isNotEmpty) {
      final passwordBytes = utf8.encode(password).length;
      if (passwordBytes < 8 || passwordBytes > 63) {
        return 'Wi-Fi password must be 8 to 63 UTF-8 bytes, or empty for an open network.';
      }
    }
    return null;
  }

  static List<int> encodeSetWifi({
    required String requestId,
    required String ssid,
    required String password,
  }) => utf8.encode(
    '${jsonEncode({
      'op': 'set_wifi',
      'requestId': requestId,
      'ssid': ssid,
      'password': password,
    })}\n',
  );
}

sealed class UlinkProtocolEvent {
  const UlinkProtocolEvent();
}

class UlinkAckEvent extends UlinkProtocolEvent {
  const UlinkAckEvent({
    required this.requestId,
    required this.status,
    this.message,
  });

  final String requestId;
  final String status;
  final String? message;
}

class UlinkMalformedEvent extends UlinkProtocolEvent {
  const UlinkMalformedEvent();
}

/// Buffers byte fragments so a UTF-8 character or JSON line may safely span
/// BLE notifications. Multiple newline-delimited messages are handled too.
class UlinkAckParser {
  final List<int> _pending = <int>[];

  List<UlinkProtocolEvent> add(List<int> bytes) {
    _pending.addAll(bytes);
    final events = <UlinkProtocolEvent>[];
    while (true) {
      final newline = _pending.indexOf(10);
      if (newline < 0) return events;
      final line = _pending.sublist(0, newline);
      _pending.removeRange(0, newline + 1);
      if (line.isEmpty) continue;
      try {
        final decoded = utf8.decode(line);
        final value = jsonDecode(decoded);
        if (value is! Map<String, dynamic> ||
            value['op'] != 'ack' ||
            value['requestId'] is! String ||
            value['status'] is! String) {
          events.add(const UlinkMalformedEvent());
          continue;
        }
        events.add(UlinkAckEvent(
          requestId: value['requestId'] as String,
          status: value['status'] as String,
          message: value['message'] is String ? value['message'] as String : null,
        ));
      } on FormatException {
        events.add(const UlinkMalformedEvent());
      }
    }
  }
}

class UlinkProvisioningException implements Exception {
  const UlinkProvisioningException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Couples a successful GATT write to the separate device-level proof that
/// firmware accepted the command. Calling [wait] without [accept]ing a
/// matching ACK always times out; a write callback has no path to success.
class UlinkAcknowledgementGate {
  UlinkAcknowledgementGate(this.requestId, {required this.safeMessage});

  final String requestId;
  final String Function(String? message) safeMessage;
  final Completer<void> _completion = Completer<void>();
  String? _failure;

  bool get isAcknowledged => _completion.isCompleted && _failure == null;

  void accept(UlinkProtocolEvent event) {
    if (_completion.isCompleted) return;
    if (event is UlinkMalformedEvent) {
      fail('U-Link sent an invalid provisioning response.');
    } else if (event is UlinkAckEvent) {
      if (event.requestId != requestId) {
        fail('U-Link acknowledged a different provisioning request.');
      } else if (event.status == 'ok') {
        _completion.complete();
      } else if (event.status == 'error') {
        fail(safeMessage(event.message));
      } else {
        fail('U-Link returned an invalid provisioning status.');
      }
    }
  }

  void fail(String message) {
    _failure = message;
    if (!_completion.isCompleted) _completion.complete();
  }

  Future<void> wait(Duration timeout) async {
    await _completion.future.timeout(
      timeout,
      onTimeout: () => throw const UlinkProvisioningException(
        'Timed out waiting for U-Link to acknowledge the credentials.',
      ),
    );
    if (_failure != null) throw UlinkProvisioningException(_failure!);
  }
}

/// A narrowly-scoped GATT client for U-Link provisioning. It never chooses a
/// "first" service/characteristic and it never treats a write callback as an
/// ESP acknowledgement.
class UlinkBleProvisioningClient {
  UlinkBleProvisioningClient({UlinkBleProtocolConfig? config})
    : config = config ?? UlinkBleProtocolConfig.environment;

  final UlinkBleProtocolConfig config;
  final UlinkAckParser _parser = UlinkAckParser();
  BluetoothDevice? _device;
  BluetoothCharacteristic? _command;
  BluetoothCharacteristic? _response;
  StreamSubscription<List<int>>? _responseSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  UlinkAcknowledgementGate? _pendingGate;

  String get deviceName => _device?.platformName.trim().isNotEmpty == true
      ? _device!.platformName
      : _device?.remoteId.str ?? 'U-Link device';

  Future<void> connect(BluetoothDevice device) async {
    if (!config.isConfigured) {
      throw const UlinkProvisioningException(
        'U-Link BLE protocol has not been configured yet.',
      );
    }
    _device = device;
    try {
      if (Platform.isAndroid) {
        // This flutter_blue_plus version exposes Android's native bond API.
        try {
          await device.createBond();
        } catch (_) {
          // GATT access can still trigger Android's normal pairing UI.
        }
      }
      await device.connect(timeout: const Duration(seconds: 15));
      _connectionSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _failPending('U-Link disconnected before it acknowledged the credentials.');
        }
      });
      final services = await device.discoverServices();
      final service = services.cast<BluetoothService?>().firstWhere(
        (item) => item != null && _sameUuid(item.uuid.str, config.serviceUuid),
        orElse: () => null,
      );
      if (service == null) {
        throw const UlinkProvisioningException('Configured U-Link BLE service was not found.');
      }
      _command = service.characteristics.cast<BluetoothCharacteristic?>().firstWhere(
        (item) => item != null && _sameUuid(item.uuid.str, config.commandCharacteristicUuid),
        orElse: () => null,
      );
      _response = service.characteristics.cast<BluetoothCharacteristic?>().firstWhere(
        (item) => item != null && _sameUuid(item.uuid.str, config.responseCharacteristicUuid),
        orElse: () => null,
      );
      if (_command == null || _response == null) {
        throw const UlinkProvisioningException(
          'Configured U-Link command or response characteristic was not found.',
        );
      }
      if (!_command!.properties.write ||
          (!_response!.properties.notify && !_response!.properties.indicate)) {
        throw const UlinkProvisioningException(
          'Configured U-Link characteristics do not support acknowledged provisioning.',
        );
      }
      _responseSubscription = _response!.onValueReceived.listen(_onResponse);
      await _response!.setNotifyValue(true);
    } catch (_) {
      await disconnect();
      rethrow;
    }
  }

  Future<void> provision({required String ssid, required String password}) async {
    final validation = UlinkProvisioningProtocol.validateCredentials(ssid, password);
    if (validation != null) throw UlinkProvisioningException(validation);
    final command = _command;
    if (command == null || _response == null || _device == null) {
      throw const UlinkProvisioningException('Connect to a U-Link device before provisioning.');
    }
    if (_pendingGate != null) {
      throw const UlinkProvisioningException('A provisioning request is already pending.');
    }
    final requestId = '${DateTime.now().microsecondsSinceEpoch}-${_device!.remoteId.str.hashCode.abs()}';
    final gate = UlinkAcknowledgementGate(
      requestId,
      safeMessage: _safeDeviceMessage,
    );
    _pendingGate = gate;
    try {
      // A completed write only means Android/GATT accepted it. Success still
      // requires the matching ESP acknowledgement below.
      await command.write(
        UlinkProvisioningProtocol.encodeSetWifi(
          requestId: requestId,
          ssid: ssid,
          password: password,
        ),
        withoutResponse: false,
      );
      await gate.wait(config.ackTimeout);
    } finally {
      _pendingGate = null;
    }
  }

  void _onResponse(List<int> bytes) {
    for (final event in _parser.add(bytes)) {
      _pendingGate?.accept(event);
    }
  }

  void _failPending(String message) {
    _pendingGate?.fail(message);
  }

  static String _safeDeviceMessage(String? message) {
    final text = message?.replaceAll(RegExp(r'[\r\n\t]'), ' ').trim();
    if (text == null || text.isEmpty) return 'U-Link rejected the Wi-Fi credentials.';
    return text.length > 160 ? '${text.substring(0, 160)}…' : text;
  }

  Future<void> disconnect() async {
    await _responseSubscription?.cancel();
    await _connectionSubscription?.cancel();
    _responseSubscription = null;
    _connectionSubscription = null;
    final response = _response;
    _response = null;
    _command = null;
    if (response != null) {
      try {
        await response.setNotifyValue(false);
      } catch (_) {}
    }
    final device = _device;
    _device = null;
    if (device != null) {
      try {
        await device.disconnect();
      } catch (_) {}
    }
  }

  static bool _sameUuid(String left, String right) =>
      left.toLowerCase() == right.trim().toLowerCase();
}
