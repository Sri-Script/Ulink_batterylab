import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

enum VtmTrendPeriod { hour, day, week, month }

extension VtmTrendPeriodLabel on VtmTrendPeriod {
  String get label => switch (this) {
    VtmTrendPeriod.hour => 'Last 1 Hour',
    VtmTrendPeriod.day => 'Last 24 Hours',
    VtmTrendPeriod.week => 'Last 7 Days',
    VtmTrendPeriod.month => 'Last 30 Days',
  };

  int get sampleCount => switch (this) {
    VtmTrendPeriod.hour => 12,
    VtmTrendPeriod.day => 24,
    VtmTrendPeriod.week => 28,
    VtmTrendPeriod.month => 30,
  };

  Duration get duration => switch (this) {
    VtmTrendPeriod.hour => const Duration(hours: 1),
    VtmTrendPeriod.day => const Duration(hours: 24),
    VtmTrendPeriod.week => const Duration(days: 7),
    VtmTrendPeriod.month => const Duration(days: 30),
  };
}

/// In-memory state used exclusively by the VTM-TEST demo.
class VtmDemoStore extends ChangeNotifier {
  VtmDemoStore._();

  static final instance = VtmDemoStore._();

  // Legacy-compatible demo persistence handles used by the VTM demo tests.
  static final values = <String, String>{'voltage': '3.70'};
  final List<String> _certificates = <String>[];
  final readings = <Map<String, dynamic>>[
    {'voltage': 12.70, 'temperature': 25.0, 'time': DateTime.now()},
    {'voltage': 12.64, 'temperature': 25.4, 'time': DateTime.now()},
  ];
  final audit = <String>[];

  VtmTrendPeriod period = VtmTrendPeriod.day;
  bool calibrationPassed = false;
  Map<String, double>? calibrationValues;
  DateTime? calibrationCompletedAt;
  bool autoUpdate = false;
  int updateSeconds = 10;

  List<String> get certificates => List.unmodifiable(_certificates);
  bool get hasCertificates => _certificates.isNotEmpty;

  /// Two deterministic, visibly distinct battery series for the active period.
  List<List<double>> get voltageSeries => _buildSeries(
    baseline: 12.65,
    amplitude: 0.17,
    batteryOffset: 0.11,
    drift: 0.025,
  );

  /// Temperature stays in the realistic 25–31 °C range for this lab demo.
  List<List<double>> get temperatureSeries => _buildSeries(
    baseline: 27.9,
    amplitude: 1.75,
    batteryOffset: 0.55,
    drift: 0.12,
  );

  // Kept for the small amount of existing demo-only code that reads `series`.
  List<List<double>> get series => voltageSeries;
  List<List<double>> get temperatures => temperatureSeries;

  List<List<double>> _buildSeries({
    required double baseline,
    required double amplitude,
    required double batteryOffset,
    required double drift,
  }) {
    final count = period.sampleCount;
    return List<List<double>>.generate(2, (batteryIndex) {
      return List<double>.generate(count, (sampleIndex) {
        final progress = sampleIndex / (count - 1);
        final wave = math.sin(progress * math.pi * 3.2 + batteryIndex * 0.85);
        final ripple =
            math.cos(progress * math.pi * 7.0 + batteryIndex) * 0.045;
        final offset = batteryIndex == 0
            ? batteryOffset / 2
            : -batteryOffset / 2;
        return baseline + offset + wave * amplitude + ripple + progress * drift;
      });
    });
  }

  void log(String message) {
    audit.add('${DateTime.now().toIso8601String()} — $message');
    notifyListeners();
  }

  void refresh() {
    final random = math.Random();
    for (var index = 0; index < 2; index++) {
      readings[index]['voltage'] =
          (readings[index]['voltage'] as double) +
          (random.nextDouble() - .5) * .08;
      readings[index]['temperature'] =
          (readings[index]['temperature'] as double) +
          (random.nextDouble() - .5) * .6;
      readings[index]['time'] = DateTime.now();
    }
    log('Simulated readings refreshed');
  }

