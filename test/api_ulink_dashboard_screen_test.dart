import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ulink_batterylab/models/ulink_api_models.dart';
import 'package:ulink_batterylab/screens/api_ulink_dashboard_screen.dart';
import 'package:ulink_batterylab/services/ulink_api_repository.dart';
import 'package:ulink_batterylab/services/ulink_ble_provisioning_client.dart';
import 'package:ulink_batterylab/services/ulink_flash_workflow.dart';

void main() {
  testWidgets(
    'shows summary cards, compact company rows, stock details, and provision controls',
    (tester) async {
      await _pumpDashboard(tester);

      expect(find.text('U-Link Dashboard'), findsOneWidget);
      expect(find.text('Companies'), findsWidgets);
      expect(find.text('In Stock'), findsOneWidget);
      expect(find.text('Assigned U-Links'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('Alpha Industries'), findsWidgets);
      expect(find.text('Beta Works'), findsOneWidget);
      expect(find.text('Active'), findsWidgets);
      expect(find.text('Inactive'), findsWidgets);

      await _scrollTo(tester, find.byKey(const Key('stock-ulinks-expansion')));
      await tester.tap(find.byKey(const Key('stock-ulinks-expansion')));
      await tester.pumpAndSettle();
      expect(find.text('U-STOCK-1'), findsOneWidget);
      expect(find.text('Integration mode: WIFI'), findsOneWidget);
      expect(find.text('Maximum devices: 8'), findsOneWidget);
      expect(find.text('Not flashed'), findsWidgets);
      expect(find.text('Flashed'), findsWidgets);

      await _scrollTo(tester, find.text('1. Select company'));
      expect(find.text('1. Select company'), findsOneWidget);
      expect(find.text('2. Select stock U-Link'), findsOneWidget);
      expect(find.text('3. Select deployment type'), findsOneWidget);
      expect(find.text('Demo'), findsOneWidget);
      expect(find.text('Live'), findsOneWidget);
      expect(
        find.text('Factory device must advertise as ULINK.'),
        findsOneWidget,
      );

      final flashButton = tester.widget<FilledButton>(
        find.byKey(const Key('flash-new-ulink')),
      );
      expect(flashButton.onPressed, isNull);
    },
  );

  testWidgets('keeps flash disabled until a deployment type is selected', (
    tester,
  ) async {
    await _pumpDashboard(tester);

    await _selectProvisioningInputs(tester, selectDeploymentType: false);

    final withoutType = tester.widget<FilledButton>(
      find.byKey(const Key('flash-new-ulink')),
    );
    expect(withoutType.onPressed, isNull);

    await _selectDeploymentType(tester, UlinkAppType.demo);

    final flashButton = tester.widget<FilledButton>(
      find.byKey(const Key('flash-new-ulink')),
    );
    expect(flashButton.onPressed, isNotNull);
  });

  testWidgets('shows flash progress while preflight is active', (tester) async {
    final api = _BlockingFlashApi();
    await _pumpDashboard(
      tester,
      workflowBuilder: () => UlinkFlashWorkflow(ble: _FakeFlashBle(), api: api),
    );
    await _selectProvisioningInputs(tester);
    await _confirmFlash(tester);
    await tester.pump();

    await _scrollTo(tester, find.text('Flash status'));

    expect(find.text('Flash status'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Checking API connection'), findsOneWidget);
    expect(find.text('Open U-Link Settings'), findsNothing);

    api.preflight.completeError(const UlinkApiException('network failure'));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'shows completion and Open Settings only after settings handoff',
    (tester) async {
      await _pumpDashboard(
        tester,
        workflowBuilder: () => UlinkFlashWorkflow(
          ble: _FakeFlashBle(),
          api: _SuccessfulFlashApi(),
        ),
      );
      await _selectProvisioningInputs(tester);
      await _confirmFlash(tester);
      await tester.pumpAndSettle();

      await _scrollTo(tester, find.text('U-Link provisioned'));

      expect(find.text('U-Link provisioned'), findsOneWidget);
      expect(find.text('Open U-Link Settings'), findsOneWidget);
    },
  );
}

Future<void> _pumpDashboard(
  WidgetTester tester, {
  UlinkFlashWorkflow Function()? workflowBuilder,
}) => tester.pumpWidget(
  MaterialApp(
    home: ApiSiDashboardScreen(
      login: _login(),
      repository: UlinkApiRepository(
        client: MockClient((_) async => http.Response('{"Result":1}', 200)),
      ),
      flashWorkflowBuilder: workflowBuilder,
    ),
  ),
);

Future<void> _selectProvisioningInputs(
  WidgetTester tester, {
  bool selectDeploymentType = true,
}) async {
  await _scrollTo(tester, find.byKey(const Key('provision-company-dropdown')));
  await tester.tap(find.byKey(const Key('provision-company-dropdown')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Alpha Industries').last);
  await tester.pumpAndSettle();

  await _scrollTo(tester, find.byKey(const Key('provision-stock-dropdown')));
  await tester.tap(find.byKey(const Key('provision-stock-dropdown')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('U-STOCK-1').last);
  await tester.pumpAndSettle();

  if (selectDeploymentType) {
    await _selectDeploymentType(tester, UlinkAppType.demo);
  }
}

Future<void> _selectDeploymentType(
  WidgetTester tester,
  UlinkAppType appType,
) async {
  final key = switch (appType) {
    UlinkAppType.demo => const Key('provision-app-type-demo'),
    UlinkAppType.live => const Key('provision-app-type-live'),
  };
  await _scrollTo(tester, find.byKey(key));
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  final scrollable = find.byType(Scrollable).first;
  final viewport = tester.getRect(scrollable);
  for (var attempt = 0; attempt < 20; attempt += 1) {
    if (finder.evaluate().isNotEmpty) {
      final center = tester.getCenter(finder.first, warnIfMissed: false);
      if (viewport.contains(center)) return;
    }
    await tester.drag(scrollable, const Offset(0, -280));
    await tester.pumpAndSettle();
  }
  throw TestFailure('Could not scroll target into view.');
}

Future<void> _confirmFlash(WidgetTester tester) async {
  await _scrollTo(tester, find.byKey(const Key('flash-new-ulink')));
  await tester.tap(find.byKey(const Key('flash-new-ulink')));
  await tester.pumpAndSettle();
  expect(find.textContaining('Company: Alpha Industries'), findsOneWidget);
  expect(find.textContaining('U-Link ID / UID: stock-1'), findsOneWidget);
  expect(find.textContaining('U-Link UCode: U-STOCK-1'), findsOneWidget);
  expect(find.textContaining('Deployment type: Demo'), findsOneWidget);
  await tester.tap(
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(FilledButton, 'Flash'),
    ),
  );
}

ApiLoginResult _login() => ApiLoginResult(
  session: ApiSession(
    userId: 'user-1',
    userRole: 'SI',
    userName: 'integrator',
    accessToken: 'access',
    accessTokenExpiresAtUtc: DateTime.utc(2030),
    refreshToken: 'refresh',
    refreshTokenExpiresAtUtc: DateTime.utc(2030),
  ),
  companies: const [
    ApiCompany(
      cid: 'company-1',
      cName: 'Alpha Industries',
      cia: true,
      uCount: 2,
    ),
    ApiCompany(cid: 'company-2', cName: 'Beta Works', cia: false, uCount: 1),
  ],
  ulinks: const [
    ApiUlink(
      uid: 'assigned-1',
      uCode: 'U-ASSIGNED-1',
      uif: true,
      uia: true,
      dCount: 3,
    ),
  ],
  ulinksInStock: const [
    ApiUlink(
      uid: 'stock-1',
      uCode: 'U-STOCK-1',
      udimC: 'WIFI',
      uif: false,
      uia: true,
      umd: 8,
    ),
    ApiUlink(
      uid: 'stock-2',
      uCode: 'U-STOCK-2',
      udimI: 'GSM',
      uif: true,
      uia: false,
      umd: 4,
    ),
  ],
);

class _BlockingFlashApi implements UlinkFlashApiGateway {
  final Completer<void> preflight = Completer<void>();

  @override
  Future<void> verifyPrerequisites(UlinkFlashSelection selection) =>
      preflight.future;

  @override
  Future<List<ApiUlink>> retryPendingAssignment(
    UlinkFlashSelection selection,
  ) => Future<List<ApiUlink>>.error(UnimplementedError());

  @override
  Future<List<ApiUlink>> updateAssignment(UlinkFlashSelection selection) =>
      Future<List<ApiUlink>>.error(UnimplementedError());
}

class _SuccessfulFlashApi implements UlinkFlashApiGateway {
  @override
  Future<void> verifyPrerequisites(UlinkFlashSelection selection) async {}

  @override
  Future<List<ApiUlink>> retryPendingAssignment(
    UlinkFlashSelection selection,
  ) async => _assigned(selection);

  @override
  Future<List<ApiUlink>> updateAssignment(
    UlinkFlashSelection selection,
  ) async => _assigned(selection);

  List<ApiUlink> _assigned(UlinkFlashSelection selection) => [
    ApiUlink(uid: selection.stockUlink.uid, uCode: selection.ucode, uif: true),
  ];
}

class _FakeFlashBle implements UlinkFlashBleGateway {
  @override
  Future<void> connectFactory() async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> findFactory() async {}

  @override
  Future<void> prepare() async {}

  @override
  Future<UlinkSettingsClient> reconnectForSettings() async =>
      _FakeSettingsClient();

  @override
  Future<void> verifyAssigned(String ucode) async {}

  @override
  Future<void> waitForRestart() async {}

  @override
  Future<void> writeUcode(String ucode) async {}
}

class _FakeSettingsClient implements UlinkSettingsClient {
  final StreamController<UlinkProtocolEvent> _events =
      StreamController<UlinkProtocolEvent>.broadcast();

  @override
  String get deviceName => 'ULINK-U-STOCK-1';

  @override
  Stream<UlinkProtocolEvent> get events => _events.stream;

  @override
  UlinkSettings? get latestSettings => null;

  @override
  Future<void> disconnect() async => _events.close();

  @override
  Future<UlinkSettings> refreshSettings() => throw UnimplementedError();

  @override
  Future<void> saveSetting(UlinkSettingsKey key, String value) async {}
}
