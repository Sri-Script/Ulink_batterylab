import 'dart:async';

import 'package:flutter/material.dart';

import '../services/ulink_ble_provisioning_client.dart';

class UlinkWifiProvisioningScreen extends StatefulWidget {
  const UlinkWifiProvisioningScreen({super.key, required this.client});
  final UlinkSettingsClient client;

  @override
  State<UlinkWifiProvisioningScreen> createState() =>
      _UlinkWifiProvisioningScreenState();
}

class _UlinkWifiProvisioningScreenState
    extends State<UlinkWifiProvisioningScreen> {
  final _ssid = TextEditingController();
  final _password = TextEditingController();
  final _apn = TextEditingController();
  final _ssidFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _apnFocus = FocusNode();
  final Map<UlinkSettingsKey, String> _saved = <UlinkSettingsKey, String>{};
  final Map<UlinkSettingsKey, String> _status = <UlinkSettingsKey, String>{};
  StreamSubscription<UlinkProtocolEvent>? _eventsSubscription;
  Timer? _initialSettingsTimer;
  String _mode = 'WIFI';
  bool _obscurePassword = true;
  bool _loaded = false;
  bool _refreshing = false;
  bool _confirming = false;
  UlinkSettingsKey? _saving;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _eventsSubscription = widget.client.events.listen(_onEvent);
    _applyInitialSettings(widget.client.latestSettings);
    _initialSettingsTimer = Timer(const Duration(seconds: 15), () {
      if (mounted && !_loaded) {
        setState(() {
          _loadError = 'U-Link did not send settings. Try Refresh / Get All.';
        });
      }
    });
  }

  void _onEvent(UlinkProtocolEvent event) {
    if (event is UlinkSettingsEvent && !_loaded) {
      _applyInitialSettings(event.settings);
    }
  }

  void _applyInitialSettings(UlinkSettings? settings) {
    if (settings == null || _loaded) return;
    _applySettings(settings);
    if (mounted) {
      setState(() {
        _loaded = true;
        _loadError = null;
      });
    } else {
      _loaded = true;
    }
    _initialSettingsTimer?.cancel();
  }

  void _applySettings(
    UlinkSettings settings, {
    Set<UlinkSettingsKey> skip = const {},
  }) {
    for (final key in UlinkSettingsKey.values) {
      if (skip.contains(key)) continue;
      final value = settings.valueFor(key);
      _saved[key] = value;
      _status[key] = 'Saved on U-Link';
      switch (key) {
        case UlinkSettingsKey.ssid:
          _ssid.text = value;
        case UlinkSettingsKey.password:
          _password.text = value;
        case UlinkSettingsKey.apn:
          _apn.text = value;
        case UlinkSettingsKey.mode:
          _mode = value;
      }
    }
  }

  TextEditingController _controllerFor(UlinkSettingsKey key) => switch (key) {
    UlinkSettingsKey.ssid => _ssid,
    UlinkSettingsKey.password => _password,
    UlinkSettingsKey.apn => _apn,
    UlinkSettingsKey.mode => throw ArgumentError(
      'Mode has no text controller.',
    ),
  };

  FocusNode? _focusFor(UlinkSettingsKey key) => switch (key) {
    UlinkSettingsKey.ssid => _ssidFocus,
    UlinkSettingsKey.password => _passwordFocus,
    UlinkSettingsKey.apn => _apnFocus,
    UlinkSettingsKey.mode => null,
  };

  String _valueFor(UlinkSettingsKey key) =>
      key == UlinkSettingsKey.mode ? _mode : _controllerFor(key).text;

  bool _hasUnsavedChanges(UlinkSettingsKey key) =>
      _saved[key] != _valueFor(key);

  bool _isProtected(UlinkSettingsKey key) =>
      _hasUnsavedChanges(key) || (_focusFor(key)?.hasFocus ?? false);

  Future<void> _refresh() async {
    if (_refreshing || _saving != null) return;
    setState(() => _refreshing = true);
    try {
      final settings = await widget.client.refreshSettings();
      if (!mounted) return;
      final protected = UlinkSettingsKey.values.where(_isProtected).toSet();
      if (protected.isEmpty) {
        setState(() => _applySettings(settings));
      } else {
        final replace = await _confirmReplace();
        if (!mounted) return;
        setState(
          () => _applySettings(settings, skip: replace ? const {} : protected),
        );
      }
      if (!_loaded) {
        _initialSettingsTimer?.cancel();
        setState(() {
          _loaded = true;
          _loadError = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _loadError = 'Could not refresh U-Link settings. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<bool> _confirmReplace() async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Replace unsaved changes?'),
          content: const Text(
            'Some fields are being edited or contain unsaved changes. Replace them with the settings currently stored on U-Link?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep my changes'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Replace'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _requestSave(UlinkSettingsKey key) async {
    if (!_loaded || _saving != null || _refreshing || _confirming) return;
    final value = _valueFor(key);
    final validation = UlinkSettingsProtocol.validate(key, value);
    if (validation != null) {
      setState(() => _status[key] = validation);
      return;
    }
    setState(() => _confirming = true);
    final confirmed = await _confirmSave(key, value);
    if (!mounted) return;
    setState(() => _confirming = false);
    if (confirmed) await _save(key);
  }

  Future<bool> _confirmSave(UlinkSettingsKey key, String value) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('CONFIRM?'),
          content: Text(_confirmationMessage(key, value)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Set'),
            ),
          ],
        ),
      ) ??
      false;

  String _confirmationMessage(UlinkSettingsKey key, String value) {
    final fieldName = switch (key) {
      UlinkSettingsKey.ssid => 'Wi-Fi SSID',
      UlinkSettingsKey.password => 'Wi-Fi password',
      UlinkSettingsKey.apn => 'APN',
      UlinkSettingsKey.mode => 'mode',
    };
    final message = 'Send this updated $fieldName to the connected U-Link?';
    if (key == UlinkSettingsKey.password) {
      return '$message\n\nThe Wi-Fi password will be updated.';
    }
    return '$message\n\nNew value: $value';
  }

  Future<void> _save(UlinkSettingsKey key) async {
    if (!_loaded || _saving != null || _refreshing) return;
    final value = _valueFor(key);
    setState(() {
      _saving = key;
      _status[key] = 'Saving...';
    });
    try {
      await widget.client.saveSetting(key, value);
      if (!mounted) return;
      setState(() {
        _saved[key] = value;
        _status[key] = 'Saved on U-Link';
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _status[key] = key == UlinkSettingsKey.password
              ? 'Password was not saved. Try again.'
              : '${key.wireName.toUpperCase()} was not saved. Try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }

  @override
  void dispose() {
    _initialSettingsTimer?.cancel();
    _eventsSubscription?.cancel();
    _ssid.dispose();
    _password.dispose();
    _apn.dispose();
    _ssidFocus.dispose();
    _passwordFocus.dispose();
    _apnFocus.dispose();
    widget.client.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('U-Link Settings')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Connected to ${widget.client.deviceName}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (!_loaded) const LinearProgressIndicator(),
          if (!_loaded) const SizedBox(height: 8),
          if (!_loaded) Text(_loadError ?? 'Loading settings from U-Link...'),
          if (_loadError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _loadError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _refreshing || _saving != null ? null : _refresh,
            icon: _refreshing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            label: Text(_refreshing ? 'Refreshing...' : 'Refresh / Get All'),
          ),
          const SizedBox(height: 20),
          _textSetting(
            UlinkSettingsKey.ssid,
            'Wi-Fi SSID',
            _ssid,
            _ssidFocus,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),
          _textSetting(
            UlinkSettingsKey.password,
            'Wi-Fi password',
            _password,
            _passwordFocus,
            obscureText: _obscurePassword,
            suffixIcon: IconButton(
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
              icon: Icon(
                _obscurePassword ? Icons.visibility : Icons.visibility_off,
              ),
              tooltip: _obscurePassword ? 'Show password' : 'Hide password',
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),
          _textSetting(UlinkSettingsKey.apn, 'APN', _apn, _apnFocus),
          const SizedBox(height: 16),
          _modeSetting(),
        ],
      ),
    ),
  );

  Widget _textSetting(
    UlinkSettingsKey key,
    String label,
    TextEditingController controller,
    FocusNode focus, {
    bool obscureText = false,
    Widget? suffixIcon,
    TextInputAction? textInputAction,
  }) => _settingRow(
    key,
    TextField(
      controller: controller,
      focusNode: focus,
      obscureText: obscureText,
      textInputAction: textInputAction,
      onChanged: (_) => setState(() => _status[key] = 'Unsaved changes'),
      decoration: InputDecoration(labelText: label, suffixIcon: suffixIcon),
    ),
  );

  Widget _modeSetting() => _settingRow(
    UlinkSettingsKey.mode,
    DropdownButtonFormField<String>(
      key: ValueKey<String>(_mode),
      initialValue: _mode,
      decoration: const InputDecoration(labelText: 'Mode'),
      items: const [
        DropdownMenuItem(value: 'WIFI', child: Text('WIFI')),
        DropdownMenuItem(value: 'GSM', child: Text('GSM')),
      ],
      onChanged: _loaded
          ? (value) {
              if (value != null) {
                setState(() {
                  _mode = value;
                  _status[UlinkSettingsKey.mode] = 'Unsaved changes';
                });
              }
            }
          : null,
    ),
  );

  Widget _settingRow(UlinkSettingsKey key, Widget input) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      input,
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: Text(
              _status[key] ?? '',
              style: TextStyle(
                color:
                    (_status[key] ?? '').contains('not saved') ||
                        (_status[key] ?? '').contains('must') ||
                        (_status[key] ?? '').contains('unsupported')
                    ? Theme.of(context).colorScheme.error
                    : null,
              ),
            ),
          ),
          FilledButton(
            onPressed: !_loaded || _saving != null || _refreshing || _confirming
                ? null
                : () => _requestSave(key),
            child: Text(_saving == key ? 'Saving...' : 'Set'),
          ),
        ],
      ),
    ],
  );
}