  void setPeriod(VtmTrendPeriod value) {
    if (period == value) return;
    period = value;
    log('Trend period changed to ${value.label}');
  }

  void resetReadings() {
    readings[0]
      ..['voltage'] = 12.70
      ..['temperature'] = 25.0
      ..['time'] = DateTime.now();
    readings[1]
      ..['voltage'] = 12.64
      ..['temperature'] = 25.4
      ..['time'] = DateTime.now();
    log('Readings reset');
  }

  void resetCalibration() {
    calibrationPassed = false;
    calibrationValues = null;
    calibrationCompletedAt = null;
    log('Calibration reset');
  }

  void completeCalibration({
    required double batteryOneVoltageOffset,
    required double batteryTwoVoltageOffset,
    required double temperatureOffset,
  }) {
    calibrationValues = Map.unmodifiable({
      'batteryOneVoltageOffset': batteryOneVoltageOffset,
      'batteryTwoVoltageOffset': batteryTwoVoltageOffset,
      'temperatureOffset': temperatureOffset,
    });
    calibrationCompletedAt = DateTime.now();
    calibrationPassed = true;
    log('Calibration completed with saved VTM-TEST values');
  }

  void issueCertificate() {
    final number = 'VTM-DEMO-${DateTime.now().millisecondsSinceEpoch}';
    _certificates.add(
      '$number — VTM Calibration Certificate — DEMO / NOT FOR PRODUCTION USE',
    );
    log('Demo certificate issued: $number');
  }

  void clearCertificates() {
    _certificates.clear();
    log('Certificates cleared');
  }

  static void reset() {
    values['voltage'] = '3.70';
    instance._certificates.clear();
    instance.calibrationPassed = false;
    instance.calibrationValues = null;
    instance.calibrationCompletedAt = null;
    instance.audit.clear();
    instance.notifyListeners();
  }
}

class VtmDemoCalibrationScreen extends StatefulWidget {
  const VtmDemoCalibrationScreen({super.key});

  @override
  State<VtmDemoCalibrationScreen> createState() => _VtmDemoShellState();
}

class _VtmDemoShellState extends State<VtmDemoCalibrationScreen> {
  final store = VtmDemoStore.instance;
  int tab = 0;

