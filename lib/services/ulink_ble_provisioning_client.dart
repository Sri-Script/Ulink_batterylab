import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ulink_ble_protocol_config.dart';

enum UlinkSettingsKey { ssid, password, apn, mode }

extension UlinkSettingsKeyWireName on UlinkSettingsKey {
  String get wireName => switch (this) {
    UlinkSettingsKey.ssid => 'ssid',
    UlinkSettingsKey.password => 'password',
    UlinkSettingsKey.apn => 'apn',
    UlinkSettingsKey.mode => 'mode',
  };
}

class UlinkSettings {
  const UlinkSettings({
    required this.ssid,
    required this.password,
    required this.apn,
    required this.mode,
  });

  final String ssid;
  final String password;
  final String apn;
  final String mode;

  String valueFor(UlinkSettingsKey key) => switch (key) {
    UlinkSettingsKey.ssid => ssid,
    UlinkSettingsKey.password => password,
    UlinkSettingsKey.apn => apn,
    UlinkSettingsKey.mode => mode,
  };
}

/// The Rev4 U-Link settings protocol is line-delimited UTF-8 JSON. The
/// password is deliberately never included in diagnostics or exceptions.
class UlinkSettingsProtocol {
  const UlinkSettingsProtocol._();

  static const getSettingsCommand = 'GET_SETTINGS\n';

  static String encodeSet(UlinkSettingsKey key, String value) =>
      '${jsonEncode(<String, String>{'cmd': 'SET', 'key': key.wireName, 'value': value})}\n';

  static String? validate(UlinkSettingsKey key, String value) {
    final limit = switch (key) {
      UlinkSettingsKey.ssid => 32,
      UlinkSettingsKey.password || UlinkSettingsKey.apn => 64,
      UlinkSettingsKey.mode => 4,
    };
    final minimum = key == UlinkSettingsKey.ssid ? 1 : 0;
    if (value.length < minimum || value.length > limit) {
      return '${key.wireName == 'ssid' ? 'SSID' : key.wireName.toUpperCase()} must be between $minimum and $limit printable characters.';
    }
    if (!_isPrintableAscii(value)) {
      return '${key.wireName == 'ssid' ? 'SSID' : key.wireName.toUpperCase()} contains unsupported control or non-printable characters.';
    }
    if (key == UlinkSettingsKey.mode && value != 'WIFI' && value != 'GSM') {
      return 'Mode must be WIFI or GSM.';
    }
    return null;
  }

  static bool _isPrintableAscii(String value) =>
      value.codeUnits.every((unit) => unit >= 0x20 && unit <= 0x7e);
}

sealed class UlinkProtocolEvent {
  const UlinkProtocolEvent();
}

class UlinkSettingsEvent extends UlinkProtocolEvent {
  const UlinkSettingsEvent(this.settings);
  final UlinkSettings settings;
}

class UlinkSetReplyEvent extends UlinkProtocolEvent {
  const UlinkSetReplyEvent({required this.ok, this.key, this.saved});

  final bool ok;
  final String? key;
  final bool? saved;
}

class UlinkMalformedEvent extends UlinkProtocolEvent {
  const UlinkMalformedEvent();
}

/// Buffers byte fragments so UTF-8 and JSON lines may span BLE notifications.
/// Each newline-delimited frame is decoded independently, including when a
/// single notification carries multiple frames.
class UlinkSettingsParser {
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
      events.add(_parse(line));
    }
  }

  UlinkProtocolEvent _parse(List<int> bytes) {
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) return const UlinkMalformedEvent();
      final value = Map<String, dynamic>.from(decoded);
      if (value['ok'] is! bool) return const UlinkMalformedEvent();
      if (value['ok'] == true && value['event'] == 'settings') {
        final ssid = value['ssid'];
        final password = value['password'];
        final apn = value['apn'];
        final mode = value['mode'];
        if (ssid is! String ||
            password is! String ||
            apn is! String ||
            mode is! String ||
            UlinkSettingsProtocol.validate(UlinkSettingsKey.ssid, ssid) !=
                null ||
            UlinkSettingsProtocol.validate(
                  UlinkSettingsKey.password,
                  password,
                ) !=
                null ||
            UlinkSettingsProtocol.validate(UlinkSettingsKey.apn, apn) != null ||
            UlinkSettingsProtocol.validate(UlinkSettingsKey.mode, mode) !=
                null) {
          return const UlinkMalformedEvent();
        }
        return UlinkSettingsEvent(
          UlinkSettings(ssid: ssid, password: password, apn: apn, mode: mode),
        );
      }
      if (value['ok'] == false ||
          (value['key'] is String && value['saved'] is bool)) {
        return UlinkSetReplyEvent(
          ok: value['ok'] as bool,
          key: value['key'] is String ? value['key'] as String : null,
          saved: value['saved'] is bool ? value['saved'] as bool : null,
        );
      }
    } on FormatException {
      // The common malformed UTF-8/JSON case is represented below.
    }
    return const UlinkMalformedEvent();
  }
}

