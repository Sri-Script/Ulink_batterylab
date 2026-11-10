import 'package:flutter/material.dart';

import '../services/ulink_ble_provisioning_client.dart';

class UlinkWifiProvisioningScreen extends StatefulWidget {
  const UlinkWifiProvisioningScreen({super.key, required this.client});
  final UlinkBleProvisioningClient client;

  @override
  State<UlinkWifiProvisioningScreen> createState() => _UlinkWifiProvisioningScreenState();
}

class _UlinkWifiProvisioningScreenState extends State<UlinkWifiProvisioningScreen> {
  final _ssid = TextEditingController();
  final _password = TextEditingController();
  bool _obscurePassword = true;
  bool _sending = false;

  Future<void> _send() async {
    final validation = UlinkProvisioningProtocol.validateCredentials(_ssid.text, _password.text);
    if (validation != null) {
      _message(validation, error: true);
      return;
    }
    setState(() => _sending = true);
    try {
      await widget.client.provision(ssid: _ssid.text, password: _password.text);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary, size: 40),
          title: const Text('Credentials acknowledged'),
          content: Text('Wi-Fi credentials acknowledged by ${widget.client.deviceName}.'),
          actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Continue'))],
        ),
      );
    } catch (error) {
      if (mounted) _message(_clean(error), error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _message(String text, {required bool error}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), backgroundColor: error ? Theme.of(context).colorScheme.error : null));
  }

  String _clean(Object error) => error.toString().replaceFirst(RegExp(r'^(StateError|Exception):\s*'), '');

  @override
  void dispose() {
    _ssid.dispose();
    _password.dispose();
    widget.client.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('U-Link Wi-Fi provisioning')),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Provision ${widget.client.deviceName}. The device must acknowledge the credentials before they are marked successful.', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 20),
            TextField(controller: _ssid, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'SSID')),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: _obscurePassword,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                labelText: 'Password (optional for open network)',
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                ),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _sending ? null : _send,
              icon: _sending ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send),
              label: Text(_sending ? 'Waiting for acknowledgement…' : 'Send credentials'),
            ),
          ],
        ),
      ),
    ),
  );
}
