import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ulink_batterylab/main.dart';
import 'package:ulink_batterylab/screens/emulate_ulink_screen.dart';
import 'package:ulink_batterylab/services/ulink_emulator_service.dart';

const _getUrlJson = <String, dynamic>{
  'Result': 1,
  'Message': 'ok',
  'URL_API_HTTP': 'http://backend.test/api/',
  'URL_API_HTTPS': 'https://backend.test/api/',
  'URL_Application': 'https://backend.test/',
};

const _settingsJson = <String, dynamic>{
  'Result': 1,
  'Message': 'ok',
  'IsActive': 1,
  'AppType': 'Ulink',
  'CallbackInterval': 5000,
  'SendMessageInterval': 10,
  'ServerDateTime': '2026-10-03 10:00:00',
  'Token': 'settings-token',
  'DeviceCount': 1,
  'Devices': [
    {
      'ID': 7,
      'Code': 'DEV-7',
      'ByteSequence': '01',
      'AddressMode': 'RTU',
      'ParameterCount': 1,
      'DeviceParameters': [
        {
          'Serial': 3,
          'DataType': 'float',
          'Address': '1',
          'Register': '40001',
        },
      ],
    },
  ],
};

http.Response _jsonResponse(Map<String, dynamic> json) =>
    http.Response(jsonEncode(json), 200, headers: const {'content-type': 'application/json'});

