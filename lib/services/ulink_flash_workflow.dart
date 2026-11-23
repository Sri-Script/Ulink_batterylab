import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../models/ulink_api_models.dart';
import 'permission_service.dart';
import 'ulink_api_repository.dart';
import 'ulink_ble_protocol_config.dart';
import 'ulink_ble_provisioning_client.dart';
import 'ulink_flash_diagnostics.dart';

enum UlinkFlashStage {
  checkingApiConnection,
  lookingForFactoryUlink,
  connectingSecurely,
  preparingUlink,
  writingUcode,
  waitingForRestart,
  verifyingAssignedUlink,
  updatingServerAssignment,
  completed,
}

extension UlinkFlashStageText on UlinkFlashStage {
  String get label => switch (this) {
    UlinkFlashStage.checkingApiConnection => 'Checking API connection',
    UlinkFlashStage.lookingForFactoryUlink => 'Looking for factory U-Link',
    UlinkFlashStage.connectingSecurely => 'Connecting securely',
    UlinkFlashStage.preparingUlink => 'Preparing U-Link',
    UlinkFlashStage.writingUcode => 'Writing UCode',
    UlinkFlashStage.waitingForRestart => 'Waiting for restart',
    UlinkFlashStage.verifyingAssignedUlink => 'Verifying ULINK',
    UlinkFlashStage.updatingServerAssignment => 'Updating server assignment',
    UlinkFlashStage.completed => 'Completed',
  };

  String get failureMessage => switch (this) {
    UlinkFlashStage.checkingApiConnection =>
      'Flashing stopped while checking the API connection.',
    UlinkFlashStage.lookingForFactoryUlink =>
      'Flashing stopped while looking for the factory U-Link.',
    UlinkFlashStage.connectingSecurely =>
      'Flashing stopped while connecting to the U-Link.',
    UlinkFlashStage.preparingUlink =>
      'Flashing stopped while preparing the U-Link.',
    UlinkFlashStage.writingUcode =>
      'Flashing stopped while waiting for the UCode acknowledgement.',
    UlinkFlashStage.waitingForRestart =>
      'Flashing stopped while waiting for the U-Link to restart.',
    UlinkFlashStage.verifyingAssignedUlink =>
      'Flashing stopped while verifying the assigned U-Link.',
    UlinkFlashStage.updatingServerAssignment =>
      'Flashing stopped while updating the server assignment.',
    UlinkFlashStage.completed => 'Flashing stopped before completion.',
  };
}

class UlinkFlashSelection {
  const UlinkFlashSelection({
    required this.session,
    required this.company,
    required this.stockUlink,
  });

  final ApiSession session;
  final ApiCompany company;
  final ApiUlink stockUlink;

  String get ucode => stockUlink.uCode;
}

class UlinkFlashException implements Exception {
  const UlinkFlashException(
    this.message, {
    this.manualRecovery = false,
    this.stage,
  });

  factory UlinkFlashException.forStage(
    UlinkFlashStage stage, {
    bool manualRecovery = false,
  }) => UlinkFlashException(
    stage.failureMessage,
    manualRecovery: manualRecovery,
    stage: stage,
  );

  final String message;
  final bool manualRecovery;
  final UlinkFlashStage? stage;
  @override
  String toString() => message;
}

class UlinkFlashResult {
  const UlinkFlashResult({
    required this.settingsClient,
    required this.companyUlinks,
  });
  final UlinkSettingsClient settingsClient;
  final List<ApiUlink> companyUlinks;
}

/// Name and service matching deliberately stay exact. Bare UCode compatibility
/// is allowed only after the advertised service UUID is present.
class UlinkAdvertisementMatcher {
  const UlinkAdvertisementMatcher._();

  static const factoryName = 'ULINK';

  static bool hasService(Iterable<String> serviceUuids, String expectedUuid) =>
      serviceUuids.any(
        (uuid) =>
            uuid.trim().toLowerCase() == expectedUuid.trim().toLowerCase(),
      );

