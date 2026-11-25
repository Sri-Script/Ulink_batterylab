import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../models/ulink_api_models.dart';
import 'permission_service.dart';
import 'ulink_api_repository.dart';
import 'ulink_ble_protocol_config.dart';
import 'ulink_ble_provisioning_client.dart';
import 'ulink_flash_workflow.dart' show UlinkAdvertisementMatcher;

enum UlinkUnflashStage {
  freshSignIn,
  apiPreflight,
  locatingAssignedUlink,
  secureConnection,
  clearingUcode,
  waitingForRestart,
  verifyingFactoryUlink,
  updatingServer,
  completed,
}

extension UlinkUnflashStageText on UlinkUnflashStage {
  String get label => switch (this) {
    UlinkUnflashStage.freshSignIn => 'Fresh sign-in',
    UlinkUnflashStage.apiPreflight => 'API preflight',
    UlinkUnflashStage.locatingAssignedUlink => 'Locating assigned U-Link',
    UlinkUnflashStage.secureConnection => 'Secure connection',
    UlinkUnflashStage.clearingUcode => 'Clearing UCode',
    UlinkUnflashStage.waitingForRestart => 'Waiting for restart',
    UlinkUnflashStage.verifyingFactoryUlink => 'Verifying ULINK',
    UlinkUnflashStage.updatingServer => 'Updating server',
    UlinkUnflashStage.completed => 'Completed',
  };
}

class UlinkUnflashSelection {
  const UlinkUnflashSelection({
    required this.session,
    required this.company,
    required this.ulink,
  });

  final ApiSession session;
  final ApiCompany company;
  final ApiUlink ulink;
  String get ucode => ulink.uCode;
}

class UlinkUnflashException implements Exception {
  const UlinkUnflashException(
    this.message, {
    this.stage,
    this.identityMayBeCleared = false,
    this.needsReconciliation = false,
    this.pendingServerRetry = false,
  });

  final String message;
  final UlinkUnflashStage? stage;
  final bool identityMayBeCleared;
  final bool needsReconciliation;
  final bool pendingServerRetry;
  @override
  String toString() => message;
}

abstract class UlinkUnflashBleGateway {
  Future<void> ensureBluetoothReady();
  Future<void> findAssigned(String ucode);
  Future<void> connectAssigned();
  Future<void> prepare();
  Future<void> clearUcode(String ucode);
  Future<void> waitForRestart();
  Future<void> verifyFactory();
  Future<void> disconnect();
}

abstract class UlinkUnflashApiGateway {
  Future<ApiLoginResult> authenticateFreshly({
    required String username,
    required String password,
  });
  Future<void> verifyPrerequisites(UlinkUnflashSelection selection);
  Future<List<ApiUlink>> updateCleared(UlinkUnflashSelection selection);
  Future<List<ApiUlink>> retryPendingUpdate(UlinkUnflashSelection selection);
}

