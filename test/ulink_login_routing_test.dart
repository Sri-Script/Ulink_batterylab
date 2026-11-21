import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ulink_batterylab/models/si_provisioning_models.dart';
import 'package:ulink_batterylab/screens/si_company_selection_screen.dart';
import 'package:ulink_batterylab/screens/ulink_device_picker_screen.dart';
import 'package:ulink_batterylab/screens/ulink_login_screen.dart';
import 'package:ulink_batterylab/screens/ulink_wifi_provisioning_screen.dart';
import 'package:ulink_batterylab/services/provisioning_repository.dart';
import 'package:ulink_batterylab/services/si_access_repository.dart';
import 'package:ulink_batterylab/services/ulink_ble_provisioning_client.dart';
import 'package:ulink_batterylab/services/ulink_login_preferences.dart';

void main() {
  test('SharedPreferences stores only the normalized U-Link email', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = SharedPreferencesUlinkLoginPreferences();

    await preferences.saveEmail(' User@Example.COM ');
    final raw = await SharedPreferences.getInstance();

    expect(
      raw.getString(SharedPreferencesUlinkLoginPreferences.emailKey),
      'user@example.com',
    );
    expect(raw.getKeys(), <String>{
      SharedPreferencesUlinkLoginPreferences.emailKey,
    });
  });

  testWidgets('custom-claim SI user routes to Company Selection', (
    tester,
  ) async {
    await _pumpLogin(
      tester,
      roleLookup: () async =>
          SiRolePolicy.isCustomClaimSystemIntegratorRole(' SI '),
    );

    await _signIn(tester);

    expect(find.byType(SiCompanySelectionScreen), findsOneWidget);
    expect(find.text('Select Company'), findsOneWidget);
  });

  testWidgets('legacy Firestore role SI user routes to Company Selection', (
    tester,
  ) async {
    await _pumpLogin(
      tester,
      roleLookup: () async => SiRolePolicy.isLegacyProfileSystemIntegratorRole(
        ' system integrator ',
      ),
      repository: _CompanyListRepository(const [
        ProvisioningCompany(id: 'assigned', name: 'Assigned Company'),
      ]),
    );

    await _signIn(tester);
    await tester.pumpAndSettle();

    expect(find.byType(SiCompanySelectionScreen), findsOneWidget);
    expect(find.text('Assigned Company'), findsOneWidget);
  });

  testWidgets('normal user still follows the existing U-Link route', (
    tester,
  ) async {
    await _pumpLogin(tester, roleLookup: () async => false);

    await _signIn(tester);

    expect(find.byType(UlinkDevicePickerScreen), findsOneWidget);
    expect(find.byType(SiCompanySelectionScreen), findsNothing);
  });

  testWidgets('successful login saves only the normalized email address', (
    tester,
  ) async {
    final preferences = _MemoryLoginPreferences();
    await _pumpLogin(
      tester,
      roleLookup: () async => false,
      loginPreferences: preferences,
    );

    await tester.enterText(find.byType(TextField).at(0), ' User@Example.COM ');
    await tester.enterText(find.byType(TextField).at(1), 'not-to-be-saved');
    await tester.tap(find.text('Sign in'));
    await tester.pump();
    await tester.pump();

    expect(preferences.email, 'user@example.com');
    expect(preferences.savedValues, ['user@example.com']);
  });

  testWidgets('reopening U-Link login restores email but never password', (
    tester,
  ) async {
    final preferences = _MemoryLoginPreferences(email: 'user@example.com');
    await tester.pumpWidget(
      MaterialApp(home: UlinkLoginScreen(loginPreferences: preferences)),
    );
    await tester.pump();

    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList();
    expect(fields[0].controller!.text, 'user@example.com');
    expect(fields[1].controller!.text, isEmpty);
  });

  testWidgets('logout clears the remembered email', (tester) async {
    final preferences = _MemoryLoginPreferences(email: 'user@example.com');
    await tester.pumpWidget(
      MaterialApp(home: UlinkLogoutButton(loginPreferences: preferences)),
    );

    await tester.tap(find.byTooltip('Log out'));
    await tester.pumpAndSettle();

    expect(preferences.email, isNull);
    expect(find.byType(UlinkLoginScreen), findsOneWidget);
  });

  testWidgets('SI can open the existing U-Link settings picker directly', (
    tester,
  ) async {
    final repository = _RefreshingCompanyRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: SiCompanySelectionScreen(siUid: 'si-1', repository: repository),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Connect to U-Link Settings'), findsOneWidget);
    expect(repository.companyQueryCount, 1);

    await tester.tap(find.text('Connect to U-Link Settings'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(UlinkDevicePickerScreen), findsOneWidget);
    expect(repository.companyQueryCount, 1);
  });

  testWidgets(
    'successful picker connection opens the existing settings screen',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: UlinkDevicePickerScreen(
            startScanning: false,
            initialResults: <ScanResult>[_ulinkScanResult()],
            clientConnector: (_, _) async => _PickerSettingsClient(),
          ),
        ),
      );

      await tester.tap(find.text('ULINK-REV4'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(UlinkWifiProvisioningScreen), findsOneWidget);
    },
  );

  testWidgets('SI with no companies sees the clear empty state', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SiCompanySelectionScreen(
          siUid: 'si-1',
          repository: _EmptyProvisioningRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Select Company'), findsOneWidget);
    expect(
      find.text('No companies are assigned to this System Integrator.'),
      findsOneWidget,
    );
    expect(find.text('Refresh'), findsOneWidget);
  });

  testWidgets('Refresh reruns the company query after an empty server result', (
    tester,
  ) async {
    final repository = _RefreshingCompanyRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: SiCompanySelectionScreen(siUid: 'si-1', repository: repository),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('No companies are assigned to this System Integrator.'),
      findsOneWidget,
    );
    expect(repository.companyQueryCount, 1);

    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();

    expect(repository.companyQueryCount, 2);
    expect(find.text('Test Company'), findsOneWidget);
  });

  testWidgets('companies are alphabetically sorted in the selection UI', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SiCompanySelectionScreen(
          siUid: 'si-1',
          repository: _CompanyListRepository(const [
            ProvisioningCompany(id: 'zebra', name: 'zebra'),
            ProvisioningCompany(id: 'alpha', name: 'alpha'),
            ProvisioningCompany(id: 'middle', name: 'Middle'),
          ]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widgetList<ListTile>(find.byType(ListTile))
          .map((tile) => (tile.title! as Text).data)
          .toList(),
      ['alpha', 'Middle', 'zebra'],
    );
  });

  testWidgets('role lookup error is visible and does not route incorrectly', (
    tester,
  ) async {
    await _pumpLogin(
      tester,
      roleLookup: () async => throw const SiRoleLookupException('denied'),
    );

    await _signIn(tester);

    expect(find.byType(UlinkLoginScreen), findsOneWidget);
    expect(find.byType(SiCompanySelectionScreen), findsNothing);
    expect(find.byType(UlinkDevicePickerScreen), findsNothing);
    expect(
      find.text(
        'We could not verify your System Integrator access. Check your Firebase permissions and try again.',
      ),
      findsOneWidget,
    );
  });

  test(
    'SI role policy normalizes supported Firebase and legacy role strings',
    () {
      expect(SiRolePolicy.isCustomClaimSystemIntegratorRole('si'), isTrue);
      expect(
        SiRolePolicy.isCustomClaimSystemIntegratorRole('SYSTEM_INTEGRATOR'),
        isTrue,
      );
      expect(
        SiRolePolicy.isLegacyProfileSystemIntegratorRole(' System Integrator '),
        isTrue,
      );
      expect(
        SiRolePolicy.isCustomClaimSystemIntegratorRole('system integrator'),
        isFalse,
      );
    },
  );
}

