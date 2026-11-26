import 'dart:async';

import 'package:flutter/material.dart';

import '../services/vtm_nus_connection.dart';

/// A minimal UART terminal. It deliberately has no Ulink calibration controls.
class VtmTerminalScreen extends StatefulWidget {
  const VtmTerminalScreen({super.key, required this.connection, required this.name});

  final VtmNusConnection connection;
  final String name;

  @override
  State<VtmTerminalScreen> createState() => _VtmTerminalScreenState();
}

class _VtmTerminalScreenState extends State<VtmTerminalScreen> {
  final _input = TextEditingController();
  final _messages = <String>[];
  StreamSubscription<String>? _receivedSubscription;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _receivedSubscription = widget.connection.receivedText.listen((text) {
      if (mounted) setState(() => _messages.add(text));
    });
  }

  Future<void> _send() async {
    final text = _input.text;
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.connection.writeText(text);
      _input.clear();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _receivedSubscription?.cancel();
    _input.dispose();
    widget.connection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('${widget.name} UART')),
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const Text('Connected to Battery Mobile ESP. No Ulink commands are sent automatically.'),
          if (widget.connection.diagnostics.isNotEmpty)
            SelectableText('Diagnostics: ${widget.connection.diagnostics}'),
          const SizedBox(height: 12),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).colorScheme.outline),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _messages.length,
                itemBuilder: (_, index) => SelectableText(_messages[index]),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  enabled: !_sending,
                  onSubmitted: (_) => _send(),
                  decoration: const InputDecoration(labelText: 'Send UART text'),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _sending ? null : _send,
                child: const Text('Send'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
