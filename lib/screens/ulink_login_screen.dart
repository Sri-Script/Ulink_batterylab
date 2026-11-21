import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../services/provisioning_repository.dart';
import '../services/si_access_repository.dart';
import '../services/ulink_login_preferences.dart';
import 'si_company_selection_screen.dart';
import 'ulink_device_picker_screen.dart';

/// Test seam for exercising post-login routing without a live Firebase user.
class UlinkLoginSession {
  const UlinkLoginSession({required this.uid, required this.resolveSiRole});

  final String uid;
  final Future<bool> Function() resolveSiRole;
}

class UlinkLoginScreen extends StatefulWidget {
  const UlinkLoginScreen({
    super.key,
    this.signIn,
    this.isSystemIntegrator,
    this.loginSession,
    this.siProvisioningRepository,
    this.loginPreferences,
  });

  final Future<UserCredential> Function(String email, String password)? signIn;
  final Future<bool> Function(User user)? isSystemIntegrator;
  final Future<UlinkLoginSession> Function(String email, String password)?
  loginSession;
  final ProvisioningRepository? siProvisioningRepository;
  final UlinkLoginPreferences? loginPreferences;

  @override
  State<UlinkLoginScreen> createState() => _UlinkLoginScreenState();
}

class _UlinkLoginScreenState extends State<UlinkLoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscurePassword = true;
  bool _submitting = false;
  late final UlinkLoginPreferences _loginPreferences =
      widget.loginPreferences ?? SharedPreferencesUlinkLoginPreferences();

  @override
  void initState() {
    super.initState();
    _restoreEmail();
  }

  Future<void> _restoreEmail() async {
    try {
      final email = await _loginPreferences.readEmail();
      if (mounted && email != null) {
        setState(() => _email.text = email);
      }
    } catch (_) {
      // Remembering an email is optional and must never block sign-in.
    }
  }

  Future<void> _submit() async {
    final email = _email.text.trim().toLowerCase();
    if (email.isEmpty || _password.text.isEmpty) {
      _message('Enter an email address and password.', error: true);
      return;
    }
    setState(() => _submitting = true);
    try {
      late final String uid;
      late final bool isSi;
      if (widget.loginSession != null) {
        final session = await widget.loginSession!(email, _password.text);
        uid = session.uid;
        isSi = await session.resolveSiRole();
      } else {
        late final UserCredential credential;
        if (widget.signIn != null) {
          credential = await widget.signIn!(email, _password.text);
        } else {
          if (Firebase.apps.isEmpty) await Firebase.initializeApp();
          credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
            email: email,
            password: _password.text,
          );
        }
        final user = credential.user;
        if (user == null) throw FirebaseAuthException(code: 'no-user');
        uid = user.uid;
        isSi = widget.isSystemIntegrator != null
            ? await widget.isSystemIntegrator!(user)
            : await SiAccessRepository().isSystemIntegrator(user);
      }
      try {
        await _loginPreferences.saveEmail(email);
      } catch (_) {
        // A local preference failure must not discard a valid Firebase login.
      }
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => isSi
              ? SiCompanySelectionScreen(
                  siUid: uid,
                  repository: widget.siProvisioningRepository,
                  loginPreferences: _loginPreferences,
                )
              : UlinkDevicePickerScreen(loginPreferences: _loginPreferences),
        ),
      );
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        _message(
          error.message ?? 'Authentication failed. Please try again.',
          error: true,
        );
      }
    } on SiRoleLookupException catch (_) {
      if (mounted) {
        _message(
          'We could not verify your System Integrator access. Check your Firebase permissions and try again.',
          error: true,
        );
      }
    } catch (_) {
      if (mounted) {
        _message(
          'Firebase authentication is unavailable. Check the app setup and try again.',
          error: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
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
            Text(
              'Sign in to provision a U-Link device.',
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
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
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
              child: Text(_submitting ? 'Signing in...' : 'Sign in'),
            ),
          ],
        ),
      ),
    ),
  );
}
