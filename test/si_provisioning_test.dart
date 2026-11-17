import 'package:flutter_test/flutter_test.dart';
import 'package:ulink_batterylab/models/si_provisioning_models.dart';
import 'package:ulink_batterylab/services/provisioning_repository.dart';
import 'package:ulink_batterylab/services/ulink_ble_protocol_config.dart';
import 'package:ulink_batterylab/services/ulink_provisioning_protocol.dart';

void main() {
  group('SI provisioning repository contract', () {
    test(
      'SI company filtering returns only server-assigned companies',
      () async {
        final repository = _MemoryRepository(
          companies: const [
            _CompanyRecord('north', 'North', ['si-a']),
            _CompanyRecord('south', 'South', ['si-b']),
          ],
        );

        expect((await repository.companiesForSi('si-a')).map((it) => it.id), [
          'north',
        ]);
      },
    );

    test('available UCodes exclude flashed and assigned U-Links', () async {
      final repository = _MemoryRepository(
        ucodes: [
          _record('free', 'si-a', UcodeStatus.available),
          _record('flashed', 'si-a', UcodeStatus.flashed, companyId: 'north'),
          _record('reserved', 'si-a', UcodeStatus.reserving),
          _record('other', 'si-b', UcodeStatus.available),
        ],
      );

      expect(
        (await repository.availableUcodesForSi('si-a')).map((it) => it.ucode),
        ['free'],
      );
    });

    test(
      'assigned U-Link list has only flashed UCodes for selected company',
      () async {
        final repository = _MemoryRepository(
          ucodes: [
            _record(
              'north-flashed',
              'si-a',
              UcodeStatus.flashed,
              companyId: 'north',
            ),
            _record(
              'north-pending',
              'si-a',
              UcodeStatus.pendingVerification,
              companyId: 'north',
            ),
            _record(
              'south-flashed',
              'si-a',
              UcodeStatus.flashed,
              companyId: 'south',
            ),
          ],
        );

        expect(
          (await repository.assignedUcodesForCompany(
            'north',
          )).map((it) => it.ucode),
          ['north-flashed'],
        );
      },
    );

    test('reservation transaction prevents duplicate allocation', () async {
      final repository = _MemoryRepository(
        ucodes: [_record('UC-1', 'si-a', UcodeStatus.available)],
      );

      final first = repository.reserveUcode(
        ucode: 'UC-1',
        companyId: 'north',
        siUid: 'si-a',
      );
      final second = repository.reserveUcode(
        ucode: 'UC-1',
        companyId: 'north',
        siUid: 'si-a',
      );
      final results = await Future.wait<Object?>([
        first.then<Object?>((value) => value).catchError((_) => null),
        second.then<Object?>((value) => value).catchError((_) => null),
      ]);

      expect(results.whereType<UcodeReservation>(), hasLength(1));
      expect(repository.record('UC-1').status, UcodeStatus.reserving);
    });

    test(
      'failed BLE write before acknowledgement releases reservation',
      () async {
        final repository = _MemoryRepository(
          ucodes: [_record('UC-2', 'si-a', UcodeStatus.available)],
        );
        final coordinator = UlinkProvisioningCoordinator(repository);
        await coordinator.reserve(
          ucode: 'UC-2',
          companyId: 'north',
          siUid: 'si-a',
        );
        await coordinator.cancelBeforeAcknowledgement();

        expect(repository.record('UC-2').status, UcodeStatus.available);
      },
    );

    test(
      'positive acknowledgement without verification becomes pending, not available',
      () async {
        final repository = _MemoryRepository(
          ucodes: [_record('UC-3', 'si-a', UcodeStatus.available)],
        );
        final coordinator = UlinkProvisioningCoordinator(repository);
        await coordinator.reserve(
          ucode: 'UC-3',
          companyId: 'north',
          siUid: 'si-a',
        );
        await coordinator.recordPositiveAcknowledgement();
        await coordinator.verificationDidNotArrive();

        expect(
          repository.record('UC-3').status,
          UcodeStatus.pendingVerification,
        );
        expect(repository.events, hasLength(1));
      },
    );

    test(
      'finalization applies only to its selected company and UCode',
      () async {
        final repository = _MemoryRepository(
          ucodes: [
            _record('UC-4', 'si-a', UcodeStatus.available),
            _record('UC-5', 'si-a', UcodeStatus.available),
          ],
        );
        final reservation = await repository.reserveUcode(
          ucode: 'UC-4',
          companyId: 'north',
          siUid: 'si-a',
        );
        await repository.finalizeVerifiedUcode(reservation);

        expect(repository.record('UC-4').companyId, 'north');
        expect(repository.record('UC-4').status, UcodeStatus.flashed);
        expect(repository.record('UC-5').companyId, isNull);
        expect(repository.record('UC-5').status, UcodeStatus.available);
      },
    );
  });

  group('firmware advertisement gate', () {
    const config = UlinkBleProtocolConfig(
      namePrefix: 'ULINK',
      serviceUuid: UlinkBleProtocolConfig.productionServiceUuid,
      commandCharacteristicUuid:
          UlinkBleProtocolConfig.productionCommandCharacteristicUuid,
      responseCharacteristicUuid:
          UlinkBleProtocolConfig.productionResponseCharacteristicUuid,
      ackTimeout: Duration(seconds: 1),
    );

    test(
      'selected-advertisement matching rejects a U-Link with another UCode',
      () {
        final matcher = UlinkAdvertisementMatcher(
          config: config,
          advertisedUcode: _testAdvertisementUcode,
        );
        expect(
          matcher.matchesSelectedUcode(
            serviceUuids: [UlinkBleProtocolConfig.productionServiceUuid],
            advertisedName: 'ULINK',
            manufacturerData: [2],
            selectedUcode: 'UC-1',
          ),
          isFalse,
        );
      },
    );

    test(
      'Option 2 never has a UCode write transport in this firmware build',
      () {
        expect(UlinkProvisioningFirmwareSupport.supportsUcodeWrite, isFalse);
        expect(
          UlinkProvisioningFirmwareSupport.ucodeWriteUnavailableMessage,
          'U-Link firmware does not yet support UCode flashing.',
        );
      },
    );
  });
}

