import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/si_provisioning_models.dart';

abstract class ProvisioningRepository {
  Future<List<ProvisioningCompany>> companiesForSi(String siUid);
  Future<List<ProvisioningUcode>> availableUcodesForSi(String siUid);
  Future<List<ProvisioningUcode>> assignedUcodesForCompany(String companyId);
  Future<UcodeReservation> reserveUcode({
    required String ucode,
    required String companyId,
    required String siUid,
  });
  Future<void> releaseReservation(UcodeReservation reservation);
  Future<void> recordProvisioningAcknowledged(UcodeReservation reservation);
  Future<void> markVerificationPending(
    UcodeReservation reservation, {
    required bool recoveryRequired,
  });

  /// Production finalization is a privileged Cloud Function, documented in
  /// FIREBASE_PROVISIONING.md. It must not be performed by this mobile client.
  Future<void> finalizeVerifiedUcode(UcodeReservation reservation);
}

class ProvisioningException implements Exception {
  const ProvisioningException(this.message);
  final String message;
  @override
  String toString() => message;
}

class FirestoreProvisioningRepository implements ProvisioningRepository {
  FirestoreProvisioningRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _companies =>
      _firestore.collection('companies');
  CollectionReference<Map<String, dynamic>> get _ucodes =>
      _firestore.collection('ucodes');
  CollectionReference<Map<String, dynamic>> get _events =>
      _firestore.collection('provisioningEvents');

  @override
  Future<List<ProvisioningCompany>> companiesForSi(String siUid) async {
    final snapshot = await _companies
        .where('systemIntegratorIds', arrayContains: siUid)
        .orderBy('name')
        .get();
    return snapshot.docs.map(ProvisioningCompany.fromFirestore).toList();
  }

  @override
  Future<List<ProvisioningUcode>> availableUcodesForSi(String siUid) async {
    final snapshot = await _ucodes
        .where('assignedSiUid', isEqualTo: siUid)
        .where('status', isEqualTo: UcodeStatus.available.wireValue)
        .where('companyId', isNull: true)
        .get();
    return snapshot.docs.map(ProvisioningUcode.fromFirestore).toList()
      ..sort((left, right) => left.ucode.compareTo(right.ucode));
  }

  @override
  Future<List<ProvisioningUcode>> assignedUcodesForCompany(
    String companyId,
  ) async {
    final snapshot = await _ucodes
        .where('companyId', isEqualTo: companyId)
        .where('status', isEqualTo: UcodeStatus.flashed.wireValue)
        .get();
    return snapshot.docs.map(ProvisioningUcode.fromFirestore).toList()
      ..sort((left, right) => left.ucode.compareTo(right.ucode));
  }

  @override
  Future<UcodeReservation> reserveUcode({
    required String ucode,
    required String companyId,
    required String siUid,
  }) async {
    final reservation = UcodeReservation(
      ucode: ucode,
      companyId: companyId,
      siUid: siUid,
      reservationId: _newReservationId(),
    );
    final ref = _ucodes.doc(ucode);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      final record = ProvisioningUcode.fromFirestore(snapshot);
      if (record.assignedSiUid != siUid ||
          record.status != UcodeStatus.available ||
          record.companyId != null) {
        throw const ProvisioningException('This UCode is no longer available.');
      }
      transaction.update(ref, <String, dynamic>{
        'status': UcodeStatus.reserving.wireValue,
        'reservationId': reservation.reservationId,
        // A bounded reservation prevents a stuck pre-write connection from
        // permanently consuming inventory. Server code should expire it.
        'reservationExpiresAt': Timestamp.fromDate(
          DateTime.now().toUtc().add(const Duration(minutes: 10)),
        ),
      });
    });
    return reservation;
  }

  @override
  Future<void> releaseReservation(UcodeReservation reservation) =>
      _updateOwnedReservation(reservation, (transaction, ref) {
        transaction.update(ref, <String, dynamic>{
          'status': UcodeStatus.available.wireValue,
          'reservationId': FieldValue.delete(),
          'reservationExpiresAt': FieldValue.delete(),
        });
      });

  @override
  Future<void> recordProvisioningAcknowledged(
    UcodeReservation reservation,
  ) async {
    await _events.add(<String, dynamic>{
      'ucode': reservation.ucode,
      'companyId': reservation.companyId,
      'siUid': reservation.siUid,
      'type': 'ucode_write_acknowledged',
      'status': 'acknowledged',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> markVerificationPending(
    UcodeReservation reservation, {
    required bool recoveryRequired,
  }) => _updateOwnedReservation(reservation, (transaction, ref) {
    transaction.update(ref, <String, dynamic>{
      'status':
          (recoveryRequired
                  ? UcodeStatus.recoveryRequired
                  : UcodeStatus.pendingVerification)
              .wireValue,
    });
  });

  Future<void> _updateOwnedReservation(
    UcodeReservation reservation,
    void Function(
      Transaction transaction,
      DocumentReference<Map<String, dynamic>> ref,
    )
    update,
  ) async {
    final ref = _ucodes.doc(reservation.ucode);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      final record = ProvisioningUcode.fromFirestore(snapshot);
      if (record.status != UcodeStatus.reserving ||
          record.assignedSiUid != reservation.siUid ||
          record.reservationId != reservation.reservationId ||
          record.companyId != null) {
        throw const ProvisioningException(
          'This UCode reservation is no longer valid.',
        );
      }
      update(transaction, ref);
    });
  }

  @override
  Future<void> finalizeVerifiedUcode(UcodeReservation reservation) {
    throw const ProvisioningException(
      'Secure UCode finalization requires the finalizeUlinkProvisioning Cloud Function.',
    );
  }

  String _newReservationId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
}