  static bool isFactoryName(String advertisedName) =>
      advertisedName == factoryName;

  static bool isAssignedName(String advertisedName, String ucode) =>
      advertisedName == 'ULINK-$ucode' || advertisedName == ucode;
}

abstract class UlinkFlashBleGateway {
  Future<void> findFactory();
  Future<void> connectFactory();
  Future<void> prepare();
  Future<void> writeUcode(String ucode);
  Future<void> waitForRestart();
  Future<void> verifyAssigned(String ucode);
  Future<UlinkSettingsClient> reconnectForSettings();
  Future<void> disconnect();
}

abstract class UlinkFlashApiGateway {
  Future<void> verifyPrerequisites(UlinkFlashSelection selection);
  Future<List<ApiUlink>> updateAssignment(UlinkFlashSelection selection);
  Future<List<ApiUlink>> retryPendingAssignment(UlinkFlashSelection selection);
}

class UlinkRepositoryFlashGateway
    implements UlinkFlashApiGateway, UlinkFlashApiDiagnosticSource {
  UlinkRepositoryFlashGateway(this.repository);
  final UlinkApiRepository repository;
  String _assignmentHttpStatus = 'not attempted';
  String _assignmentResult = 'not attempted';

  @override
  UlinkFlashApiDiagnostics get flashDiagnostics => UlinkFlashApiDiagnostics(
    assignmentHttpStatus: _assignmentHttpStatus,
    assignmentResult: _assignmentResult,
  );

  @override
  Future<void> verifyPrerequisites(UlinkFlashSelection selection) async {
    if (selection.stockUlink.uif == true) {
      throw const UlinkFlashException(
        'Select a U-Link In Stock that is not flashed.',
      );
    }
    if (!UlinkFlashProtocol.isValidUcode(selection.ucode)) {
      throw const UlinkFlashException(
        'The selected API UCode is invalid for Rev5.',
      );
    }
    final active = await repository.requireActiveSession();
    if (active.userId != selection.session.userId) {
      throw const UlinkFlashException(
        'The active API session has changed. Sign in again.',
      );
    }
    // An authenticated read proves the live session and API reachability
    // before any write-once firmware command is sent.
    await repository.verifyUlinkApiReachability(
      userId: active.userId,
      companyId: selection.company.cid,
    );
  }

  @override
  Future<List<ApiUlink>> updateAssignment(UlinkFlashSelection selection) async {
    _assignmentHttpStatus = 'pending';
    _assignmentResult = 'pending';
    try {
      final ulinks = await repository.updateUlinkProvisioning(
        companyId: selection.company.cid,
        ulinkId: selection.stockUlink.uid,
        flashed: true,
      );
      _assignmentHttpStatus = '200';
      _assignmentResult = 'success';
      return ulinks;
    } on UlinkApiException catch (error) {
      _assignmentHttpStatus = error.statusCode?.toString() ?? 'unavailable';
      _assignmentResult = _apiResultCategory(error);
      rethrow;
    } catch (_) {
      _assignmentHttpStatus = 'unavailable';
      _assignmentResult = 'transport failure';
      rethrow;
    }
  }

  @override
  Future<List<ApiUlink>> retryPendingAssignment(
    UlinkFlashSelection selection,
  ) async {
    _assignmentHttpStatus = 'pending retry';
    _assignmentResult = 'retry pending';
    try {
      final retried = await repository.retryPendingProvisioning();
      if (!retried) {
        _assignmentHttpStatus = 'unavailable';
        _assignmentResult = 'pending operation unavailable';
        throw const UlinkFlashException(
          'The server assignment is still pending. Keep the U-Link powered and retry the pending operation from this session.',
          manualRecovery: true,
        );
      }
      final ulinks = await repository.getCompanyUlinks(
        userId: selection.session.userId,
        companyId: selection.company.cid,
      );
      _assignmentHttpStatus = '200';
      _assignmentResult = 'retry success';
      return ulinks;
    } on UlinkApiException catch (error) {
      _assignmentHttpStatus = error.statusCode?.toString() ?? 'unavailable';
      _assignmentResult = _apiResultCategory(error);
      rethrow;
    } catch (_) {
      _assignmentHttpStatus = 'unavailable';
      _assignmentResult = 'transport failure';
      rethrow;
    }
  }
}

