import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ulink_batterylab/screens/vtm_demo_calibration_screen.dart';

void main() {
  final store = VtmDemoStore.instance;

  setUp(() {
    store.period = VtmTrendPeriod.day;
  });

  test('each VTM demo period creates two valid, distinct series', () {
    for (final period in VtmTrendPeriod.values) {
      store.period = period;
      final voltage = store.voltageSeries;
      final temperature = store.temperatureSeries;

      expect(voltage, hasLength(2));
      expect(temperature, hasLength(2));
      expect(voltage[0], hasLength(period.sampleCount));
      expect(voltage[1], hasLength(period.sampleCount));
      expect(temperature[0], hasLength(period.sampleCount));
      expect(temperature[1], hasLength(period.sampleCount));
      expect(voltage[0], isNot(equals(voltage[1])));
      expect(temperature[0], isNot(equals(temperature[1])));
      expect(
        voltage
            .expand((series) => series)
            .every((value) => value > 12.3 && value < 13.0),
        isTrue,
      );
      expect(
        temperature
            .expand((series) => series)
            .every((value) => value > 25 && value < 31),
        isTrue,
      );
    }
  });

  testWidgets(
    '360dp dashboard keeps both battery cards side by side and charts bounded',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_demoApp());
      await tester.pump();

      expect(find.text('Battery Monitoring'), findsOneWidget);
      expect(find.text('Demo site: Lab bench'), findsOneWidget);
      expect(find.text('Demo Online'), findsOneWidget);
      expect(find.text('Battery 1 (12 V)'), findsOneWidget);
      expect(find.text('Battery 2 (12 V)'), findsOneWidget);
      expect(find.byType(LineChart), findsAtLeastNWidgets(1));

      final batteryOne = tester.getTopLeft(find.text('Battery 1 (12 V)'));
      final batteryTwo = tester.getTopLeft(find.text('Battery 2 (12 V)'));
      expect(batteryTwo.dx, greaterThan(batteryOne.dx));
      expect((batteryTwo.dy - batteryOne.dy).abs(), lessThan(2));
      expect(
        tester.getBottomRight(find.text('Battery 2 (12 V)')).dy,
        lessThan(640),
      );

      await tester.drag(find.byType(Scrollable).first, const Offset(0, -480));
      await tester.pump();
      expect(find.text('Temperature'), findsWidgets);
      expect(find.byType(LineChart), findsAtLeastNWidgets(1));
    },
  );

  testWidgets(
    'wider phone and tablet widths retain the compact two-column grid',
    (tester) async {
      for (final width in [393.0, 800.0]) {
        await tester.binding.setSurfaceSize(Size(width, 800));
        await tester.pumpWidget(_demoApp());
        await tester.pump();

        final batteryOne = tester.getTopLeft(find.text('Battery 1 (12 V)'));
        final batteryTwo = tester.getTopLeft(find.text('Battery 2 (12 V)'));
        expect(
          batteryTwo.dx,
          greaterThan(batteryOne.dx),
          reason: 'expected two columns at ${width}dp',
        );
      }
      addTearDown(() => tester.binding.setSurfaceSize(null));
    },
  );

  testWidgets(
    'changing the dashboard period updates the selected label and chart data',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_demoApp());
      await tester.pump();

      await tester.tap(find.byType(DropdownButtonFormField<VtmTrendPeriod>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Last 30 Days').last);
      await tester.pumpAndSettle();

      expect(store.period, VtmTrendPeriod.month);
      expect(store.voltageSeries.first, hasLength(30));
      expect(store.temperatureSeries.first, hasLength(30));
      expect(find.text('Last 30 Days'), findsWidgets);
      expect(find.byType(LineChart), findsAtLeastNWidgets(1));
    },
  );
}

Widget _demoApp() => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
    child: child!,
  ),
  theme: ThemeData.dark(useMaterial3: true).copyWith(
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.cyan,
      brightness: Brightness.dark,
    ),
  ),
  home: const VtmDemoCalibrationScreen(),
);
