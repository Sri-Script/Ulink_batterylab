import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../models/ulink_api_models.dart';
import 'permission_service.dart';
import 'ulink_api_repository.dart';
import 'ulink_ble_protocol_config.dart';
import 'ulink_ble_provisioning_client.dart';

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
  const UlinkFlashException(this.message, {this.manualRecovery = false});
  final String message;
  final bool manualRecovery;
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

class UlinkRepositoryFlashGateway implements UlinkFlashApiGateway {
  UlinkRepositoryFlashGateway(this.repository);
  final UlinkApiRepository repository;

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
  Future<List<ApiUlink>> updateAssignment(UlinkFlashSelection selection) =>
      repository.updateUlinkProvisioning(
        companyId: selection.company.cid,
        ulinkId: selection.stockUlink.uid,
        flashed: true,
      );

  @override
  Future<List<ApiUlink>> retryPendingAssignment(
    UlinkFlashSelection selection,
  ) async {
    final retried = await repository.retryPendingProvisioning();
    if (!retried) {
      throw const UlinkFlashException(
        'The server assignment is still pending. Keep the U-Link powered and retry the pending operation from this session.',
        manualRecovery: true,
      );
    }
    return repository.getCompanyUlinks(
      userId: selection.session.userId,
      companyId: selection.company.cid,
    );
  }
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
    try {
      onProgress(UlinkFlashStage.checkingApiConnection);
      await _api.verifyPrerequisites(selection);

      onProgress(UlinkFlashStage.lookingForFactoryUlink);
      await _ble.findFactory();
      onProgress(UlinkFlashStage.connectingSecurely);
      await _ble.connectFactory();
      onProgress(UlinkFlashStage.preparingUlink);
      await _ble.prepare();

      onProgress(UlinkFlashStage.writingUcode);
      try {
        await _ble.writeUcode(selection.ucode);
        positiveAck = true;
      } catch (_) {
        // A write may have reached a write-once device even if the response
        // was lost. Scan to reconcile, but never resend the command.
      }

      onProgress(UlinkFlashStage.waitingForRestart);
      try {
        await _ble.waitForRestart();
      } catch (_) {
        // The reboot disconnect can be missed by Android; verification below
        // is the authoritative post-write result.
      }
      // Release the factory link before the one-connection device advertises
      // again. This is not a firmware reset and never sends a BLE command.
      await _ble.disconnect();
      onProgress(UlinkFlashStage.verifyingAssignedUlink);
      try {
        await _ble.verifyAssigned(selection.ucode);
        assignedVerified = true;
      } catch (_) {
        if (positiveAck) {
          throw const UlinkFlashException(
            'UCode may have been written; do not retry. Reconnect and verify manually.',
            manualRecovery: true,
          );
        }
        throw const UlinkFlashException(
          'UCode may have been written; do not retry. Reconnect and verify manually.',
          manualRecovery: true,
        );
      }

      if (!positiveAck) {
        throw const UlinkFlashException(
          'The U-Link advertised with the selected UCode, but its write acknowledgement was not received. Do not retry; it needs manual recovery.',
          manualRecovery: true,
        );
      }

      onProgress(UlinkFlashStage.updatingServerAssignment);
      List<ApiUlink> companyUlinks;
      try {
        companyUlinks = await _api.updateAssignment(selection);
      } on UlinkApiException catch (error) {
        if (error.statusCode != null) {
          throw UlinkFlashException(
            '${error.message} U-Link needs manual recovery.',
            manualRecovery: true,
          );
        }
        try {
          companyUlinks = await _api.retryPendingAssignment(selection);
        } catch (_) {
          throw const UlinkFlashException(
            'The U-Link is verified, but the server assignment outcome is unknown. The pending operation was retained and must be retried idempotently; do not reset the U-Link.',
            manualRecovery: true,
          );
        }
      }
      final confirmed = companyUlinks.any(
        (ulink) => ulink.uCode == selection.ucode && ulink.uif == true,
      );
      if (!confirmed) {
        throw const UlinkFlashException(
          'The server did not confirm the flashed UCode. U-Link needs manual recovery.',
          manualRecovery: true,
        );
      }
      final settingsClient = await _ble.reconnectForSettings();
      onProgress(UlinkFlashStage.completed);
      return UlinkFlashResult(
        settingsClient: settingsClient,
        companyUlinks: companyUlinks,
      );
    } finally {
      // The gateway retains only the new assigned settings client after a
      // confirmed end-to-end success. All other paths release the old link.
      if (!positiveAck || !assignedVerified) await _ble.disconnect();
    }
  }
}

class FlutterUlinkFlashBleGateway implements UlinkFlashBleGateway {
  FlutterUlinkFlashBleGateway({
    UlinkBleProtocolConfig? config,
    this.scanTimeout = const Duration(seconds: 20),
  }) : _config = config ?? UlinkBleProtocolConfig.environment;

  final UlinkBleProtocolConfig _config;
  final Duration scanTimeout;
  ScanResult? _factory;
  ScanResult? _assigned;
  UlinkBleProvisioningClient? _flashClient;

  @override
  Future<void> findFactory() async {
    _factory = await _scan(
      (result) =>
          UlinkAdvertisementMatcher.isFactoryName(
            result.advertisementData.advName,
          ) &&
          _hasConfiguredService(result),
    );
  }

  @override
  Future<void> connectFactory() async {
    final result = _factory;
    if (result == null) {
      throw const UlinkFlashException('Factory U-Link was not found.');
    }
    final client = UlinkBleProvisioningClient(config: _config);
    _flashClient = client;
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
    _assigned = await _scan(
      (result) =>
          UlinkAdvertisementMatcher.isAssignedName(
            result.advertisementData.advName,
            ucode,
          ) &&
          _hasConfiguredService(result),
    );
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
    await _flashClient?.disconnect();
    _flashClient = null;
  }

  bool _hasConfiguredService(ScanResult result) =>
      UlinkAdvertisementMatcher.hasService(
        result.advertisementData.serviceUuids.map((uuid) => uuid.str),
        _config.serviceUuid,
      );

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