  @override
  void initState() {
    super.initState();
    store.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    store.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('VTM-TEST Dashboard'),
      actions: [
        IconButton(
          onPressed: store.refresh,
          icon: const Icon(Icons.refresh),
          tooltip: 'Refresh readings',
        ),
      ],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: tab,
      onDestinationSelected: (index) => setState(() => tab = index),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.dashboard_outlined),
          label: 'Dashboard',
        ),
        NavigationDestination(icon: Icon(Icons.show_chart), label: 'Trend'),
        NavigationDestination(
          icon: Icon(Icons.description_outlined),
          label: 'Reports',
        ),
        NavigationDestination(
          icon: Icon(Icons.download_outlined),
          label: 'Download',
        ),
        NavigationDestination(
          icon: Icon(Icons.settings_outlined),
          label: 'Settings',
        ),
      ],
    ),
    body: switch (tab) {
      0 => _dashboard(),
      1 => _trend(),
      2 => _reports(),
      3 => _download(),
      _ => _settings(),
    },
  );

  Widget _dashboard() {
    final voltage = store.voltageSeries;
    final temperature = store.temperatureSeries;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _summary(),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final twoColumns = constraints.maxWidth >= 320;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 2,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: twoColumns ? 2 : 1,
                mainAxisExtent: 204,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemBuilder: (_, index) => _battery(index),
            );
          },
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Trending',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(
              store.period.label,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ],
        ),
        const SizedBox(height: 8),
        _periodDropdown(),
        const SizedBox(height: 12),
        _VtmChartCard(
          title: 'Voltage',
          unit: 'V',
          period: store.period,
          data: voltage,
          height: 198,
          summary:
              'Voltage: battery terminal voltage over the selected period.',
        ),
        const SizedBox(height: 12),
        _VtmChartCard(
          title: 'Temperature',
          unit: '°C',
          period: store.period,
          data: temperature,
          height: 198,
          summary: 'Temperature: battery temperature over the selected period.',
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Icon(
              store.calibrationPassed ? Icons.check_circle : Icons.info_outline,
              color: store.calibrationPassed
                  ? Colors.green
                  : Theme.of(context).colorScheme.onSurfaceVariant,
              size: 18,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                'Calibration status: ${store.calibrationPassed ? 'Passed' : 'Not completed'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: _openCalibration,
          icon: const Icon(Icons.tune),
          label: const Text('Calibration'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: store.calibrationPassed ? _issueCertificate : null,
          icon: const Icon(Icons.verified),
          label: const Text('Issue Certificate'),
        ),
      ],
    );
  }

  Widget _summary() => SizedBox(
    height: 112,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 21,
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: .18),
                    child: Icon(
                      Icons.battery_charging_full,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Battery Monitoring',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Site: Lab Bench',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Align(alignment: Alignment.centerRight, child: _OnlinePill()),
          ],
        ),
      ),
    ),
  );

  Widget _battery(int index) {
    final reading = store.readings[index];
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final time = reading['time'] as DateTime;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: primary,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                Icon(
                  Icons.battery_full,
                  color: theme.colorScheme.onPrimary,
                  size: 19,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    'Battery ${index + 1} (12 V)',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.colorScheme.onPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SizedBox(
                    height: 30,
                    child: FittedBox(
                      alignment: Alignment.centerLeft,
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '${(reading['voltage'] as double).toStringAsFixed(2)} V',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 22,
                    child: FittedBox(
                      alignment: Alignment.centerLeft,
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '${(reading['temperature'] as double).toStringAsFixed(1)} \u00B0C',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(
                    height: 18,
                    child: FittedBox(
                      alignment: Alignment.centerLeft,
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Healthy',
                        style: TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 14,
                    child: FittedBox(
                      alignment: Alignment.centerLeft,
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Last updated: ${_timeOfDay(time)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _periodDropdown() => DropdownButtonFormField<VtmTrendPeriod>(
    initialValue: store.period,
    isExpanded: true,
    items: VtmTrendPeriod.values
        .map(
          (period) =>
              DropdownMenuItem(value: period, child: Text(period.label)),
        )
        .toList(),
    onChanged: (period) {
      if (period != null) store.setPeriod(period);
    },
    decoration: const InputDecoration(
      border: OutlineInputBorder(),
      labelText: 'Period',
      isDense: true,
    ),
  );

  Widget _trend() {
    final voltage = store.voltageSeries;
    final temperature = store.temperatureSeries;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Trend analysis',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'Detailed simulated history for the selected period.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        _periodDropdown(),
        const SizedBox(height: 14),
        _VtmChartCard(
          title: 'Voltage',
          unit: 'V',
          period: store.period,
          data: voltage,
          height: 278,
          details:
              'Meaning: battery terminal voltage over the selected period.\n'
              'X-axis: evenly sampled timestamps across ${store.period.label}.\n'
              'Y-axis: terminal voltage in volts (V).\n'
              'Series: Battery 1 is teal; Battery 2 is blue-violet.\n'
              'Simulated parameters: nominal 12 V, load variation, drift, ripple and measurement noise.',
        ),
        const SizedBox(height: 14),
        _VtmChartCard(
          title: 'Temperature',
          unit: '°C',
          period: store.period,
          data: temperature,
          height: 278,
          details:
              'Meaning: battery temperature over the selected period.\n'
              'X-axis: evenly sampled timestamps across ${store.period.label}.\n'
              'Y-axis: battery temperature in degrees Celsius (°C).\n'
              'Series: Battery 1 is teal; Battery 2 is blue-violet.\n'
              'Simulated parameters: ambient temperature, load variation, thermal drift and sensor ripple.',
        ),
      ],
    );
  }

  Widget _reports() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      _summary(),
      const SizedBox(height: 12),
      Text(
        'Latest voltage: ${(store.readings[0]['voltage'] as double).toStringAsFixed(2)} V',
      ),
      Text(
        'Latest temperature: ${(store.readings[0]['temperature'] as double).toStringAsFixed(1)} °C',
      ),
      Text(
        'Calibration: ${store.calibrationPassed ? 'Passed' : 'Not completed'}',
      ),
      Text('Certificates: ${store.certificates.length}'),
      Text('Period: ${store.period.label}'),
      const SizedBox(height: 12),
      const Text(
        'Calibration audit history',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      Text(
        store.audit.isEmpty ? 'No demo activity yet.' : store.audit.join('\n'),
      ),
    ],
  );

  Widget _download() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const Text('Demo exports are local previews only.'),
      FilledButton.icon(
        onPressed: () {
          store.log('Simulated battery report exported');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Simulated report export recorded locally.'),
            ),
          );
        },
        icon: const Icon(Icons.download),
        label: const Text('Export simulated battery report'),
      ),
      FilledButton.icon(
        onPressed: !store.hasCertificates
            ? null
            : () {
                store.log('Demo certificate exported');
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Demo certificate export recorded locally.'),
                  ),
                );
              },
        icon: const Icon(Icons.picture_as_pdf),
        label: const Text('Export demo certificate'),
      ),
    ],
  );

  Widget _settings() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      SwitchListTile(
        title: const Text('Automatic simulated live updates'),
        value: store.autoUpdate,
        onChanged: (value) {
          store.autoUpdate = value;
          store.log('Auto updates ${value ? 'enabled' : 'disabled'}');
        },
      ),
      DropdownButtonFormField<int>(
        initialValue: store.updateSeconds,
        items: [5, 10, 30]
            .map(
              (value) => DropdownMenuItem(
                value: value,
                child: Text('Every $value seconds'),
              ),
            )
            .toList(),
        onChanged: (value) {
          if (value != null) {
            store.updateSeconds = value;
            store.log('Update frequency changed');
          }
        },
        decoration: const InputDecoration(
          labelText: 'Simulated update frequency',
        ),
      ),
      FilledButton(
        onPressed: () => _confirm('Reset readings', store.resetReadings),
        child: const Text('Reset VTM-TEST readings'),
      ),
      FilledButton(
        onPressed: () => _confirm('Reset calibration', store.resetCalibration),
        child: const Text('Reset calibration'),
      ),
      FilledButton(
        onPressed: () =>
            _confirm('Clear certificates', store.clearCertificates),
        child: const Text('Clear demo certificates'),
      ),
    ],
  );

  Future<void> _openCalibration() => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const VtmTestCalibrationScreen()),
  );

  void _issueCertificate() {
    store.issueCertificate();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('VTM-TEST certificate issued.')),
    );
  }

  void _confirm(String title, VoidCallback action) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: const Text('This affects VTM-TEST demo data only.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              action();
              Navigator.pop(context);
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  static String _timeOfDay(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}

/// Calibration entry is intentionally isolated to VTM-TEST in-memory state.
class VtmTestCalibrationScreen extends StatefulWidget {
  const VtmTestCalibrationScreen({super.key});

  @override
  State<VtmTestCalibrationScreen> createState() =>
      _VtmTestCalibrationScreenState();
}

class _VtmTestCalibrationScreenState extends State<VtmTestCalibrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _batteryOneController = TextEditingController();
  final _batteryTwoController = TextEditingController();
  final _temperatureController = TextEditingController();
  final _store = VtmDemoStore.instance;
  bool _submitting = false;

  @override
  void dispose() {
    _batteryOneController.dispose();
    _batteryTwoController.dispose();
    _temperatureController.dispose();
    super.dispose();
  }

  String? _validateOffset(String? value, String label) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Enter $label.';
    final number = double.tryParse(text);
    if (number == null) return 'Enter a valid number.';
    if (number < -2 || number > 2) return 'Enter a value between -2.0 and 2.0.';
    return null;
  }

  Future<void> _completeCalibration() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _submitting = true);
    try {
      _store.completeCalibration(
        batteryOneVoltageOffset: double.parse(
          _batteryOneController.text.trim(),
        ),
        batteryTwoVoltageOffset: double.parse(
          _batteryTwoController.text.trim(),
        ),
        temperatureOffset: double.parse(_temperatureController.text.trim()),
      );
      final completedAt = _store.calibrationCompletedAt!;
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 10),
              Expanded(child: Text('Calibration Successful')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'VTM-TEST calibration was completed successfully. Calibration values have been saved.',
              ),
              const SizedBox(height: 12),
              Text('Completed: ${_formatTimestamp(completedAt)}'),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('VTM-TEST Calibration')),
    body: SafeArea(
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Calibration values',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'Enter the measured offsets before completing calibration.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            _offsetField(
              controller: _batteryOneController,
              label: 'Battery 1 voltage offset (V)',
            ),
            const SizedBox(height: 12),
            _offsetField(
              controller: _batteryTwoController,
              label: 'Battery 2 voltage offset (V)',
            ),
            const SizedBox(height: 12),
            _offsetField(
              controller: _temperatureController,
              label: 'Temperature offset (°C)',
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _submitting ? null : _completeCalibration,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Complete Calibration'),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _offsetField({
    required TextEditingController controller,
    required String label,
  }) => TextFormField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(
      decimal: true,
      signed: true,
    ),
    textInputAction: TextInputAction.next,
    autovalidateMode: AutovalidateMode.onUserInteraction,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
    validator: (value) => _validateOffset(value, label),
  );

  static String _formatTimestamp(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year} '
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}