/// Keeps password-login provenance separate from the regular restored API
/// session. The password itself is neither retained nor stored.
class UlinkRepositoryUnflashApiGateway implements UlinkUnflashApiGateway {
  UlinkRepositoryUnflashApiGateway(this.repository, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final UlinkApiRepository repository;
  final DateTime Function() _now;
  String? _freshAuthenticationId;
  DateTime? _freshAtUtc;

  @override
  Future<ApiLoginResult> authenticateFreshly({
    required String username,
    required String password,
  }) async {
    final result = await repository.login(
      username: username,
      password: password,
    );
    _freshAuthenticationId = result.session.authenticationId;
    _freshAtUtc = _now().toUtc();
    return result;
  }

  @override
  Future<void> verifyPrerequisites(UlinkUnflashSelection selection) async {
    if (selection.ulink.uif != true) {
      throw const UlinkUnflashException('Select a currently flashed U-Link.');
    }
    if (!UlinkFlashProtocol.isValidUcode(selection.ucode)) {
      throw const UlinkUnflashException(
        'The selected U-Link has an invalid UCode.',
      );
    }
    final freshAt = _freshAtUtc;
    if (freshAt == null ||
        selection.session.authenticationId == null ||
        selection.session.authenticationId != _freshAuthenticationId ||
        _now().toUtc().difference(freshAt) > const Duration(minutes: 5)) {
      throw const UlinkUnflashException(
        'A successful password sign-in from the last five minutes is required.',
      );
    }
    final active = await repository.requireActiveSession();
    if (active.authenticationId != selection.session.authenticationId ||
        active.userId != selection.session.userId) {
      throw const UlinkUnflashException(
        'The authenticated API session has changed. Sign in again.',
      );
    }
    final ulinks = await repository.getCompanyUlinks(
      userId: active.userId,
      companyId: selection.company.cid,
    );
    final selected = ulinks.where(
      (item) =>
          item.uid == selection.ulink.uid && item.uCode == selection.ucode,
    );
    if (selected.length != 1 || selected.single.uif != true) {
      throw const UlinkUnflashException(
        'The selected flashed U-Link no longer belongs to this company. Refresh and try again.',
      );
    }
  }

  @override
  Future<List<ApiUlink>> updateCleared(UlinkUnflashSelection selection) async {
    try {
      return await repository.updateUlinkProvisioning(
        companyId: selection.company.cid,
        ulinkId: selection.ulink.uid,
        flashed: false,
        appType: null,
        requireFreshAuthentication: true,
      );
    } on UlinkApiException catch (error) {
      if (error.statusCode != null) {
        await repository.discardPendingProvisioning();
        throw const UlinkUnflashException(
          'The server rejected the reset. The U-Link identity was cleared; reconcile this U-Link manually and do not reflash it.',
          needsReconciliation: true,
        );
      }
      throw const UlinkUnflashException(
        'ULINK was verified, but the server result is unknown. Needs reconciliation: retry only the pending server update in this same session; do not reflash or unflash again.',
        needsReconciliation: true,
        pendingServerRetry: true,
      );
    }
  }

  @override
  Future<List<ApiUlink>> retryPendingUpdate(
    UlinkUnflashSelection selection,
  ) async {
    final active = await repository.requireActiveSession();
    if (active.authenticationId != selection.session.authenticationId ||
        active.authenticationId != _freshAuthenticationId) {
      throw const UlinkUnflashException(
        'Needs reconciliation: the pending server update cannot be replayed after another fresh login.',
        needsReconciliation: true,
      );
    }
    final retried = await repository.retryPendingProvisioning();
    if (!retried) {
      throw const UlinkUnflashException(
        'Needs reconciliation: no matching pending server update exists for this authenticated session.',
        needsReconciliation: true,
      );
    }
    return repository.getCompanyUlinks(
      userId: active.userId,
      companyId: selection.company.cid,
    );
  }
}

/// Coordinates a single irreversible command. It never retries UNFLASH_UCODE,
/// never replays it after a reboot, and does not issue a factory-reset command.
class UlinkUnflashWorkflow {
  UlinkUnflashWorkflow({
    required UlinkUnflashBleGateway ble,
    required UlinkUnflashApiGateway api,
  }) : _ble = ble,
       _api = api;

  final UlinkUnflashBleGateway _ble;
  final UlinkUnflashApiGateway _api;

  Future<List<ApiUlink>> run(
    UlinkUnflashSelection selection, {
    required void Function(UlinkUnflashStage stage) onProgress,
  }) async {
    var positiveAck = false;
    var factoryVerified = false;
    var stage = UlinkUnflashStage.apiPreflight;
    void start(UlinkUnflashStage value) {
      stage = value;
      onProgress(value);
    }

    try {
      start(UlinkUnflashStage.apiPreflight);
      await _api.verifyPrerequisites(selection);
      await _ble.ensureBluetoothReady();
      start(UlinkUnflashStage.locatingAssignedUlink);
      await _ble.findAssigned(selection.ucode);
      start(UlinkUnflashStage.secureConnection);
      await _ble.connectAssigned();
      await _ble.prepare();
      start(UlinkUnflashStage.clearingUcode);
      await _ble.clearUcode(selection.ucode);
      positiveAck = true;
      start(UlinkUnflashStage.waitingForRestart);
      try {
        await _ble.waitForRestart();
      } catch (_) {
        // The disconnect notification itself can be missed; the exact ULINK
        // advertisement below is the authoritative reboot verification.
      }
      await _ble.disconnect();
      start(UlinkUnflashStage.verifyingFactoryUlink);
      try {
        await _ble.verifyFactory();
        factoryVerified = true;
      } catch (_) {
        throw const UlinkUnflashException(
          'Identity may have been cleared; do not retry. Verify manually.',
          identityMayBeCleared: true,
        );
      }
      start(UlinkUnflashStage.updatingServer);
      final ulinks = await _api.updateCleared(selection);
      final stillFlashed = ulinks.any(
        (item) => item.uid == selection.ulink.uid && item.uif == true,
      );
      if (stillFlashed) {
        throw const UlinkUnflashException(
          'The server still shows this U-Link as flashed. Needs reconciliation; do not reflash it.',
          needsReconciliation: true,
        );
      }
      start(UlinkUnflashStage.completed);
      return ulinks;
    } on UlinkUnflashException {
      rethrow;
    } on UlinkApiException catch (_) {
      throw UlinkUnflashException(
        'Unflash stopped during ${stage.label.toLowerCase()}.',
        stage: stage,
      );
    } catch (_) {
      if (positiveAck && !factoryVerified) {
        throw const UlinkUnflashException(
          'Identity may have been cleared; do not retry. Verify manually.',
          identityMayBeCleared: true,
        );
      }
      throw UlinkUnflashException(
        'Unflash stopped during ${stage.label.toLowerCase()}.',
        stage: stage,
      );
    } finally {
      await _ble.disconnect();
    }
  }
}

class FlutterUlinkUnflashBleGateway implements UlinkUnflashBleGateway {
  FlutterUlinkUnflashBleGateway({
    UlinkBleProtocolConfig? config,
    this.scanTimeout = const Duration(seconds: 20),
  }) : _config = config ?? UlinkBleProtocolConfig.environment;