String? _testAdvertisementUcode(String _, List<int> data) =>
    data.isNotEmpty && data.first == 1 ? 'UC-1' : 'UC-OTHER';

class _CompanyRecord {
  const _CompanyRecord(this.id, this.name, this.integrators);
  final String id;
  final String name;
  final List<String> integrators;
}

class _UcodeRecord {
  _UcodeRecord({
    required this.ucode,
    required this.siUid,
    required this.status,
    this.companyId,
  });
  final String ucode;
  final String siUid;
  UcodeStatus status;
  String? companyId;
  String? reservationId;

  ProvisioningUcode get value => ProvisioningUcode(
    ucode: ucode,
    assignedSiUid: siUid,
    status: status,
    companyId: companyId,
    reservationId: reservationId,
  );
}

_UcodeRecord _record(
  String ucode,
  String siUid,
  UcodeStatus status, {
  String? companyId,
}) => _UcodeRecord(
  ucode: ucode,
  siUid: siUid,
  status: status,
  companyId: companyId,
);

class _MemoryRepository implements ProvisioningRepository {
  _MemoryRepository({
    List<_CompanyRecord> companies = const [],
    List<_UcodeRecord> ucodes = const [],
  }) : _companies = companies,
       _ucodes = {for (final item in ucodes) item.ucode: item};

  final List<_CompanyRecord> _companies;
  final Map<String, _UcodeRecord> _ucodes;
  final List<UcodeReservation> events = [];
  int _reservationSequence = 0;

  _UcodeRecord record(String ucode) => _ucodes[ucode]!;

  @override
  Future<List<ProvisioningCompany>> companiesForSi(String siUid) async =>
      _companies
          .where((company) => company.integrators.contains(siUid))
          .map(
            (company) =>
                ProvisioningCompany(id: company.id, name: company.name),
          )
          .toList();

  @override
  Future<List<ProvisioningUcode>> availableUcodesForSi(String siUid) async =>
      _ucodes.values
          .where(
            (item) =>
                item.siUid == siUid &&
                item.status == UcodeStatus.available &&
                item.companyId == null,
          )
          .map((item) => item.value)
          .toList();

  @override
  Future<List<ProvisioningUcode>> assignedUcodesForCompany(
    String companyId,
  ) async => _ucodes.values
      .where(
        (item) =>
            item.companyId == companyId && item.status == UcodeStatus.flashed,
      )
      .map((item) => item.value)
      .toList();

  @override
  Future<UcodeReservation> reserveUcode({
    required String ucode,
    required String companyId,
    required String siUid,
  }) async {
    final record = this.record(ucode);
    if (record.siUid != siUid ||
        record.status != UcodeStatus.available ||
        record.companyId != null) {
      throw const ProvisioningException('not available');
    }
    final reservation = UcodeReservation(
      ucode: ucode,
      companyId: companyId,
      siUid: siUid,
      reservationId: 'r${++_reservationSequence}',
    );
    record.status = UcodeStatus.reserving;
    record.reservationId = reservation.reservationId;
    return reservation;
  }

  bool _owns(UcodeReservation reservation) {
    final item = record(reservation.ucode);
    return item.status == UcodeStatus.reserving &&
        item.siUid == reservation.siUid &&
        item.reservationId == reservation.reservationId &&
        item.companyId == null;
  }

  @override
  Future<void> releaseReservation(UcodeReservation reservation) async {
    if (!_owns(reservation)) throw const ProvisioningException('invalid');
    final item = record(reservation.ucode);
    item.status = UcodeStatus.available;
    item.reservationId = null;
  }

  @override
  Future<void> recordProvisioningAcknowledged(
    UcodeReservation reservation,
  ) async {
    if (!_owns(reservation)) throw const ProvisioningException('invalid');
    events.add(reservation);
  }

  @override
  Future<void> markVerificationPending(
    UcodeReservation reservation, {
    required bool recoveryRequired,
  }) async {
    if (!_owns(reservation)) throw const ProvisioningException('invalid');
    record(reservation.ucode).status = recoveryRequired
        ? UcodeStatus.recoveryRequired
        : UcodeStatus.pendingVerification;
  }

  @override
  Future<void> finalizeVerifiedUcode(UcodeReservation reservation) async {
    if (!_owns(reservation)) throw const ProvisioningException('invalid');
    final item = record(reservation.ucode);
    item.status = UcodeStatus.flashed;
    item.companyId = reservation.companyId;
  }
}
