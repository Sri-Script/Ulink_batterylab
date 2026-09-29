import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../config/device_contract.dart';
import '../models/calibration_log_entry.dart';
import '../providers/connection_controller.dart';
import '../services/calibration_certificate_pdf.dart';
import '../widgets/signature_capture_dialog.dart';

class CalibrationHistoryScreen extends StatefulWidget {
  const CalibrationHistoryScreen({super.key});

  @override
  State<CalibrationHistoryScreen> createState() => _CalibrationHistoryScreenState();
}

class _CalibrationHistoryScreenState extends State<CalibrationHistoryScreen> {
  String? _signerName;
  Uint8List? _signaturePng;
  int? _exportingId;

  Future<void> _export(CalibrationLogEntry entry) async {
    final signerName = await _ensureSignerName();
    if (signerName == null || !mounted) return;
    _signaturePng ??= await showSignatureCaptureDialog(context);
    if (_signaturePng == null || !mounted) return;

    setState(() => _exportingId = entry.id);
    try {
      final controller = context.read<ConnectionController>();
      final bytes = await generateCalibrationCertificatePdf(
        record: entry,
        nodeRole: controller.deviceRole,
        signerName: signerName,
        signaturePng: _signaturePng!,
      );
      final serial = entry.deviceId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      final date = DeviceContract.deviceTimestamp(entry.timestamp)
          .substring(0, 10)
          .replaceAll('-', '');
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'Calibration_${serial}_$date.pdf',
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not generate certificate: $error')),
      );
    } finally {
      if (mounted) setState(() => _exportingId = null);
    }
  }

  Future<String?> _ensureSignerName() async {
    if (_signerName != null && _signerName!.isNotEmpty) return _signerName;
    final input = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Signer name'),
        content: TextField(
          controller: input,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Printed name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final value = input.text.trim();
              if (value.isNotEmpty) Navigator.pop(dialogContext, value);
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    input.dispose();
    if (name != null) _signerName = name;
    return name;
  }

  @override
  Widget build(BuildContext context) {
    final history = context.read<ConnectionController>().history();
    return Scaffold(
      appBar: AppBar(title: const Text('Calibration History')),
      body: FutureBuilder<List<CalibrationLogEntry>>(
        future: history,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final entries = (snapshot.data ?? const <CalibrationLogEntry>[])
              .where(_isVoltageCalibration)
              .toList();
          if (entries.isEmpty) {
            return const Center(child: Text('No calibration history for this device.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: entries.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final entry = entries[index];
              final exporting = _exportingId == entry.id;
              return ListTile(
                title: Text(entry.action),
                subtitle: Text('${DeviceContract.deviceTimestamp(entry.timestamp)}\n${entry.status}'),
                isThreeLine: true,
                trailing: IconButton(
                  onPressed: exporting ? null : () => _export(entry),
                  icon: exporting
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.picture_as_pdf),
                  tooltip: 'Download Certificate',
                ),
              );
            },
          );
        },
      ),
    );
  }

  bool _isVoltageCalibration(CalibrationLogEntry entry) {
    final action = entry.action.toUpperCase();
    return action == 'VOLT' ||
        action == 'VOLTAGE' ||
        action.startsWith('CAL_VOLT');
  }
}