String _apiResultCategory(UlinkApiException error) {
  if (error.message.toLowerCase().contains('invalid response')) {
    return 'parse failure';
  }
  return error.statusCode == null ? 'transport failure' : 'HTTP failure';
}

/// Coordinates the irreversible Rev5 sequence. It never retries SET_UCODE and
/// never issues a reset command. A dropped link before a positive reply is
/// reconciled by scanning only; it is never treated as API authorization.
class UlinkFlashWorkflow {
  UlinkFlashWorkflow({
    required UlinkFlashBleGateway ble,
    required UlinkFlashApiGateway api,
  }) : _ble = ble,
       _api = api;

  final UlinkFlashBleGateway _ble;
  final UlinkFlashApiGateway _api;

  Future<UlinkFlashResult> run(
    UlinkFlashSelection selection, {
    required void Function(UlinkFlashStage stage) onProgress,
  }) async {
    var positiveAck = false;
    var assignedVerified = false;
    var currentStage = UlinkFlashStage.checkingApiConnection;

    void beginStage(UlinkFlashStage stage) {
      currentStage = stage;
      onProgress(stage);
      _debugStage(selection, stage);
    }

    void completeStage(UlinkFlashStage stage) => _debugStage(selection, stage);

    try {
      beginStage(UlinkFlashStage.checkingApiConnection);
      await _api.verifyPrerequisites(selection);
      completeStage(UlinkFlashStage.checkingApiConnection);

      beginStage(UlinkFlashStage.lookingForFactoryUlink);
      await _ble.findFactory();
      completeStage(UlinkFlashStage.lookingForFactoryUlink);
      beginStage(UlinkFlashStage.connectingSecurely);
      await _ble.connectFactory();
      completeStage(UlinkFlashStage.connectingSecurely);
      beginStage(UlinkFlashStage.preparingUlink);
      await _ble.prepare();
      completeStage(UlinkFlashStage.preparingUlink);

      beginStage(UlinkFlashStage.writingUcode);
      try {
        await _ble.writeUcode(selection.ucode);
        positiveAck = true;
        completeStage(UlinkFlashStage.writingUcode);
      } catch (error, stackTrace) {
        _debugStage(
          selection,
          UlinkFlashStage.writingUcode,
          error: error,
          stackTrace: stackTrace,
        );
        // A write may have reached a write-once device even if the response
        // was lost. Scan to reconcile, but never resend the command.
      }

      beginStage(UlinkFlashStage.waitingForRestart);
      try {
        await _ble.waitForRestart();
        completeStage(UlinkFlashStage.waitingForRestart);
      } catch (error, stackTrace) {
        _debugStage(
          selection,
          UlinkFlashStage.waitingForRestart,
          error: error,
          stackTrace: stackTrace,
        );
        // The reboot disconnect can be missed by Android; verification below
        // is the authoritative post-write result.
      }
      // Release the factory link before the one-connection device advertises
      // again. This is not a firmware reset and never sends a BLE command.
      await _ble.disconnect();
      beginStage(UlinkFlashStage.verifyingAssignedUlink);
      try {
        await _ble.verifyAssigned(selection.ucode);
        assignedVerified = true;
        completeStage(UlinkFlashStage.verifyingAssignedUlink);
      } catch (error, stackTrace) {
        _debugStage(
          selection,
          UlinkFlashStage.verifyingAssignedUlink,
          error: error,
          stackTrace: stackTrace,
        );
        throw UlinkFlashException.forStage(
          UlinkFlashStage.verifyingAssignedUlink,
          manualRecovery: true,
        );
      }

      if (!positiveAck) {
        throw UlinkFlashException.forStage(
          UlinkFlashStage.writingUcode,
          manualRecovery: true,
        );
      }

      beginStage(UlinkFlashStage.updatingServerAssignment);
      List<ApiUlink> companyUlinks;
      try {
        companyUlinks = await _api.updateAssignment(selection);
      } on UlinkApiException catch (error, stackTrace) {
        _debugStage(
          selection,
          UlinkFlashStage.updatingServerAssignment,
          error: error,
          stackTrace: stackTrace,
        );
        if (error.statusCode != null) {
          throw UlinkFlashException.forStage(
            UlinkFlashStage.updatingServerAssignment,
            manualRecovery: true,
          );
        }
        try {
          companyUlinks = await _api.retryPendingAssignment(selection);
        } catch (retryError, stackTrace) {
          _debugStage(
            selection,
            UlinkFlashStage.updatingServerAssignment,
            error: retryError,
            stackTrace: stackTrace,
          );
          throw UlinkFlashException.forStage(
            UlinkFlashStage.updatingServerAssignment,
            manualRecovery: true,
          );
        }
      }
      final confirmed = companyUlinks.any(
        (ulink) => ulink.uCode == selection.ucode && ulink.uif == true,
      );
      if (!confirmed) {
        throw UlinkFlashException.forStage(
          UlinkFlashStage.updatingServerAssignment,
          manualRecovery: true,
        );
      }
      completeStage(UlinkFlashStage.updatingServerAssignment);
      final settingsClient = await _ble.reconnectForSettings();
      beginStage(UlinkFlashStage.completed);
      completeStage(UlinkFlashStage.completed);
      return UlinkFlashResult(
        settingsClient: settingsClient,
        companyUlinks: companyUlinks,
      );
    } on UlinkFlashException catch (error, stackTrace) {
      if (error.stage != null) rethrow;
      _debugStage(
        selection,
        currentStage,
        error: error,
        stackTrace: stackTrace,
      );
      throw UlinkFlashException.forStage(
        currentStage,
        manualRecovery: error.manualRecovery,
      );
    } catch (error, stackTrace) {
      _debugStage(
        selection,
        currentStage,
        error: error,
        stackTrace: stackTrace,
      );
      throw UlinkFlashException.forStage(currentStage);
    } finally {
      // The gateway retains only the new assigned settings client after a
      // confirmed end-to-end success. All other paths release the old link.
      if (!positiveAck || !assignedVerified) await _ble.disconnect();
    }
  }

