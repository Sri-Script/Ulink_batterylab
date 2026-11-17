import 'package:cloud_firestore/cloud_firestore.dart';

enum UcodeStatus {
  available,
  reserving,
  flashed,
  pendingVerification,
  recoveryRequired;

  static UcodeStatus fromWire(String? value) => switch (value) {
    'available' => UcodeStatus.available,
    'reserving' => UcodeStatus.reserving,
    'flashed' => UcodeStatus.flashed,
    'pending_verification' => UcodeStatus.pendingVerification,
    'recovery_required' => UcodeStatus.recoveryRequired,
    _ => throw FormatException('Unknown UCode status.'),
  };

  String get wireValue => switch (this) {
    UcodeStatus.available => 'available',
    UcodeStatus.reserving => 'reserving',
    UcodeStatus.flashed => 'flashed',
    UcodeStatus.pendingVerification => 'pending_verification',
    UcodeStatus.recoveryRequired => 'recovery_required',
  };
}

class ProvisioningCompany {
  const ProvisioningCompany({required this.id, required this.name});

  factory ProvisioningCompany.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    return ProvisioningCompany(
      id: document.id,
      name: data['name'] is String && (data['name'] as String).trim().isNotEmpty
          ? (data['name'] as String).trim()
          : document.id,
    );
  }

  final String id;
  final String name;
}

class ProvisioningUcode {
  const ProvisioningUcode({
    required this.ucode,
    required this.assignedSiUid,
    required this.status,
    this.companyId,
    this.reservationId,
  });

  factory ProvisioningUcode.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    final ucode = data['ucode'];
    final siUid = data['assignedSiUid'];
    if (ucode is! String || siUid is! String) {
      throw const FormatException('Invalid UCode document.');
    }
    return ProvisioningUcode(
      ucode: ucode,
      assignedSiUid: siUid,
      status: UcodeStatus.fromWire(data['status'] as String?),
      companyId: data['companyId'] as String?,
      reservationId: data['reservationId'] as String?,
    );
  }

  final String ucode;
  final String assignedSiUid;
  final UcodeStatus status;
  final String? companyId;
  final String? reservationId;
}

class UcodeReservation {
  const UcodeReservation({
    required this.ucode,
    required this.companyId,
    required this.siUid,
    required this.reservationId,
  });

  final String ucode;
  final String companyId;
  final String siUid;
  final String reservationId;
}

enum ProvisioningProgress {
  idle,
  reservingUcode,
  scanning,
  connecting,
  writingUcode,
  waitingForReset,
  verifyingUlink,
  readyForSettings,
  pendingVerification,
  cancelled,
  failed,
}

extension ProvisioningProgressLabel on ProvisioningProgress {
  String get label => switch (this) {
    ProvisioningProgress.idle => 'Ready',
    ProvisioningProgress.reservingUcode => 'Reserving UCode',
    ProvisioningProgress.scanning => 'Scanning',
    ProvisioningProgress.connecting => 'Connecting',
    ProvisioningProgress.writingUcode => 'Writing UCode',
    ProvisioningProgress.waitingForReset => 'Waiting for reset',
    ProvisioningProgress.verifyingUlink => 'Verifying U-Link',
    ProvisioningProgress.readyForSettings => 'Ready for settings',
    ProvisioningProgress.pendingVerification => 'Pending verification',
    ProvisioningProgress.cancelled => 'Cancelled',
    ProvisioningProgress.failed => 'Failed',
  };
}