class _OnlinePill extends StatelessWidget {
  const _OnlinePill();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.green.withValues(alpha: .14),
      borderRadius: BorderRadius.circular(20),
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 8, color: Colors.green),
        SizedBox(width: 5),
        Text(
          'Online',
          style: TextStyle(
            color: Colors.green,
            fontWeight: FontWeight.w700,
            fontSize: 11,
          ),
        ),
      ],
    ),
  );
}

class _VtmChartCard extends StatelessWidget {
  const _VtmChartCard({
    required this.title,
    required this.unit,
    required this.period,
    required this.data,
    required this.height,
    this.summary,
    this.details,
  });

  final String title;
  final String unit;
  final VtmTrendPeriod period;
  final List<List<double>> data;
  final double height;
  final String? summary;
  final String? details;

  static const batteryTwoColor = Color(0xFF8B7CFF);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _Legend(color: theme.colorScheme.primary, label: 'Battery 1'),
                const SizedBox(width: 8),
                const _Legend(color: batteryTwoColor, label: 'Battery 2'),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: height,
              child: _VtmLineChart(
                title: title,
                unit: unit,
                period: period,
                data: data,
                primaryColor: theme.colorScheme.primary,
                secondaryColor: batteryTwoColor,
                labelColor: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (summary != null) ...[
              const SizedBox(height: 7),
              Text(summary!, style: theme.textTheme.bodySmall),
            ],
            if (details != null) ...[
              const SizedBox(height: 8),
              Text(
                details!,
                style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 4),
      Text(label, style: Theme.of(context).textTheme.labelSmall),
    ],
  );
}