  void _debugStage(
    UlinkFlashSelection selection,
    UlinkFlashStage stage, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    final ble = _ble is UlinkFlashBleDiagnosticSource
        ? (_ble as UlinkFlashBleDiagnosticSource).flashDiagnostics
        : const UlinkFlashBleDiagnostics();
    final api = _api is UlinkFlashApiDiagnosticSource
        ? (_api as UlinkFlashApiDiagnosticSource).flashDiagnostics
        : const UlinkFlashApiDiagnostics();
    final detail = error == null
        ? ''
        : '; cause=${_redactDiagnosticCause(error)}';
    final stackDetail = kDebugMode && stackTrace != null
        ? '; stack=${_topStackLocation(stackTrace)}'
        : '';
    debugPrint(
      '[U-Link Flash] cid=${selection.company.cid}; '
      'stockUid=${selection.stockUlink.uid}; ucode=${selection.ucode}; '
      'stage=${stage.name}; advertisementName=${ble.advertisementName}; '
      'serviceUuidMatch=${ble.serviceUuidMatch}; connection=${ble.connection}; '
      'discovery=${ble.discovery}; notifications=${ble.notifications}; '
      'DEV_OPEN=${ble.developerOpen}; settingsAck=${ble.settingsAck}; '
      'SET_UCODE write=${ble.setUcodeWrite}; '
      'response=${ble.responseCategory}; '
      'assignedAdvertisementVerification=${ble.assignedAdvertisementVerification}; '
      'apiAssignmentHttpStatus=${api.assignmentHttpStatus}; '
      'apiAssignmentResult=${api.assignmentResult}$detail$stackDetail',
    );
  }
}