Future<void> _pumpLogin(
  WidgetTester tester, {
  required Future<bool> Function() roleLookup,
  ProvisioningRepository? repository,
  UlinkLoginPreferences? loginPreferences,
}) => tester.pumpWidget(
  MaterialApp(
    home: UlinkLoginScreen(
      loginSession: (_, _) async =>
          UlinkLoginSession(uid: 'si-or-user', resolveSiRole: roleLookup),
      siProvisioningRepository: repository ?? _EmptyProvisioningRepository(),
      loginPreferences: loginPreferences ?? _MemoryLoginPreferences(),
    ),
  ),
);

Future<void> _signIn(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).at(0), 'user@example.com');
  await tester.enterText(find.byType(TextField).at(1), 'password');
  await tester.tap(find.text('Sign in'));
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

class _EmptyProvisioningRepository implements ProvisioningRepository {
  @override
  Future<List<ProvisioningCompany>> companiesForSi(String siUid) async => [];

  @override
  Future<List<ProvisioningUcode>> availableUcodesForSi(String siUid) =>
      throw UnimplementedError();

  @override
  Future<List<ProvisioningUcode>> assignedUcodesForCompany(String companyId) =>
      throw UnimplementedError();

  @override
  Future<UcodeReservation> reserveUcode({
    required String ucode,
    required String companyId,
    required String siUid,
  }) => throw UnimplementedError();

