import 'package:flutter_test/flutter_test.dart';

import 'package:ulink_batterylab/config/device_contract.dart';
import 'package:ulink_batterylab/config/vtm_nus_contract.dart';

void main() {
  test('recognizes VTM names without changing Ulink matching', () {
    expect(VtmNusContract.matchesName('VTM-7FAF'), isTrue);
    expect(VtmNusContract.matchesName('VTM-0001'), isTrue);
    expect(VtmNusContract.matchesName('VTM 001'), isFalse);
    expect(VtmNusContract.matchesName('vtm-001'), isFalse);
    expect(DeviceContract.matchesAdvertisingName('ULINK-GW-TEST01'), isTrue);
    expect(DeviceContract.matchesAdvertisingName('VTM 001'), isFalse);
  });

  test('selects exact Nordic UART UUIDs', () {
    expect(VtmNusContract.sameUuid(
      '6E400001-B5A3-F393-E0A9-E50E24DCCA9E',
      VtmNusContract.serviceUuid,
    ), isTrue);
    expect(VtmNusContract.sameUuid(
      '6E400002-B5A3-F393-E0A9-E50E24DCCA9E',
      VtmNusContract.rxUuid,
    ), isTrue);
    expect(VtmNusContract.sameUuid(
      '6E400003-B5A3-F393-E0A9-E50E24DCCA9E',
      VtmNusContract.txUuid,
    ), isTrue);
    expect(VtmNusContract.sameUuid(VtmNusContract.rxUuid, VtmNusContract.txUuid), isFalse);
  });

  test('fresh matching requires the selected name and remote id', () {
    expect(VtmNusContract.matchesFreshAdvertisement(
      advertisedName: 'VTM 001', remoteId: 'AA-BB',
      selectedName: 'VTM 001', selectedRemoteId: 'aa:bb',
    ), isTrue);
    expect(VtmNusContract.matchesFreshAdvertisement(
      advertisedName: 'VTM 001', remoteId: 'AA:CC',
      selectedName: 'VTM 001', selectedRemoteId: 'aa:bb',
    ), isFalse);
    expect(VtmNusContract.matchesFreshAdvertisement(
      advertisedName: 'VTM 002', remoteId: 'AA:BB',
      selectedName: 'VTM 001', selectedRemoteId: 'aa:bb',
    ), isFalse);
  });
}
