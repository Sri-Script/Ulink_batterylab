import '../models/si_provisioning_models.dart';
import 'provisioning_repository.dart';
import 'ulink_ble_protocol_config.dart';

/// Firmware capability discovered from the checked-in Rev4 protocol contract.
/// It deliberately has no guessed UCode write or advertising syntax.
class UlinkProvisioningFirmwareSupport {
  const UlinkProvisioningFirmwareSupport._();

  static const ucodeWriteUnavailableMessage =
      'U-Link firmware does not yet support UCode flashing.';

  static const bool supportsUcodeWrite = false;
  static const bool supportsUcodeAdvertisement = false;
}

/// Matches only an explicitly parsed, firmware-approved advertised UCode. A
/// missing parser is unsafe and therefore matches nothing; callers must never
/// fall back to a BLE name or the first scan result.
class UlinkAdvertisementMatcher {
  const UlinkAdvertisementMatcher({required this.config, this.advertisedUcode});

  final UlinkBleProtocolConfig config;
  final String? Function(String advertisedName, List<int> manufacturerData)?
  advertisedUcode;

  bool matchesUnassigned({
    required Iterable<String> serviceUuids,
    required String advertisedName,
    required List<int> manufacturerData,
  }) {
    if (!_hasUlinkService(serviceUuids)) return false;
    final parser = advertisedUcode;
    if (parser == null) return false;
    return parser(advertisedName, manufacturerData) == null;
  }

  bool matchesSelectedUcode({
    required Iterable<String> serviceUuids,
    required String advertisedName,
    required List<int> manufacturerData,
    required String selectedUcode,
  }) {
    if (!_hasUlinkService(serviceUuids)) return false;
    final parser = advertisedUcode;
    if (parser == null) return false;
    return parser(advertisedName, manufacturerData) == selectedUcode;
  }

  bool _hasUlinkService(Iterable<String> serviceUuids) => serviceUuids.any(
    (uuid) => uuid.trim().toLowerCase() == config.serviceUuid.toLowerCase(),
  );
}

abstract class UcodeWriteTransport {
  /// Must resolve only for the exact, selected-UCode positive firmware ACK.
  Future<void> writeUcodeAndWaitForPositiveAcknowledgement(String ucode);

  Future<void> disconnect();
}

/// Coordinates state changes around BLE. It intentionally does not contain a
/// write command because this firmware revision has no documented one.
class UlinkProvisioningCoordinator {
  UlinkProvisioningCoordinator(this.repository);

  final ProvisioningRepository repository;
  UcodeReservation? _reservation;
  bool _positiveAcknowledgementReceived = false;

  ProvisioningProgress progress = ProvisioningProgress.idle;

  Future<UcodeReservation> reserve({
    required String ucode,
    required String companyId,
    required String siUid,
  }) async {
    progress = ProvisioningProgress.reservingUcode;
    final reservation = await repository.reserveUcode(
      ucode: ucode,
      companyId: companyId,
      siUid: siUid,
    );
    _reservation = reservation;
    return reservation;
  }

  Future<void> recordPositiveAcknowledgement() async {
    final reservation = _requireReservation();
    _positiveAcknowledgementReceived = true;
    await repository.recordProvisioningAcknowledged(reservation);
    progress = ProvisioningProgress.waitingForReset;
  }

  Future<void> verificationDidNotArrive({bool recoveryRequired = false}) async {
    final reservation = _requireReservation();
    if (!_positiveAcknowledgementReceived) {
      throw StateError('A positive U-Link acknowledgement is required first.');
    }
    await repository.markVerificationPending(
      reservation,
      recoveryRequired: recoveryRequired,
    );
    progress = ProvisioningProgress.pendingVerification;
  }

  Future<void> cancelBeforeAcknowledgement() async {
    final reservation = _reservation;
    if (reservation != null && !_positiveAcknowledgementReceived) {
      await repository.releaseReservation(reservation);
    }
    progress = ProvisioningProgress.cancelled;
  }

  UcodeReservation _requireReservation() {
    final reservation = _reservation;
    if (reservation == null) throw StateError('No UCode is reserved.');
    return reservation;
  }
}