void main() {
  test('service sends exact GetURL, settings, and PostRecord request shapes', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.url.path.endsWith('/GetURL')) return _jsonResponse(_getUrlJson);
      if (request.url.path.endsWith('/GetUlinkSettings')) {
        return _jsonResponse(_settingsJson);
      }
      return _jsonResponse(<String, dynamic>{
        'Result': 1,
        'Message': 'ok',
        'IsSendMessage': 0,
        'SendMessageTo': '',
        'MessageContent': '',
        'UserCommands': <String, int>{'UserCommand1': 0, 'UserCommand2': 0},
        'RelayCommands': <String, int>{'RelayCommand1': 0, 'RelayCommand2': 0},
        'Token': 'next-token',
        'DeviceCount': 1,
        'Devices': <dynamic>[],
      });
    });
    final service = UlinkEmulatorService(client: client);

    await service.getUrl();
    await service.getUlinkSettings('UC-42');
    await service.postRecord(<String, dynamic>{
      'UID': 99,
      'TimeStamp': '2026-10-03 12:34:56',
      'RelayStates': <String, int>{'RelayState1': 1, 'RelayState2': 0},
      'InputStatuses': <String, int>{
        'InputStatus1': 1,
        'InputStatus2': 0,
        'InputStatus3': 1,
        'InputStatus4': 0,
      },
      'Token': 'settings-token',
      'Devices': <Map<String, dynamic>>[
        <String, dynamic>{
          'DID': 7,
          'Code': 'DEV-7',
          'IsDeviceLive': 1,
          'DeviceParameters': <Map<String, dynamic>>[
            <String, dynamic>{'Serial': 3, 'Value': 456.78},
          ],
        },
      ],
    });

    expect(requests[0].url.toString(), 'https://ulinkwebapi.ultratech.ind.in/api/GetURL');
    expect(requests[1].url.path, '/api/GetUlinkSettings');
    expect(requests[1].url.queryParameters, <String, String>{'Type': 'json', 'UCode': 'UC-42'});
    expect(requests[2].method, 'POST');
    expect(requests[2].headers['content-type'], 'application/json; charset=utf-8');
    expect(jsonDecode(requests[2].body), <String, dynamic>{
      'UID': 99,
      'TimeStamp': '2026-10-03 12:34:56',
      'RelayStates': <String, int>{'RelayState1': 1, 'RelayState2': 0},
      'InputStatuses': <String, int>{
        'InputStatus1': 1,
        'InputStatus2': 0,
        'InputStatus3': 1,
        'InputStatus4': 0,
      },
      'Token': 'settings-token',
      'Devices': <Map<String, dynamic>>[
        <String, dynamic>{
          'DID': 7,
          'Code': 'DEV-7',
          'IsDeviceLive': 1,
          'DeviceParameters': <Map<String, dynamic>>[
            <String, dynamic>{'Serial': 3, 'Value': 456.78},
          ],
        },
      ],
    });
    print('HTTP trace: ${requests.map((request) => '${request.method} ${request.url}').join(' | ')}');
  });

  testWidgets('screen rolls tokens forward and stops timer calls after disposal', (tester) async {
    final postBodies = <Map<String, dynamic>>[];
    var postNumber = 0;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/GetURL')) return _jsonResponse(_getUrlJson);
      if (request.url.path.endsWith('/GetUlinkSettings')) return _jsonResponse(_settingsJson);
      postBodies.add(Map<String, dynamic>.from(jsonDecode(request.body) as Map));
      postNumber++;
      return _jsonResponse(<String, dynamic>{
        'Result': 1,
        'Message': 'ok',
        'IsSendMessage': 0,
        'SendMessageTo': '',
        'MessageContent': '',
        'UserCommands': <String, int>{'UserCommand1': 1, 'UserCommand2': 2},
        'RelayCommands': <String, int>{'RelayCommand1': 3, 'RelayCommand2': 4},
        'Token': 'post-token-$postNumber',
        'DeviceCount': 1,
        'Devices': <dynamic>[],
      });
    });
    final service = UlinkEmulatorService(client: client);

    await tester.pumpWidget(MaterialApp(home: EmulateUlinkScreen(service: service)));
    await tester.enterText(find.byType(TextField).first, 'UC-42');
    await tester.tap(find.text('Fetch Settings'));
    await tester.pump();
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(1), '99');
    await tester.tap(find.text('Send Now'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Send Now'));
    await tester.pump();
    await tester.pump();

    expect(postBodies[0]['Token'], 'settings-token');
    expect(postBodies[1]['Token'], 'post-token-1');
    expect((postBodies[0]['TimeStamp'] as String), matches(RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$')));

    await tester.tap(
      find.ancestor(
        of: find.text('Start Continuous Emulation'),
        matching: find.byType(SwitchListTile),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 15));
    final callsBeforeDispose = postBodies.length;
    expect(callsBeforeDispose, greaterThanOrEqualTo(3));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 50));
    expect(postBodies.length, callsBeforeDispose);
    print('Token trace: ${postBodies.map((body) => body['Token']).join(' -> ')}');
    print('Timer trace: $callsBeforeDispose POST calls before disposal; ${postBodies.length} after 50 ms.');
  });

  testWidgets('root menu is reachable on all tabs and does not overlap checked controls', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{'disclaimer_acknowledged': true});
    await tester.pumpWidget(const BatteryLabApp());
    await tester.pump();
    for (var elapsed = Duration.zero; elapsed < const Duration(seconds: 7); elapsed += const Duration(milliseconds: 500)) {
      await tester.pump(const Duration(milliseconds: 500));
    }

    final tabs = <String>['Scan / Connect', 'Design Mode', 'History', 'Live Data'];
    for (final tab in tabs) {
      await tester.tap(find.text(tab));
      await tester.pump();
      expect(find.byTooltip('Open menu'), findsOneWidget);
      await tester.tap(find.byTooltip('Open menu'));
      await tester.pump();
      expect(find.text('Emulate Ulink'), findsOneWidget);
      print('Reachability trace: $tab -> root menu -> Drawer visible');
      await tester.pageBack();
      await tester.pump();
    }

    await tester.tap(find.text('Scan / Connect'));
    await tester.pump();
    final scanFab = tester.getRect(find.byTooltip('Open menu'));
    final liveData = tester.getRect(find.text('View Live Data'));
    expect(scanFab.overlaps(liveData), isFalse);
    print('Scan overlap trace: FAB=$scanFab, View Live Data=$liveData, overlaps=false');

    await tester.tap(find.text('Design Mode'));
    await tester.pump();
    final designFab = tester.getRect(find.byTooltip('Open menu'));
    final detecting = tester.getRect(find.text('Start detecting (BLE)'));
    expect(designFab.overlaps(detecting), isFalse);
    print('Design overlap trace: FAB=$designFab, Start detecting=$detecting, overlaps=false');

    await tester.tap(find.byTooltip('Open menu'));
    await tester.pump();
    await tester.tap(find.text('Emulate Ulink'));
    await tester.pump();
    expect(find.text('Emulate Ulink'), findsOneWidget);
    expect(tester.takeException(), isNull);
    print('Navigation trace: Drawer -> Emulate Ulink -> screen built without a test exception');
  });
}
