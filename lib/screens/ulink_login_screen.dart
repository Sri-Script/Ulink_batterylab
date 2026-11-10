import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'ulink_device_picker_screen.dart';

class UlinkLoginScreen extends StatefulWidget {
  const UlinkLoginScreen({super.key, this.signIn});

  final Future<UserCredential> Function(String email, String password)? signIn;

  @override
  State<UlinkLoginScreen> createState() => _UlinkLoginScreenState();
}

class _UlinkLoginScreenState extends State<UlinkLoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscurePassword = true;
  bool _submitting = false;

  Future<void> _submit() async {
    final email = _email.text.trim();
    if (email.isEmpty || _password.text.isEmpty) {
      _message('Enter an email address and password.', error: true);
      return;
    }
    setState(() => _submitting = true);
    try {
      if (widget.signIn != null) {
        await widget.signIn!(email, _password.text);
      } else {
        if (Firebase.apps.isEmpty) await Firebase.initializeApp();
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: _password.text,
        );
      }
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const UlinkDevicePickerScreen()),
      );
    } on FirebaseAuthException catch (error) {
      if (mounted) _message(error.message ?? 'Authentication failed. Please try again.', error: true);
    } catch (_) {
      if (mounted) {
        _message('Firebase authentication is unavailable. Check the app setup and try again.', error: true);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _message(String text, {required bool error}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('U-Link sign in')),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Sign in to provision a U-Link device.', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 20),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: _obscurePassword,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Password',
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                  tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                ),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: Text(_submitting ? 'Signing in...' : 'Sign in'),
            ),
          ],
        ),
      ),
    ),
  );
}
