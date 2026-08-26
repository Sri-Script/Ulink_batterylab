import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/connection_controller.dart';

class WifiProvisioningScreen extends StatefulWidget {
  const WifiProvisioningScreen({super.key});

  @override
  State<WifiProvisioningScreen> createState() => _WifiProvisioningScreenState();
}

class _WifiProvisioningScreenState extends State<WifiProvisioningScreen> {
  final _ssid = TextEditingController();
  final _password = TextEditingController();
  bool _obscurePassword = true;
  bool _sending = false;

  Future<void> _send() async {
    final ssid = _ssid.text.trim();
    if (ssid.isEmpty) {
      _message('Enter a Wi-Fi network name.', error: true);
      return;
    }
    setState(() => _sending = true);
    try {
      // TODO(security): Wi-Fi credentials are sent as plaintext JSON over BLE;
      // replace this placeholder protocol when firmware supports secure provisioning.
      final success = await context.read<ConnectionController>().write(
        'wifi_credentials',
        jsonEncode({'ssid': ssid, 'password': _password.text}),
      );
      if (!mounted) return;
      if (!success) throw StateError('The gateway rejected the credentials.');
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: Icon(
            Icons.check_circle,
            color: Theme.of(context).colorScheme.primary,
            size: 40,
          ),
          title: const Text('Sent successfully'),
          content: const Text('Wi-Fi credentials were sent to the gateway.'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) _message(_clean(error), error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _message(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  String _clean(Object error) =>
      error.toString().replaceFirst(RegExp(r'^(StateError|Exception):\s*'), '');

  @override
  void dispose() {
    _ssid.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Wi-Fi Provisioning')),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Send Wi-Fi credentials to the connected gateway.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _ssid,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'SSID'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: _obscurePassword,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                labelText: 'Password',
                suffixIcon: IconButton(
                  onPressed: () => setState(
                    () => _obscurePassword = !_obscurePassword,
                  ),
                  icon: Icon(
                    _obscurePassword ? Icons.visibility : Icons.visibility_off,
                  ),
                  tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                ),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              label: Text(_sending ? 'Sending...' : 'Send Credentials'),
            ),
          ],
        ),
      ),
    ),
  );
}
