import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'live_data_viewer_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _createAccount = false;
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
      if (_createAccount) {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: _password.text,
        );
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: _password.text,
        );
      }
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const LiveDataViewerScreen()),
      );
    } on FirebaseAuthException catch (error) {
      if (mounted) _message(error.message ?? 'Authentication failed.', error: true);
    } catch (_) {
      if (mounted) {
        _message('Firebase authentication is unavailable. Check the app setup.', error: true);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
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

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_createAccount ? 'Create account' : 'Login')),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _createAccount
                  ? 'Create an account to view live device data.'
                  : 'Sign in to view live device data.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
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
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: Text(
                _submitting
                    ? 'Please wait...'
                    : _createAccount
                    ? 'Create account'
                    : 'Login',
              ),
            ),
            TextButton(
              onPressed: _submitting
                  ? null
                  : () => setState(() => _createAccount = !_createAccount),
              child: Text(
                _createAccount
                    ? 'Already have an account? Login'
                    : 'Create account',
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
