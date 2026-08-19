import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../config/device_contract.dart';
import '../models/device_descriptor.dart';
import '../providers/connection_controller.dart';
import '../services/wifi_gateway_discovery.dart';
import '../widgets/scan_frame_overlay.dart';
import 'calibration_screen.dart';

enum ScanMode { qr, barcode }

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});
  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  late MobileScannerController _scanner = _newScanner();
  ScanMode _mode = ScanMode.qr;
  bool _handlingScan = false;
  bool _cameraAllowed = false;
  String? _feedback;
  bool _feedbackIsError = false;
  DeviceDescriptor? _validatedBarcode;

  MobileScannerController _newScanner() => MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: _mode == ScanMode.qr
        ? DeviceContract.qrFormats
        : DeviceContract.barcodeFormats,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepare());
  }

  Future<void> _prepare() async {
    final controller = context.read<ConnectionController>();
    await controller.initialize();
    final allowed = await controller.requestCameraPermission();
    if (mounted) setState(() => _cameraAllowed = allowed);
  }

  Future<void> _changeMode(ScanMode mode) async {
    if (mode == _mode || _handlingScan) return;
    final previous = _scanner;
    await previous.stop();
    if (!mounted) return;
    setState(() {
      _mode = mode;
      _scanner = _newScanner();
      _feedback = null;
      _validatedBarcode = null;
    });
    await previous.dispose();
  }

  Future<void> _onCapture(BarcodeCapture capture) async {
    if (_handlingScan || _validatedBarcode != null) return;
    final raw = capture.barcodes.firstOrNull?.rawValue?.trim();
    if (raw == null || raw.isEmpty) {
      _showFeedback(
        "Couldn't recognize that code — try rescanning",
        error: true,
      );
      return;
    }
    try {
      final descriptor = DeviceDescriptor.fromScannedPayload(
        raw,
        barcode: _mode == ScanMode.barcode,
      );
      if (_mode == ScanMode.barcode) {
        await _scanner.stop();
        if (!mounted) return;
        setState(() {
          _validatedBarcode = descriptor;
          _feedback = 'Valid gateway serial: ${descriptor.deviceId}';
          _feedbackIsError = false;
        });
        return;
      }
      await _connect(descriptor);
    } on FormatException {
      _showFeedback(
        "Couldn't recognize that code — try rescanning",
        error: true,
      );
    } catch (_) {
      _showFeedback(
        "Couldn't recognize that code — try rescanning",
        error: true,
      );
    }
  }

  void _showFeedback(String message, {required bool error}) {
    if (!mounted) return;
    setState(() {
      _feedback = message;
      _feedbackIsError = error;
      if (error) _validatedBarcode = null;
    });
  }

  Future<void> _rescanBarcode() async {
    setState(() {
      _validatedBarcode = null;
      _feedback = null;
    });
    await _scanner.start();
  }

  Future<void> _connect(
    DeviceDescriptor descriptor, {
    bool reconnect = false,
  }) async {
    final controller = context.read<ConnectionController>();
    setState(() {
      _handlingScan = true;
      _feedback = null;
    });
    await _scanner.stop();
    final success = await controller.connect(descriptor, reconnect: reconnect);
    if (!mounted) return;
    if (success) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const CalibrationScreen()),
      );
    } else {
      _showFeedback(
        _friendlyConnectionError(controller.errorMessage),
        error: true,
      );
    }
    if (mounted) {
      setState(() {
        _handlingScan = false;
        _validatedBarcode = null;
      });
      if (_cameraAllowed) await _scanner.start();
    }
  }

  String _friendlyConnectionError(String? message) {
    if (message?.contains('permission') ?? false) {
      return 'Bluetooth permission is required to connect to this gateway.';
    }
    if (message?.contains('not found') ?? false) {
      return 'That gateway was not found nearby. Try again.';
    }
    if (message?.contains('does not match') ?? false) {
      return 'The gateway found on Wi-Fi does not match the scanned device.';
    }
    return 'Could not connect to that gateway. Please try again.';
  }

  Future<void> _wifiDiscovery() async {
    await _scanner.stop();
    if (!mounted) return;
    final result = await showModalBottomSheet<DeviceDescriptor>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _WifiDiscoverySheet(),
    );
    if (!mounted) return;
    if (result != null) {
      await _connect(result);
    } else if (_cameraAllowed) {
      await _scanner.start();
    }
  }

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ConnectionController>();
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Connect Ulink Gateway',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SegmentedButton<ScanMode>(
                    segments: const [
                      ButtonSegment(
                        value: ScanMode.qr,
                        icon: Icon(Icons.qr_code_scanner),
                        label: Text('Scan QR Code'),
                      ),
                      ButtonSegment(
                        value: ScanMode.barcode,
                        icon: Icon(Icons.view_week),
                        label: Text('Scan Barcode'),
                      ),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (value) => _changeMode(value.first),
                  ),
                  if (controller.lastDevice case final last?) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _handlingScan
                          ? null
                          : () => _connect(last, reconnect: true),
                      icon: const Icon(Icons.link),
                      label: Text('Reconnect to ${last.deviceId}'),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = math.min(
                    270.0,
                    math.min(
                      constraints.maxWidth - 32,
                      constraints.maxHeight - 32,
                    ),
                  );
                  final scanWindow = Rect.fromCenter(
                    center: Offset(
                      constraints.maxWidth / 2,
                      constraints.maxHeight / 2,
                    ),
                    width: size,
                    height: size,
                  );
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_cameraAllowed)
                        MobileScanner(
                          key: ValueKey(_mode),
                          controller: _scanner,
                          scanWindow: scanWindow,
                          onDetect: _onCapture,
                          errorBuilder: (_, _) => const _PermissionMessage(
                            message:
                                'Camera is unavailable. Check camera access and try again.',
                          ),
                        )
                      else
                        const _PermissionMessage(
                          message:
                              'Camera permission denied. Allow camera access in Settings to scan a gateway.',
                        ),
                      if (_cameraAllowed) ScanFrameOverlay(size: size),
                      Positioned(
                        left: 24,
                        right: 24,
                        bottom: 20,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.surface.withValues(alpha: .92),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _mode == ScanMode.qr
                                ? 'Place one Ulink QR code inside the frame'
                                : 'Place the Code 128 serial inside the frame',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                      if (_handlingScan)
                        const ColoredBox(
                          color: Color(0x99000000),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                    ],
                  );
                },
              ),
            ),
            if (_feedback case final feedback?)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _feedbackIsError ? Icons.error : Icons.verified,
                      color: _feedbackIsError
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        feedback,
                        style: TextStyle(
                          color: _feedbackIsError
                              ? Theme.of(context).colorScheme.error
                              : Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_validatedBarcode case final validated?) ...[
                    FilledButton.icon(
                      onPressed: () => _connect(validated),
                      icon: const Icon(Icons.bluetooth_searching),
                      label: const Text('Connect to this gateway'),
                    ),
                    TextButton(
                      onPressed: _rescanBarcode,
                      child: const Text('Scan a different barcode'),
                    ),
                  ] else
                    OutlinedButton.icon(
                      onPressed: _handlingScan ? null : _wifiDiscovery,
                      icon: const Icon(Icons.wifi_find),
                      label: const Text('Discover via Wi-Fi instead'),
                    ),
                  if (AppConfig.demoMode) ...[
                    const SizedBox(height: 6),
                    TextButton.icon(
                      onPressed: _handlingScan
                          ? null
                          : () => _connect(
                              DeviceDescriptor.fromScannedPayload(
                                DeviceContract.testStatusPayload['deviceId']!
                                    as String,
                                barcode: false,
                              ),
                            ),
                      icon: const Icon(Icons.science),
                      label: const Text('Use demo gateway'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WifiDiscoverySheet extends StatefulWidget {
  const _WifiDiscoverySheet();
  @override
  State<_WifiDiscoverySheet> createState() => _WifiDiscoverySheetState();
}

class _WifiDiscoverySheetState extends State<_WifiDiscoverySheet> {
  late Future<List<DiscoveredGateway>> _results = WifiGatewayDiscovery()
      .discover();
  final _deviceId = TextEditingController();
  final _ip = TextEditingController();
  final _port = TextEditingController(text: '80');

  void _retry() => setState(() => _results = WifiGatewayDiscovery().discover());

  void _manualConnect() {
    final id = _deviceId.text.trim().toUpperCase();
    final ip = _ip.text.trim();
    final port = int.tryParse(_port.text.trim());
    if (!DeviceContract.deviceIdPattern.hasMatch(id) ||
        !DeviceDescriptor.isValidIpv4(ip) ||
        port == null ||
        port < 1 ||
        port > 65535) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid gateway ID, IP address, and port.'),
        ),
      );
      return;
    }
    Navigator.pop(
      context,
      DeviceDescriptor(
        mode: TransportType.wifi,
        deviceId: id,
        gatewayId: id,
        ip: ip,
        port: port,
      ),
    );
  }

  @override
  void dispose() {
    _deviceId.dispose();
    _ip.dispose();
    _port.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Ulink gateways on Wi-Fi',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            const Text(
              'Searching the local network with mDNS (_ulink._tcp.local).',
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<DiscoveredGateway>>(
              future: _results,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final gateways = snapshot.data ?? [];
                if (gateways.isEmpty) {
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.wifi_off),
                      title: const Text('No advertised gateways found'),
                      subtitle: const Text(
                        'Use manual connection below or scan again.',
                      ),
                      trailing: IconButton(
                        onPressed: _retry,
                        icon: const Icon(Icons.refresh),
                        tooltip: 'Search again',
                      ),
                    ),
                  );
                }
                return Column(
                  children: gateways
                      .map(
                        (gateway) => Card(
                          child: ListTile(
                            leading: const Icon(Icons.router),
                            title: Text(gateway.descriptor.deviceId),
                            subtitle: Text(
                              '${gateway.descriptor.ip}:${gateway.descriptor.port} • ${gateway.batteryCount ?? '?'} batteries',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () =>
                                Navigator.pop(context, gateway.descriptor),
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
            const SizedBox(height: 18),
            Text(
              'Manual fallback',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _deviceId,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Gateway ID',
                hintText: 'ULINK-GW-TEST01',
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ip,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'IP address',
                      hintText: '192.168.1.42',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 90,
                  child: TextField(
                    controller: _port,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Port'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _manualConnect,
              child: const Text('Connect manually'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _PermissionMessage extends StatelessWidget {
  const _PermissionMessage({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surface,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography, size: 50),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    ),
  );
}