  @override
  Future<void> releaseReservation(UcodeReservation reservation) =>
      throw UnimplementedError();

  @override
  Future<void> recordProvisioningAcknowledged(UcodeReservation reservation) =>
      throw UnimplementedError();

  @override
  Future<void> markVerificationPending(
    UcodeReservation reservation, {
    required bool recoveryRequired,
  }) => throw UnimplementedError();

  @override
  Future<void> finalizeVerifiedUcode(UcodeReservation reservation) =>
      throw UnimplementedError();
}

class _CompanyListRepository extends _EmptyProvisioningRepository {
  _CompanyListRepository(this.companies);

  final List<ProvisioningCompany> companies;

  @override
  Future<List<ProvisioningCompany>> companiesForSi(String siUid) async =>
      List<ProvisioningCompany>.of(companies);
}

class _RefreshingCompanyRepository extends _EmptyProvisioningRepository {
  int companyQueryCount = 0;

  @override
  Future<List<ProvisioningCompany>> companiesForSi(String siUid) async {
    companyQueryCount++;
    return companyQueryCount == 1
        ? []
        : const [ProvisioningCompany(id: 'test-company', name: 'Test Company')];
  }
}

class _MemoryLoginPreferences implements UlinkLoginPreferences {
  _MemoryLoginPreferences({this.email});

  String? email;
  final List<String> savedValues = <String>[];

  @override
  Future<void> clearEmail() async => email = null;

  @override
  Future<String?> readEmail() async => email;

  @override
  Future<void> saveEmail(String value) async {
    email = value;
    savedValues.add(value);
  }
}

ScanResult _ulinkScanResult() => ScanResult(
  device: BluetoothDevice.fromId('00:11:22:33:44:55'),
  advertisementData: AdvertisementData(
    advName: 'ULINK-REV4',
    txPowerLevel: null,
    appearance: null,
    connectable: true,
    manufacturerData: <int, List<int>>{},
    serviceData: <Guid, List<int>>{},
    serviceUuids: <Guid>[],
  ),
  rssi: -42,
  timeStamp: DateTime.now(),
);

class _PickerSettingsClient implements UlinkSettingsClient {
  @override
  String get deviceName => 'ULINK-REV4';

  @override
  Stream<UlinkProtocolEvent> get events =>
      const Stream<UlinkProtocolEvent>.empty();

  @override
  UlinkSettings? get latestSettings => null;

  @override
  Future<void> disconnect() async {}

  @override
  Future<UlinkSettings> refreshSettings() => throw UnimplementedError();

  @override
  Future<void> saveSetting(UlinkSettingsKey key, String value) =>
      throw UnimplementedError();
}