class _VtmLineChart extends StatelessWidget {
  const _VtmLineChart({
    required this.title,
    required this.unit,
    required this.period,
    required this.data,
    required this.primaryColor,
    required this.secondaryColor,
    required this.labelColor,
  });

  final String title;
  final String unit;
  final VtmTrendPeriod period;
  final List<List<double>> data;
  final Color primaryColor;
  final Color secondaryColor;
  final Color labelColor;

  List<FlSpot> _spots(List<double> readings) {
    final spots = readings
        .asMap()
        .entries
        .map((entry) => FlSpot(entry.key.toDouble(), entry.value))
        .toList();
    return spots;
  }

  @override
  Widget build(BuildContext context) {
    assert(
      data.length == 2 &&
          data[0].isNotEmpty &&
          data[0].length == data[1].length,
    );
    final firstSpots = _spots(data[0]);
    final secondSpots = _spots(data[1]);
    final all = [...data[0], ...data[1]];
    final actualMin = all.reduce(math.min);
    final actualMax = all.reduce(math.max);
    final range = actualMax - actualMin;
    final padding = math.max(range * .22, unit == 'V' ? .08 : .7);
    final minY = actualMin - padding;
    final maxY = actualMax + padding;
    final maxX = data[0].length - 1.0;
    final yInterval = (maxY - minY) / 3;
    assert(() {
      debugPrint(
        'VTM-TEST $title ${period.label}: '
        'seriesLength=${firstSpots.length}/${secondSpots.length}, '
        'battery1=${firstSpots.first}..${firstSpots.last}, '
        'battery2=${secondSpots.first}..${secondSpots.last}, '
        'actual=$actualMin..$actualMax, chartBounds=x:0..$maxX y:$minY..$maxY',
      );
      return true;
    }());

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: maxX,
        minY: minY,
        maxY: maxY,
        clipData: const FlClipData.all(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: yInterval,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: labelColor.withValues(alpha: .18), strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: unit == '°C' ? 43 : 37,
              interval: yInterval,
              getTitlesWidget: (value, meta) => Text(
                '${value.toStringAsFixed(unit == 'V' ? 1 : 0)} $unit',
                textAlign: TextAlign.right,
                style: TextStyle(color: labelColor, fontSize: 10),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 27,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final index = value.round();
                final middle = data[0].length ~/ 2;
                if (index < 0 ||
                    index >= data[0].length ||
                    (index != 0 &&
                        index != middle &&
                        index != data[0].length - 1)) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(
                    _xLabel(index),
                    style: TextStyle(color: labelColor, fontSize: 10),
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          enabled: true,
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touchedSpots) => touchedSpots
                .map(
                  (spot) => LineTooltipItem(
                    '${spot.barIndex == 0 ? 'Battery 1' : 'Battery 2'}\n${spot.y.toStringAsFixed(unit == 'V' ? 2 : 1)} $unit',
                    TextStyle(
                      color: spot.barIndex == 0 ? primaryColor : secondaryColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: firstSpots,
            isCurved: true,
            color: primaryColor,
            barWidth: 2.6,
            isStrokeCapRound: true,
            dotData: FlDotData(show: firstSpots.length <= 12),
            belowBarData: BarAreaData(show: false),
          ),
          LineChartBarData(
            spots: secondSpots,
            isCurved: true,
            color: secondaryColor,
            barWidth: 2.6,
            isStrokeCapRound: true,
            dotData: FlDotData(show: secondSpots.length <= 12),
            belowBarData: BarAreaData(show: false),
          ),
        ],
      ),
    );
  }

  String _xLabel(int index) {
    final count = data[0].length;
    final remaining = count == 1 ? 0 : (count - 1 - index) / (count - 1);
    final timestamp = DateTime.now().subtract(period.duration * remaining);
    if (period == VtmTrendPeriod.hour) {
      return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    }
    if (period == VtmTrendPeriod.day) {
      return '${timestamp.hour.toString().padLeft(2, '0')}:00';
    }
    return '${timestamp.day}/${timestamp.month}';
  }
}
