import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ulink_batterylab/models/calibration_log_entry.dart';
import 'package:ulink_batterylab/services/calibration_certificate_pdf.dart';

void main() {
  test('generates a PDF when the stored calibration response lacks a reference voltage', () async {
    final record = CalibrationLogEntry(
      id: 1,
      deviceId: 'BATTERY-001',
      action: 'volt',
      value: jsonEncode({
        'detected_volt': 3.712,
        'volt_factor': 0.998,
      }),
      timestamp: DateTime.utc(2026, 9, 3, 12, 30),
      direction: 'command',
      status: 'success',
    );
    final signature = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL2kQAAAABJRU5ErkJggg==',
    );

    final bytes = await generateCalibrationCertificatePdf(
      record: record,
      nodeRole: 'MASTER',
      signerName: 'Test Signer',
      signaturePng: signature,
      signedAt: DateTime.utc(2026, 9, 3, 13),
    );

    expect(utf8.decode(bytes.take(4).toList()), '%PDF');
  });
}