class UlinkSettingsException implements Exception {
  const UlinkSettingsException(this.message);
  final String message;

  @override
  String toString() => message;
}

abstract class _UlinkResponseGate<T> {
  void accept(UlinkProtocolEvent event);
  void fail(String message);
  Future<T> wait(Duration timeout);
}

class UlinkSettingsResponseGate implements _UlinkResponseGate<UlinkSettings> {
  final Completer<UlinkSettings> _completion = Completer<UlinkSettings>();

  @override
  void accept(UlinkProtocolEvent event) {
    if (_completion.isCompleted) return;
    if (event is UlinkMalformedEvent) {
      fail('U-Link sent an invalid settings response.');
    } else if (event is UlinkSettingsEvent) {
      _completion.complete(event.settings);
    } else if (event is UlinkSetReplyEvent && !event.ok) {
      fail('U-Link could not return its settings.');
    }
  }

  @override
  void fail(String message) {
    if (!_completion.isCompleted) {
      _completion.completeError(UlinkSettingsException(message));
    }
  }

  @override
  Future<UlinkSettings> wait(Duration timeout) => _completion.future.timeout(
    timeout,
    onTimeout: () => throw const UlinkSettingsException(
      'Timed out waiting for U-Link settings.',
    ),
  );
}

class UlinkSetResponseGate implements _UlinkResponseGate<void> {
  UlinkSetResponseGate(this.key);

  final UlinkSettingsKey key;
  final Completer<void> _completion = Completer<void>();

  @override
  void accept(UlinkProtocolEvent event) {
    if (_completion.isCompleted) return;
    if (event is UlinkMalformedEvent) {
      fail('U-Link sent an invalid save response.');
    } else if (event is UlinkSetReplyEvent) {
      if (!event.ok) {
        fail('U-Link rejected this setting.');
      } else if (event.key != key.wireName) {
        fail('U-Link replied for a different setting.');
      } else if (event.saved != true) {
        fail('U-Link did not confirm that the setting was saved.');
      } else {
        _completion.complete();
      }
    }
  }

  @override
  void fail(String message) {
    if (!_completion.isCompleted) {
      _completion.completeError(UlinkSettingsException(message));
    }
  }

  @override
  Future<void> wait(Duration timeout) => _completion.future.timeout(
    timeout,
    onTimeout: () => throw UlinkSettingsException(
      'Timed out saving ${key.wireName == 'password' ? 'the password' : key.wireName}.',
    ),
  );
}

abstract class UlinkSettingsClient {
  String get deviceName;
  UlinkSettings? get latestSettings;
  Stream<UlinkProtocolEvent> get events;
  Future<UlinkSettings> refreshSettings();
  Future<void> saveSetting(UlinkSettingsKey key, String value);
  Future<void> disconnect();
}

/// A narrowly-scoped GATT client for Rev4 U-Link settings. It uses only the
/// configured U-Link service/characteristics and relies on Android/NimBLE for
/// BLE link encryption and pairing.
class UlinkBleProvisioningClient implements UlinkSettingsClient {
  UlinkBleProvisioningClient({UlinkBleProtocolConfig? config})
    : config = config ?? UlinkBleProtocolConfig.environment;

  final UlinkBleProtocolConfig config;
  final UlinkSettingsParser _parser = UlinkSettingsParser();
  final StreamController<UlinkProtocolEvent> _events =
      StreamController<UlinkProtocolEvent>.broadcast();
  BluetoothDevice? _device;
  BluetoothCharacteristic? _command;
  BluetoothCharacteristic? _response;
  StreamSubscription<List<int>>? _responseSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  _UlinkResponseGate<Object?>? _pendingGate;
  UlinkSettings? _latestSettings;

