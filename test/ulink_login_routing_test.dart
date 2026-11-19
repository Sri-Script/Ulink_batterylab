import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ulink_batterylab/models/si_provisioning_models.dart';
import 'package:ulink_batterylab/screens/si_company_selection_screen.dart';
import 'package:ulink_batterylab/screens/ulink_device_picker_screen.dart';
import 'package:ulink_batterylab/screens/ulink_login_screen.dart';
import 'package:ulink_batterylab/services/provisioning_repository.dart';
import 'package:ulink_batterylab/services/si_access_repository.dart';

void main() {
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
    );

    await _signIn(tester);

    expect(find.byType(SiCompanySelectionScreen), findsOneWidget);
  });

  testWidgets('normal user still follows the existing U-Link route', (
    tester,
  ) async {
    await _pumpLogin(tester, roleLookup: () async => false);

    await _signIn(tester);

    expect(find.byType(UlinkDevicePickerScreen), findsOneWidget);
    expect(find.byType(SiCompanySelectionScreen), findsNothing);
  });

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
}) => tester.pumpWidget(
  MaterialApp(
    home: UlinkLoginScreen(
      loginSession: (_, _) async =>
          UlinkLoginSession(uid: 'si-or-user', resolveSiRole: roleLookup),
      siProvisioningRepository: _EmptyProvisioningRepository(),
    ),
  ),
);

Future<void> _signIn(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).at(0), 'user@example.com');
  await tester.enterText(find.byType(TextField).at(1), 'password');
  await tester.tap(find.text('Sign in'));
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