String _redactDiagnosticCause(Object error) {
  // Never serialize an exception message: platform and HTTP exceptions may
  // embed a MAC address, credentials, headers, or complete response body.
  // The stage snapshot above contains every diagnostic detail that is safe to
  // expose, including whitelisted ACK error codes and HTTP status/category.
  return switch (error) {
    UlinkApiException(statusCode: final statusCode) =>
      'API ${_safeApiFailureCategory(error.message)} status=${statusCode ?? 'unavailable'}',
    UlinkSettingsException() => 'BLE protocol failure',
    UlinkFlashException() => 'flash workflow failure',
    FormatException() => 'response format failure',
    TypeError() => 'unexpected response type',
    _ => 'failure type=${error.runtimeType}',
  };
}

String _safeApiFailureCategory(String message) {
  final normalized = message.toLowerCase();
  if (normalized.contains('invalid') || normalized.contains('unexpected')) {
    return 'invalid response';
  }
  if (normalized.contains('network') ||
      normalized.contains('unavailable') ||
      normalized.contains('lost')) {
    return 'network failure';
  }
  if (normalized.contains('session')) return 'session failure';
  return 'request failure';
}

String _topStackLocation(StackTrace stackTrace) {
  final lines = stackTrace.toString().split('\n');
  final location = lines.firstWhere(
    (line) => line.trim().isNotEmpty,
    orElse: () => 'unavailable',
  );
  return location.length <= 200 ? location : '${location.substring(0, 200)}…';
}

