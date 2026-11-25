import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ulink_ble_protocol_config.dart';
import 'ulink_flash_diagnostics.dart';

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

/// Rev5 uses UTF-8 JSON frames delimited by LF. The password is deliberately
/// never included in diagnostics or exceptions.
class UlinkSettingsProtocol {
  const UlinkSettingsProtocol._();

  static const getSettingsCommand = 'GET_SETTINGS\n';
  static const settingsAckCommand = 'SETTINGS_ACK\n';
  static const developerOpenCommand = 'DEV_OPEN\n';

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

/// Rev5 write-once UCode framing and validation.
class UlinkFlashProtocol {
  const UlinkFlashProtocol._();

  static final _ucodePattern = RegExp(r'^[A-Za-z0-9_-]{1,23}$');

  static bool isValidUcode(String value) => _ucodePattern.hasMatch(value);

  static String encodeSetUcode(String ucode) {
    if (!isValidUcode(ucode)) {
      throw const UlinkSettingsException(
        'UCode must contain 1–23 ASCII letters, digits, underscores, or hyphens.',
      );
    }
    return '${jsonEncode(<String, String>{'cmd': 'SET_UCODE', 'ucode': ucode})}\n';
  }

  /// Rev5 identity removal command. The same UCode validation used for
  /// provisioning prevents a command from being directed at an ambiguous
  /// assigned advertisement.
  static String encodeUnflashUcode(String ucode) {
    if (!isValidUcode(ucode)) {
      throw const UlinkSettingsException(
        'UCode must contain 1â€“23 ASCII letters, digits, underscores, or hyphens.',
      );
    }
    return '${jsonEncode(<String, String>{'cmd': 'UNFLASH_UCODE', 'ucode': ucode})}\n';
  }
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

class UlinkDeveloperModeEvent extends UlinkProtocolEvent {
  const UlinkDeveloperModeEvent();
}

class UlinkUcodeWrittenEvent extends UlinkProtocolEvent {
  const UlinkUcodeWrittenEvent(this.ucode);
  final String ucode;
}

class UlinkUcodeClearedEvent extends UlinkProtocolEvent {
  const UlinkUcodeClearedEvent(this.ucode);
  final String ucode;
}

class UlinkErrorEvent extends UlinkProtocolEvent {
  const UlinkErrorEvent(this.message);
  final String message;
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
      if (value['ok'] == false) {
        final error = value['error'];
        return UlinkErrorEvent(
          error is String && error.trim().isNotEmpty
              ? error.trim()
              : 'U-Link rejected the command.',
        );
      }
      if (value['event'] == 'settings') {
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
      if (value['developer_mode'] == true) {
        return const UlinkDeveloperModeEvent();
      }
      if (value['event'] == 'ucode_written' && value['ucode'] is String) {
        return UlinkUcodeWrittenEvent(value['ucode'] as String);
      }
      if (value['event'] == 'ucode_cleared' && value['ucode'] is String) {
        return UlinkUcodeClearedEvent(value['ucode'] as String);
      }
      if (value['key'] is String && value['saved'] is bool) {
        return UlinkSetReplyEvent(
          ok: true,
          key: value['key'] as String,
          saved: value['saved'] as bool,
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
    } else if (event is UlinkErrorEvent) {
      fail(event.message);
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
    } else if (event is UlinkErrorEvent) {
      fail(event.message);
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

class UlinkDeveloperModeResponseGate implements _UlinkResponseGate<void> {
  final Completer<void> _completion = Completer<void>();
  @override
  void accept(UlinkProtocolEvent event) {
    if (_completion.isCompleted) return;
    if (event is UlinkDeveloperModeEvent) {
      _completion.complete();
    } else if (event is UlinkErrorEvent) {
      fail(event.message);
    } else if (event is UlinkMalformedEvent) {
      fail('U-Link sent an invalid developer-mode response.');
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
    onTimeout: () => throw const UlinkSettingsException(
      'Timed out opening U-Link developer mode.',
    ),
  );
}

class UlinkUcodeResponseGate implements _UlinkResponseGate<void> {
  UlinkUcodeResponseGate(this.ucode);
  final String ucode;
  final Completer<void> _completion = Completer<void>();
  @override
  void accept(UlinkProtocolEvent event) {
    if (_completion.isCompleted) return;
    if (event is UlinkUcodeWrittenEvent) {
      if (event.ucode == ucode) {
        _completion.complete();
      } else {
        fail('U-Link confirmed a different UCode.');
      }
    } else if (event is UlinkErrorEvent) {
      fail(event.message);
    } else if (event is UlinkMalformedEvent) {
      fail('U-Link sent an invalid UCode response.');
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
    onTimeout: () => throw const UlinkSettingsException(
      'Timed out waiting for U-Link to confirm the UCode.',
    ),
  );
}

/// Accepts only the documented Rev5 positive unflash acknowledgement. ATT
/// write completion is deliberately not treated as firmware success.
class UlinkUnflashResponseGate implements _UlinkResponseGate<void> {
  UlinkUnflashResponseGate(this.ucode);
  final String ucode;
  final Completer<void> _completion = Completer<void>();

  @override
  void accept(UlinkProtocolEvent event) {
    if (_completion.isCompleted) return;
    if (event is UlinkUcodeClearedEvent) {
      if (event.ucode == ucode) {
        _completion.complete();
      } else {
        fail('U-Link confirmed that a different UCode was cleared.');
      }
    } else if (event is UlinkErrorEvent) {
      fail(event.message);
    } else if (event is UlinkMalformedEvent) {
      fail('U-Link sent an invalid UCode-clear response.');
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
    onTimeout: () => throw const UlinkSettingsException(
      'Timed out waiting for U-Link to confirm identity removal.',
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

/// GATT client for the Rev5 U-Link NUS service. It preserves the established
/// Android/Vivo bond attempt and lets the OS complete encrypted Just Works
/// pairing. Service discovery always completes before notification setup.
class UlinkBleProvisioningClient
    implements UlinkSettingsClient, UlinkFlashBleDiagnosticSource {
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
  Completer<UlinkSettings>? _initialSettings;
  Completer<void>? _disconnected;
  Future<void> _writeQueue = Future<void>.value();
  String _connection = 'not attempted';
  String _discovery = 'not attempted';
  String _notifications = 'not attempted';
  String _developerOpen = 'not attempted';
  String _settingsAck = 'not attempted';
  String _setUcodeWrite = 'not sent';
  String _responseCategory = 'not observed';

  @override
  UlinkFlashBleDiagnostics get flashDiagnostics => UlinkFlashBleDiagnostics(
    connection: _connection,
    discovery: _discovery,
    notifications: _notifications,
    developerOpen: _developerOpen,
    settingsAck: _settingsAck,
    setUcodeWrite: _setUcodeWrite,
    responseCategory: _responseCategory,
  );

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
      throw UlinkSettingsException(
        config.validationError ??
            'U-Link BLE protocol has not been configured.',
      );
    }
    _device = device;
    _initialSettings = Completer<UlinkSettings>();
    _disconnected = Completer<void>();
    _connection = 'attempting';
    _discovery = 'not attempted';
    _notifications = 'not attempted';
    try {
      if (Platform.isAndroid) {
        try {
          await device.createBond();
        } catch (_) {
          // Android may still display its normal pairing prompt during GATT.
        }
      }
      await device.connect(timeout: const Duration(seconds: 15));
      _connection = 'connected';
      _connectionSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _connection = 'disconnected';
          if (!(_disconnected?.isCompleted ?? true)) _disconnected!.complete();
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
      _discovery = 'service found';
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
      // Subscribe before the automatic settings frame and before commands.
      await _response!.setNotifyValue(true);
      _notifications = 'enabled';
    } catch (_) {
      if (_connection != 'disconnected') _connection = 'failed';
      if (_discovery == 'not attempted') _discovery = 'failed';
      if (_notifications == 'not attempted') _notifications = 'failed';
      await disconnect();
      rethrow;
    }
  }

  /// Completes after the automatic settings snapshot has been acknowledged.
  Future<UlinkSettings> waitForInitialSettings() async {
    final completion = _initialSettings;
    if (completion == null) {
      throw const UlinkSettingsException('Connect to a U-Link device first.');
    }
    try {
      final settings = await completion.future.timeout(
        config.ackTimeout,
        onTimeout: () => throw const UlinkSettingsException(
          'Timed out waiting for the automatic U-Link settings snapshot.',
        ),
      );
      return settings;
    } catch (_) {
      _recordResponseFailure();
      rethrow;
    }
  }

  Future<void> openDeveloperMode() async {
    _developerOpen = 'sent';
    try {
      await _writeAndWait<void>(
        utf8.encode(UlinkSettingsProtocol.developerOpenCommand),
        UlinkDeveloperModeResponseGate(),
      );
      _developerOpen = 'acknowledged';
    } catch (_) {
      _developerOpen = 'failed';
      _recordResponseFailure();
      rethrow;
    }
  }

  /// This deliberately has no retry path: Rev5 UCodes are write-once.
  Future<void> writeUcode(String ucode) async {
    _setUcodeWrite = 'sent';
    _responseCategory = 'not observed';
    try {
      await _writeAndWait<void>(
        utf8.encode(UlinkFlashProtocol.encodeSetUcode(ucode)),
        UlinkUcodeResponseGate(ucode),
      );
      _responseCategory = 'positive ACK';
    } catch (_) {
      _recordResponseFailure();
      rethrow;
    }
  }

  /// This has no retry path: a clear acknowledgement is irreversible and the
  /// firmware reboots immediately afterwards.
  Future<void> unflashUcode(String ucode) async {
    _setUcodeWrite = 'unflash sent';
    _responseCategory = 'not observed';
    try {
      await _writeAndWait<void>(
        utf8.encode(UlinkFlashProtocol.encodeUnflashUcode(ucode)),
        UlinkUnflashResponseGate(ucode),
      );
      _responseCategory = 'ucode_cleared ACK';
    } catch (_) {
      _recordResponseFailure();
      rethrow;
    }
  }

  Future<void> waitForDisconnect(Duration timeout) {
    final completion = _disconnected;
    if (completion == null) {
      throw const UlinkSettingsException('Connect to a U-Link device first.');
    }
    return completion.future.timeout(timeout);
  }

  @override
  Future<UlinkSettings> refreshSettings() => _writeAndWait<UlinkSettings>(
    utf8.encode(UlinkSettingsProtocol.getSettingsCommand),
    UlinkSettingsResponseGate(),
  );

  @override
  Future<void> saveSetting(UlinkSettingsKey key, String value) async {
    final validation = UlinkSettingsProtocol.validate(key, value);
    if (validation != null) throw UlinkSettingsException(validation);
    await _writeAndWait<void>(
      utf8.encode(UlinkSettingsProtocol.encodeSet(key, value)),
      UlinkSetResponseGate(key),
    );
  }

  Future<T> _writeAndWait<T>(
    List<int> command,
    _UlinkResponseGate<T> gate,
  ) async {
    if (_command == null || _response == null || _device == null) {
      throw const UlinkSettingsException('Connect to a U-Link device first.');
    }
    if (_pendingGate != null) {
      throw const UlinkSettingsException(
        'Another U-Link operation is pending.',
      );
    }
    _pendingGate = gate as _UlinkResponseGate<Object?>;
    try {
      // A completed GATT write is transport progress, never firmware success.
      await _enqueueWrite(command);
      return await gate.wait(config.ackTimeout);
    } finally {
      _pendingGate = null;
    }
  }

  Future<void> _enqueueWrite(List<int> command) {
    final characteristic = _command;
    if (characteristic == null) {
      return Future<void>.error(
        const UlinkSettingsException('Connect to a U-Link device first.'),
      );
    }
    final operation = _writeQueue.then((_) async {
      for (final chunk in UlinkBleWriteChunks.split(command)) {
        await characteristic.write(chunk, withoutResponse: false);
      }
    });
    // A failed acknowledgement write must not poison later serialized writes.
    _writeQueue = operation.catchError((_) {});
    return operation;
  }

  void _onResponse(List<int> bytes) {
    for (final event in _parser.add(bytes)) {
      if (event is UlinkSettingsEvent) {
        _latestSettings = event.settings;
        // Rev5 requires an acknowledgement after every complete snapshot.
        unawaited(_sendSettingsAck());
        if (!(_initialSettings?.isCompleted ?? true)) {
          _initialSettings!.complete(event.settings);
        }
      }
      if (event is UlinkErrorEvent) {
        _responseCategory =
            'negative ACK error code=${_safeErrorCode(event.message)}';
      } else if (event is UlinkMalformedEvent) {
        _responseCategory = 'parse failure';
      }
      _events.add(event);
      _pendingGate?.accept(event);
    }
  }

  void _failPending(String message) => _pendingGate?.fail(message);

  Future<void> _sendSettingsAck() async {
    _settingsAck = 'sent';
    try {
      await _enqueueWrite(
        utf8.encode(UlinkSettingsProtocol.settingsAckCommand),
      );
      _settingsAck = 'acknowledged';
    } catch (_) {
      _settingsAck = 'failed';
    }
  }

  void _recordResponseFailure() {
    if (_responseCategory != 'not observed') return;
    if (_connection == 'disconnected') {
      _responseCategory = 'disconnect';
    } else {
      _responseCategory = 'timeout';
    }
  }

  String _safeErrorCode(String value) {
    final trimmed = value.trim();
    if (RegExp(r'^[A-Za-z0-9_-]{1,32}$').hasMatch(trimmed)) {
      return trimmed;
    }
    return 'redacted';
  }

  @override
  Future<void> disconnect() async {
    _connection = 'disconnected';
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
    if (!(_disconnected?.isCompleted ?? true)) _disconnected!.complete();
  }

  static bool _sameUuid(String left, String right) =>
      left.toLowerCase() == right.trim().toLowerCase();
}

/// Centralized, testable 20-byte write-with-response framing.
class UlinkBleWriteChunks {
  const UlinkBleWriteChunks._();
  static List<List<int>> split(List<int> bytes, {int maxBytes = 20}) {
    if (maxBytes <= 0) throw ArgumentError.value(maxBytes, 'maxBytes');
    return <List<int>>[
      for (var start = 0; start < bytes.length; start += maxBytes)
        bytes.sublist(start, (start + maxBytes).clamp(0, bytes.length)),
    ];
  }
}