  @override
  String get deviceName => _device?.platformName.trim().isNotEmpty == true
      ? _device!.platformName
      : _device?.remoteId.str ?? 'U-Link device';

  @override
  UlinkSettings? get latestSettings => _latestSettings;

  @override
  Stream<UlinkProtocolEvent> get events => _events.stream;

  Future<void> connect(BluetoothDevice device) async {
    if (!config.isConfigured) {
      throw const UlinkSettingsException(
        'U-Link BLE protocol has not been configured yet.',
      );
    }
    _device = device;
    try {
      if (Platform.isAndroid) {
        try {
          await device.createBond();
        } catch (_) {
          // Android may still display its normal pairing prompt during GATT.
        }
      }
      await device.connect(timeout: const Duration(seconds: 15));
      _connectionSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _failPending('U-Link disconnected before it responded.');
        }
      });
      final services = await device.discoverServices();
      final service = services.cast<BluetoothService?>().firstWhere(
        (item) => item != null && _sameUuid(item.uuid.str, config.serviceUuid),
        orElse: () => null,
      );
      if (service == null) {
        throw const UlinkSettingsException(
          'Configured U-Link BLE service was not found.',
        );
      }
      _command = service.characteristics
          .cast<BluetoothCharacteristic?>()
          .firstWhere(
            (item) =>
                item != null &&
                _sameUuid(item.uuid.str, config.commandCharacteristicUuid),
            orElse: () => null,
          );
      _response = service.characteristics
          .cast<BluetoothCharacteristic?>()
          .firstWhere(
            (item) =>
                item != null &&
                _sameUuid(item.uuid.str, config.responseCharacteristicUuid),
            orElse: () => null,
          );
      if (_command == null || _response == null) {
        throw const UlinkSettingsException(
          'Configured U-Link command or response characteristic was not found.',
        );
      }
      if (!_command!.properties.write ||
          (!_response!.properties.notify && !_response!.properties.indicate)) {
        throw const UlinkSettingsException(
          'Configured U-Link characteristics do not support settings.',
        );
      }
      _responseSubscription = _response!.onValueReceived.listen(_onResponse);
      // Notifications must be enabled before the automatic settings frame.
      await _response!.setNotifyValue(true);
    } catch (_) {
      await disconnect();
      rethrow;
    }
  }

  @override
  Future<UlinkSettings> refreshSettings() async {
    final gate = UlinkSettingsResponseGate();
    return _writeAndWait<UlinkSettings>(
      utf8.encode(UlinkSettingsProtocol.getSettingsCommand),
      gate,
    );
  }

  @override
  Future<void> saveSetting(UlinkSettingsKey key, String value) async {
    final validation = UlinkSettingsProtocol.validate(key, value);
    if (validation != null) throw UlinkSettingsException(validation);
    final gate = UlinkSetResponseGate(key);
    await _writeAndWait<void>(
      utf8.encode(UlinkSettingsProtocol.encodeSet(key, value)),
      gate,
    );
  }

  Future<T> _writeAndWait<T>(
    List<int> command,
    _UlinkResponseGate<T> gate,
  ) async {
    final characteristic = _command;
    if (characteristic == null || _response == null || _device == null) {
      throw const UlinkSettingsException('Connect to a U-Link device first.');
    }
    if (_pendingGate != null) {
      throw const UlinkSettingsException(
        'Another U-Link settings operation is pending.',
      );
    }
    _pendingGate = gate as _UlinkResponseGate<Object?>;
    try {
      // GATT write completion is not firmware confirmation. The gate resolves
      // only when the matching newline-delimited response is received.
      await characteristic.write(command, withoutResponse: false);
      return await gate.wait(config.ackTimeout);
    } finally {
      _pendingGate = null;
    }
  }

  void _onResponse(List<int> bytes) {
    for (final event in _parser.add(bytes)) {
      if (event is UlinkSettingsEvent) _latestSettings = event.settings;
      _events.add(event);
      _pendingGate?.accept(event);
    }
  }

  void _failPending(String message) => _pendingGate?.fail(message);

  @override
  Future<void> disconnect() async {
    _failPending('U-Link disconnected before it responded.');
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
