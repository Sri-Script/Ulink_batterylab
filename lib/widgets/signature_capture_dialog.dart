import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:signature/signature.dart';

Future<Uint8List?> showSignatureCaptureDialog(BuildContext context) => showDialog<Uint8List>(
  context: context,
  builder: (_) => const _SignatureCaptureDialog(),
);

class _SignatureCaptureDialog extends StatefulWidget {
  const _SignatureCaptureDialog();

  @override
  State<_SignatureCaptureDialog> createState() => _SignatureCaptureDialogState();
}

class _SignatureCaptureDialogState extends State<_SignatureCaptureDialog> {
  late final SignatureController _controller = SignatureController(
    penStrokeWidth: 3,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
    onDrawEnd: () {
      if (mounted) setState(() {});
    },
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_controller.isEmpty) return;
    final png = await _controller.toPngBytes();
    if (!mounted || png == null) return;
    Navigator.pop(context, png);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Signature'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 180,
            decoration: BoxDecoration(border: Border.all(color: Theme.of(context).colorScheme.outline)),
            child: Signature(
              controller: _controller,
              backgroundColor: Colors.white,
            ),
          ),
          Row(
            children: [
              TextButton.icon(onPressed: _controller.isEmpty ? null : () => setState(_controller.undo), icon: const Icon(Icons.undo), label: const Text('Undo')),
              TextButton.icon(onPressed: _controller.isEmpty ? null : () => setState(_controller.clear), icon: const Icon(Icons.clear), label: const Text('Clear')),
            ],
          ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: _controller.isEmpty ? null : _save, child: const Text('Use signature')),
    ],
  );
}
