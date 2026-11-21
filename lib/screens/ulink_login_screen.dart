import 'package:flutter/material.dart';

import '../services/ulink_api_repository.dart';
import '../services/ulink_login_preferences.dart';
import 'api_ulink_dashboard_screen.dart';

class UlinkLoginScreen extends StatefulWidget {
  const UlinkLoginScreen({super.key, this.repository, this.loginPreferences});
  final UlinkApiRepository? repository;
  final UlinkLoginPreferences? loginPreferences;
  @override
  State<UlinkLoginScreen> createState() => _UlinkLoginScreenState();
}

class _UlinkLoginScreenState extends State<UlinkLoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _obscurePassword = true;
  bool _submitting = false;
  late final UlinkApiRepository _repository = widget.repository ?? UlinkApiRepository();
  late final UlinkLoginPreferences _preferences = widget.loginPreferences ?? SharedPreferencesUlinkLoginPreferences();

  @override
  void initState() { super.initState(); _restoreUsername(); }
  Future<void> _restoreUsername() async { try { final username = await _preferences.readUsername(); if (mounted && username != null) setState(() => _username.text = username); } catch (_) {} }

  Future<void> _submit() async {
    final username = _username.text.trim();
    final password = _password.text;
    if (username.isEmpty || password.isEmpty) { _message('Enter a username and password.'); return; }
    setState(() => _submitting = true);
    try {
      final login = await _repository.login(username: username, password: password);
      try { await _preferences.saveUsername(username); } catch (_) {}
      if (!mounted) return;
      final destination = login.session.userRole == 'SI'
          ? ApiSiDashboardScreen(login: login, repository: _repository, loginPreferences: _preferences)
          : ApiCompanyAdminDashboardScreen(login: login, repository: _repository, loginPreferences: _preferences);
      await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => destination));
    } on UlinkApiException catch (error) {
      if (mounted) _message(_userMessage(error));
    } on FormatException {
      if (mounted) _message('The service returned an invalid session. Please sign in again.');
    } catch (_) {
      if (mounted) _message('The service is unavailable. Please try again.');
    } finally { if (mounted) setState(() => _submitting = false); }
  }
  String _userMessage(UlinkApiException error) => switch (error.statusCode) { 401 || 403 => 'Invalid username or password.', 429 => 'Too many attempts. Please wait and try again.', _ => error.message };
  void _message(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), backgroundColor: Theme.of(context).colorScheme.error));
  @override void dispose() { _username.dispose(); _password.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('U-Link sign in')),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Sign in to view your U-Link hierarchy.', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 20),
            TextField(controller: _username, autocorrect: false, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'Username')),
            const SizedBox(height: 12),
            TextField(controller: _password, obscureText: _obscurePassword, onSubmitted: (_) => _submit(), decoration: InputDecoration(labelText: 'Password', suffixIcon: IconButton(onPressed: () => setState(() => _obscurePassword = !_obscurePassword), icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off), tooltip: _obscurePassword ? 'Show password' : 'Hide password'))),
            const SizedBox(height: 20),
            FilledButton(onPressed: _submitting ? null : _submit, child: Text(_submitting ? 'Signing in...' : 'Sign in')),
          ],
        ),
      ),
    ),
  );
}