  final UlinkBleProtocolConfig _config;
  final Duration scanTimeout;
  ScanResult? _assigned;
  UlinkBleProvisioningClient? _client;
  String? _knownRemoteId;

  @override
  Future<void> ensureBluetoothReady() async {
    if (!await PermissionService().requestBle()) {
      throw const UlinkUnflashException(
        'Bluetooth permission is required to unflash a U-Link.',
      );
    }
    if (!await FlutterBluePlus.isSupported) {
      throw const UlinkUnflashException(
        'Bluetooth LE is not supported on this device.',
      );
    }
    if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
      await FlutterBluePlus.turnOn();
    }
    await FlutterBluePlus.adapterState
        .where((state) => state == BluetoothAdapterState.on)
        .first
        .timeout(const Duration(seconds: 15));
  }

  @override
  Future<void> findAssigned(String ucode) async {
    _assigned = await _scanOne(
      (result) =>
          UlinkAdvertisementMatcher.isAssignedName(
            result.advertisementData.advName,
            ucode,
          ) &&
          _hasConfiguredService(result),
    );
    _knownRemoteId = _assigned!.device.remoteId.str;
  }

  @override
  Future<void> connectAssigned() async {
    final assigned = _assigned;
    if (assigned == null) {
      throw const UlinkUnflashException(
        'The selected assigned U-Link was not found.',
      );
    }
    _client = UlinkBleProvisioningClient(config: _config);
    await _client!.connect(assigned.device);
  }

  @override
  Future<void> prepare() async {
    final client = _client;
    if (client == null) {
      throw const UlinkUnflashException(
        'The assigned U-Link is not connected.',
      );
    }
    await client.waitForInitialSettings();
    await client.openDeveloperMode();
  }

  @override
  Future<void> clearUcode(String ucode) => _client!.unflashUcode(ucode);

  @override
  Future<void> waitForRestart() =>
      _client!.waitForDisconnect(const Duration(seconds: 12));

  @override
  Future<void> verifyFactory() async {
    final matches = await _scanMatches(
      (result) =>
          UlinkAdvertisementMatcher.isFactoryName(
            result.advertisementData.advName,
          ) &&
          _hasConfiguredService(result),
    );
    final known = _knownRemoteId;
    if (known != null &&
        matches.any((result) => result.device.remoteId.str == known)) {
      return;
    }
    if (matches.length == 1) return;
    throw const UlinkUnflashException(
      'More than one factory ULINK was found. Keep only this U-Link nearby and select it before continuing.',
    );
  }

  @override
  Future<void> disconnect() async {
    final client = _client;
    _client = null;
    if (client != null) {
      await client.disconnect();
    }
  }

  bool _hasConfiguredService(ScanResult result) =>
      UlinkAdvertisementMatcher.hasService(
        result.advertisementData.serviceUuids.map((uuid) => uuid.str),
        _config.serviceUuid,
      );

  Future<ScanResult> _scanOne(bool Function(ScanResult) matches) async {
    final all = await _scanMatches(matches, stopOnFirst: true);
    return all.single;
  }

  Future<List<ScanResult>> _scanMatches(
    bool Function(ScanResult) matches, {
    bool stopOnFirst = false,
  }) async {
    final found = <String, ScanResult>{};
    final completion = Completer<void>();
    late final StreamSubscription<List<ScanResult>> subscription;
    subscription = FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        if (matches(result)) {
          found[result.device.remoteId.str] = result;
        }
      }
      if (stopOnFirst && found.isNotEmpty && !completion.isCompleted) {
        completion.complete();
      }
    });
    try {
      unawaited(
        FlutterBluePlus.startScan(
          timeout: scanTimeout,
          androidScanMode: AndroidScanMode.lowLatency,
        ),
      );
      if (stopOnFirst) {
        await completion.future.timeout(scanTimeout);
      } else {
        await Future<void>.delayed(scanTimeout);
      }
      if (found.isEmpty) {
        throw const UlinkUnflashException(
          'No matching U-Link advertisement with the required service was found.',
        );
      }
      return found.values.toList(growable: false);
    } on TimeoutException {
      throw const UlinkUnflashException(
        'No matching U-Link advertisement with the required service was found.',
      );
    } finally {
      await subscription.cancel();
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
    }
  }
}
