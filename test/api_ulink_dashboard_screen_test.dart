import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ulink_batterylab/features/ulink_dashboard/presentation/widgets/dashboard_widgets.dart';
import 'package:ulink_batterylab/models/ulink_api_models.dart';
import 'package:ulink_batterylab/screens/api_ulink_dashboard_screen.dart';
import 'package:ulink_batterylab/screens/ulink_device_picker_screen.dart';
import 'package:ulink_batterylab/services/api_session_store.dart';
import 'package:ulink_batterylab/services/ulink_api_repository.dart';

void main() {
  testWidgets(
    'keeps the existing device-detail unflash action available only for flashed records',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ApiDevicesScreen(
            company: const ApiCompany(cid: 'company-1', cName: 'Alpha'),
            ulink: const ApiUlink(
              uid: 'assigned-1',
              uCode: 'U-ASSIGNED-1',
              uif: true,
            ),
            session: _login().session,
            repository: _repository(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('unflash-ulink')), findsOneWidget);

      await tester.pumpWidget(
        MaterialApp(
          home: ApiDevicesScreen(
            company: const ApiCompany(cid: 'company-1', cName: 'Alpha'),
            ulink: const ApiUlink(
              uid: 'stock-1',
              uCode: 'U-STOCK-1',
              uif: false,
            ),
            session: _login().session,
            repository: _repository(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('unflash-ulink')), findsNothing);
    },
  );

  testWidgets('uses bottom navigation and preserves provision tab state', (
    tester,
  ) async {
    await _pumpDashboard(tester);
    expect(find.text('Home'), findsOneWidget);
    await _openProvision(tester);
    await _chooseCompany(tester);
    expect(find.text('Alpha Industries'), findsWidgets);

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    await _openProvision(tester);
    expect(find.text('Alpha Industries'), findsWidgets);
  });

  testWidgets('home settings hero preserves the existing settings route', (
    tester,
  ) async {
    await _pumpDashboard(tester);
    await tester.tap(find.text('Connect to U-Link Settings'));
    await tester.pump();
    expect(find.byType(UlinkDevicePickerScreen), findsOneWidget);
  });

  testWidgets('provision steps lock and flash CTA follows selection state', (
    tester,
  ) async {
    await _pumpDashboard(tester);
    await _openProvision(tester);
    expect(
      tester
          .widget<PickerField>(
            find.byKey(const Key('provision-stock-picker')),
          )
          .enabled,
      isFalse,
    );
    expect(
      tester
          .widget<PrimaryActionButton>(
            find.byKey(const Key('flash-new-ulink')),
          )
          .onPressed,
      isNull,
    );

    await _chooseCompany(tester);
    expect(
      tester
          .widget<PickerField>(
            find.byKey(const Key('provision-stock-picker')),
          )
          .enabled,
      isTrue,
    );
    await _chooseStock(tester);
    expect(
      tester
          .widget<PrimaryActionButton>(
            find.byKey(const Key('flash-new-ulink')),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const Key('provision-app-type-demo')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SelectableOptionCard>(
            find.byKey(const Key('provision-app-type-demo')),
          )
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<PrimaryActionButton>(
            find.byKey(const Key('flash-new-ulink')),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets(
    'assigned U-Link rows render API-provided state and only flashed rows expose Unflash',
    (tester) async {
      await _pumpDashboard(tester);
      await _openProvision(tester);
      await _chooseCompany(tester);
      await tester.pumpAndSettle();
      expect(find.text('U-ASSIGNED-1'), findsOneWidget);
      expect(find.text('U-NOT-FLASHED'), findsOneWidget);
      expect(find.byKey(const Key('unflash-ulink')), findsOneWidget);
    },
  );

  testWidgets('Attach / Detach remains informational with no operational controls', (
    tester,
  ) async {
    await _pumpDashboard(tester);
    await tester.tap(find.text('Attach / Detach'));
    await tester.pumpAndSettle();
    expect(
      find.text('Device attachment will be available in a future update.'),
      findsOneWidget,
    );
    expect(
      find.text('No devices or U-Links are changed from this screen.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('flash-new-ulink')), findsNothing);
    expect(find.byKey(const Key('unflash-ulink')), findsNothing);
  });

  testWidgets('dashboard avoids overflow on a narrow large-text layout', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.35)),
        child: MaterialApp(
          home: ApiSiDashboardScreen(login: _login(), repository: _repository()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpDashboard(WidgetTester tester) => tester.pumpWidget(
  MaterialApp(home: ApiSiDashboardScreen(login: _login(), repository: _repository())),
);

Future<void> _openProvision(WidgetTester tester) async {
  await tester.tap(find.text('Provision'));
  await tester.pumpAndSettle();
  expect(find.text('Provision a U-Link'), findsOneWidget);
}

Future<void> _chooseCompany(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('provision-company-picker')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Alpha Industries').last);
  await tester.pumpAndSettle();
}

Future<void> _chooseStock(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('provision-stock-picker')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('U-STOCK-1').last);
  await tester.pumpAndSettle();
}

UlinkApiRepository _repository() {
  final session = _login().session;
  return UlinkApiRepository(
    sessionStore: MemoryApiSessionStore()..value = session,
    client: MockClient((request) async {
      if (request.url.path.endsWith('/GetUlinks')) {
        return http.Response(
          '''{"Result":1,"Ulinks":[
            {"UID":"assigned-1","UCode":"U-ASSIGNED-1","UIF":true},
            {"UID":"assigned-2","UCode":"U-NOT-FLASHED","UIF":false}
          ]}''',
          200,
        );
      }
      if (request.url.path.endsWith('/GetDevices')) {
        return http.Response('{"Result":1,"Devices":[]}', 200);
      }
      return http.Response('{"Result":1}', 200);
    }),
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
    ApiCompany(cid: 'company-1', cName: 'Alpha Industries', cia: true, uCount: 2),
    ApiCompany(cid: 'company-2', cName: 'Beta Works', cia: false, uCount: 1),
  ],
  ulinks: const [
    ApiUlink(uid: 'assigned-1', uCode: 'U-ASSIGNED-1', uif: true),
  ],
  ulinksInStock: const [
    ApiUlink(uid: 'stock-1', uCode: 'U-STOCK-1', uif: false),
    ApiUlink(uid: 'stock-2', uCode: 'U-STOCK-2', uif: false),
  ],
);