class FlutterUlinkFlashBleGateway
    implements UlinkFlashBleGateway, UlinkFlashBleDiagnosticSource {
  FlutterUlinkFlashBleGateway({
    UlinkBleProtocolConfig? config,
    this.scanTimeout = const Duration(seconds: 20),
  }) : _config = config ?? UlinkBleProtocolConfig.environment;

  final UlinkBleProtocolConfig _config;
  final Duration scanTimeout;
  ScanResult? _factory;
  ScanResult? _assigned;
  UlinkBleProvisioningClient? _flashClient;
  UlinkFlashBleDiagnostics? _lastClientDiagnostics;
  String _advertisementName = 'not observed';
  String _serviceUuidMatch = 'not observed';
  String _assignedAdvertisementVerification = 'not attempted';

  @override
  UlinkFlashBleDiagnostics get flashDiagnostics {
    final client = _flashClient?.flashDiagnostics ?? _lastClientDiagnostics;
    return UlinkFlashBleDiagnostics(
      advertisementName: _advertisementName,
      serviceUuidMatch: _serviceUuidMatch,
      connection: client?.connection ?? 'not attempted',
      discovery: client?.discovery ?? 'not attempted',
      notifications: client?.notifications ?? 'not attempted',
      developerOpen: client?.developerOpen ?? 'not attempted',
      settingsAck: client?.settingsAck ?? 'not attempted',
      setUcodeWrite: client?.setUcodeWrite ?? 'not sent',
      responseCategory: client?.responseCategory ?? 'not observed',
      assignedAdvertisementVerification: _assignedAdvertisementVerification,
    );
  }

  @override
  Future<void> findFactory() async {
    _factory = await _scan(
      (result) =>
          UlinkAdvertisementMatcher.isFactoryName(
            result.advertisementData.advName,
          ) &&
          _hasConfiguredService(result),
    );
    _recordAdvertisement(_factory!);
  }

  @override
  Future<void> connectFactory() async {
    final result = _factory;
    if (result == null) {
      throw const UlinkFlashException('Factory U-Link was not found.');
    }
    final client = UlinkBleProvisioningClient(config: _config);
    _flashClient = client;
    _lastClientDiagnostics = null;
    await client.connect(result.device);
  }

  @override
  Future<void> prepare() async {
    final client = _flashClient;
    if (client == null) {
      throw const UlinkFlashException('Factory U-Link is not connected.');
    }
    await client.waitForInitialSettings();
    await client.openDeveloperMode();
  }

  @override
  Future<void> writeUcode(String ucode) async =>
      _flashClient!.writeUcode(ucode);

  @override
  Future<void> waitForRestart() =>
      _flashClient!.waitForDisconnect(const Duration(seconds: 12));

  @override
  Future<void> verifyAssigned(String ucode) async {
    _assignedAdvertisementVerification = 'searching';
    try {
      _assigned = await _scan(
        (result) =>
            UlinkAdvertisementMatcher.isAssignedName(
              result.advertisementData.advName,
              ucode,
            ) &&
            _hasConfiguredService(result),
      );
      _recordAdvertisement(_assigned!);
      _assignedAdvertisementVerification = 'verified';
    } catch (_) {
      _assignedAdvertisementVerification = 'not verified';
      rethrow;
    }
  }

  @override
  Future<UlinkSettingsClient> reconnectForSettings() async {
    final result = _assigned;
    if (result == null) {
      throw const UlinkFlashException('Assigned U-Link was not found.');
    }
    final client = UlinkBleProvisioningClient(config: _config);
    await client.connect(result.device);
    return client;
  }

  @override
  Future<void> disconnect() async {
    final client = _flashClient;
    if (client != null) {
      await client.disconnect();
      _lastClientDiagnostics = client.flashDiagnostics;
    }
    _flashClient = null;
  }

  bool _hasConfiguredService(ScanResult result) =>
      UlinkAdvertisementMatcher.hasService(
        result.advertisementData.serviceUuids.map((uuid) => uuid.str),
        _config.serviceUuid,
      );

  void _recordAdvertisement(ScanResult result) {
    _advertisementName = result.advertisementData.advName;
    _serviceUuidMatch = _hasConfiguredService(result)
        ? 'matched'
        : 'not matched';
  }

  Future<ScanResult> _scan(bool Function(ScanResult result) matches) async {
    if (!await PermissionService().requestBle()) {
      throw const UlinkFlashException(
        'Bluetooth permission is required to find U-Link devices.',
      );
    }
    if (!await FlutterBluePlus.isSupported) {
      throw const UlinkFlashException(
        'Bluetooth LE is not supported on this device.',
      );
    }
    await _waitForBluetoothOn();
    final found = Completer<ScanResult>();
    late final StreamSubscription<List<ScanResult>> subscription;
    subscription = FlutterBluePlus.scanResults.listen((results) {
      if (found.isCompleted) return;
      for (final result in results) {
        if (matches(result)) {
          found.complete(result);
          break;
        }
      }
    });
    try {
      // Low-latency is Android's active scan mode. No MTU request is made.
      unawaited(
        FlutterBluePlus.startScan(
          timeout: scanTimeout,
          androidScanMode: AndroidScanMode.lowLatency,
        ),
      );
      return await found.future.timeout(
        scanTimeout,
        onTimeout: () => throw const UlinkFlashException(
          'No matching U-Link advertisement with the required service was found.',
        ),
      );
    } finally {
      await subscription.cancel();
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
    }
  }

  Future<void> _waitForBluetoothOn() async {
    final adapterOn = FlutterBluePlus.adapterState
        .where((state) => state == BluetoothAdapterState.on)
        .first;
    if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
      await FlutterBluePlus.turnOn();
    }
    await adapterOn.timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw const UlinkFlashException(
        'Turn on Bluetooth to scan for U-Link devices.',
      ),
    );
  }
}
