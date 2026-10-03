import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';

import '../models/ulink_emulator/ulink_emulator_models.dart';
import '../services/ulink_emulator_service.dart';

class EmulateUlinkScreen extends StatefulWidget {
  const EmulateUlinkScreen({super.key, this.service});

  final UlinkEmulatorService? service;

  @override
  State<EmulateUlinkScreen> createState() => _EmulateUlinkScreenState();
}

class _EmulateUlinkScreenState extends State<EmulateUlinkScreen> {
  late final UlinkEmulatorService _service;
  final _random = Random();
  final _uCodeController = TextEditingController();
  final _uidController = TextEditingController();
  final Map<String, TextEditingController> _valueControllers = {};

  Timer? _emulationTimer;
  UlinkSettingsResponse? _settings;
  UlinkPostRecordResponse? _lastPostResponse;
  String _token = '';
  String? _error;
  String? _requestJson;
  String? _responseJson;
  bool _isFetching = false;
  bool _isSending = false;
  bool _autoRandomize = false;
  bool _continuous = false;
  bool _relayState1 = false;
  bool _relayState2 = false;
  final List<bool> _inputStatuses = List<bool>.filled(4, false);

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? UlinkEmulatorService();
  }

  @override
  void dispose() {
    _emulationTimer?.cancel();
    _service.dispose();
    _uCodeController.dispose();
    _uidController.dispose();
    for (final controller in _valueControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _fetchSettings() async {
    final uCode = _uCodeController.text.trim();
    if (uCode.isEmpty) {
      setState(() => _error = 'Enter a UCode before fetching settings.');
      return;
    }
    setState(() {
      _isFetching = true;
      _error = null;
      _settings = null;
      _lastPostResponse = null;
    });
    try {
      final urlResponse = await _service.getUrl();
      if (urlResponse.result != 1) {
        throw UlinkApiException(urlResponse.message);
      }
      final settings = await _service.getUlinkSettings(uCode);
      if (settings.result != 1) {
        throw UlinkApiException(settings.message);
      }
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _token = settings.token;
        _createValueFields(settings);
      });
      if (_continuous) _restartEmulationTimer();
    } catch (error) {
      if (mounted) setState(() => _error = _errorMessage(error));
    } finally {
      if (mounted) setState(() => _isFetching = false);
    }
  }

  void _createValueFields(UlinkSettingsResponse settings) {
    for (final controller in _valueControllers.values) {
      controller.dispose();
    }
    _valueControllers.clear();
    for (final device in settings.devices) {
      for (final parameter in device.deviceParameters) {
        _valueControllers[_parameterKey(device, parameter)] =
            TextEditingController(text: _newRandomValue().toStringAsFixed(2));
      }
    }
  }

  Future<void> _sendNow() async {
    if (_isSending) return;
    final settings = _settings;
    if (settings == null) {
      setState(() => _error = 'Fetch Ulink settings before sending a record.');
      return;
    }
    final uid = int.tryParse(_uidController.text.trim());
    if (uid == null) {
      setState(() => _error = 'Enter a valid numeric UID before sending a record.');
      return;
    }
    if (_autoRandomize) _randomWalkValues();
    final payload = _buildPayload(settings, uid);
    setState(() {
      _isSending = true;
      _error = null;
      _requestJson = const JsonEncoder.withIndent('  ').convert(payload);
      _responseJson = null;
    });
    try {
      final response = await _service.postRecord(payload);
      if (!mounted) return;
      setState(() {
        _lastPostResponse = response;
        _responseJson = const JsonEncoder.withIndent('  ').convert(response.rawJson);
        _token = response.token;
      });
      if (response.result != 1) {
        setState(() => _error = response.message);
      }
    } catch (error) {
      if (mounted) setState(() => _error = _errorMessage(error));
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Map<String, dynamic> _buildPayload(UlinkSettingsResponse settings, int uid) =>
      <String, dynamic>{
        'UID': uid,
        'TimeStamp': _formatTimeStamp(DateTime.now()),
        'RelayStates': <String, int>{
          'RelayState1': _relayState1 ? 1 : 0,
          'RelayState2': _relayState2 ? 1 : 0,
        },
        'InputStatuses': <String, int>{
          'InputStatus1': _inputStatuses[0] ? 1 : 0,
          'InputStatus2': _inputStatuses[1] ? 1 : 0,
          'InputStatus3': _inputStatuses[2] ? 1 : 0,
          'InputStatus4': _inputStatuses[3] ? 1 : 0,
        },
        'Token': _token,
        'Devices': settings.devices
            .map(
              (device) => <String, dynamic>{
                'DID': device.id,
                'Code': device.code,
                'IsDeviceLive': 1,
                'DeviceParameters': device.deviceParameters
                    .map(
                      (parameter) => <String, dynamic>{
                        'Serial': parameter.serial,
                        'Value': _valueFor(device, parameter),
                      },
                    )
                    .toList(growable: false),
              },
            )
            .toList(growable: false),
      };

  void _randomWalkValues() {
    for (final controller in _valueControllers.values) {
      final current = double.tryParse(controller.text) ?? _newRandomValue();
      final next = (current + (_random.nextDouble() * 40 - 20)).clamp(100.0, 900.0);
      controller.text = next.toStringAsFixed(2);
    }
  }

  double _newRandomValue() => 100 + _random.nextDouble() * 800;

  double _valueFor(UlinkSettingsDevice device, UlinkDeviceParameter parameter) =>
      double.tryParse(_valueControllers[_parameterKey(device, parameter)]?.text ?? '') ??
      0.0;

  String _parameterKey(UlinkSettingsDevice device, UlinkDeviceParameter parameter) =>
      '${device.id}:${parameter.serial}';

  void _setContinuous(bool enabled) {
    setState(() => _continuous = enabled);
    if (enabled) {
      _restartEmulationTimer();
      _sendNow();
    } else {
      _emulationTimer?.cancel();
      _emulationTimer = null;
    }
  }

  void _restartEmulationTimer() {
    _emulationTimer?.cancel();
    final interval = _settings?.sendMessageInterval ?? 60000;
    _emulationTimer = Timer.periodic(
      Duration(milliseconds: interval > 0 ? interval : 60000),
      (_) => _sendNow(),
    );
  }

  String _formatTimeStamp(DateTime time) =>
      '${time.year.toString().padLeft(4, '0')}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} '
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';

  String _errorMessage(Object error) => error is UlinkApiException
      ? error.message
      : error is StateError
      ? error.message.toString()
      : 'Ulink request failed: $error';

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Emulate Ulink')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Standalone Ulink IoT gateway emulator',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _uCodeController,
            decoration: const InputDecoration(labelText: 'UCode'),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _isFetching ? null : _fetchSettings,
            icon: _isFetching
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator())
                : const Icon(Icons.download),
            label: const Text('Fetch Settings'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            _MessageBanner(message: _error!, isWarning: false),
          ],
          if (_settings != null) ..._settingsContent(_settings!),
          if (_requestJson != null || _responseJson != null) ...[
            const SizedBox(height: 16),
            _RawPayloadPanel(requestJson: _requestJson, responseJson: _responseJson),
          ],
        ],
      ),
    ),
  );

  List<Widget> _settingsContent(UlinkSettingsResponse settings) => <Widget>[
    const SizedBox(height: 16),
    if (settings.isActive == 0)
      const _MessageBanner(
        message: 'This Ulink is inactive. You can still test PostRecord manually.',
        isWarning: true,
      ),
    Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Fetched settings', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('IsActive: ${settings.isActive}'),
            Text('AppType: ${settings.appType}'),
            Text('CallbackInterval: ${settings.callbackInterval} ms'),
            Text('SendMessageInterval: ${settings.sendMessageInterval} ms'),
            Text('Devices: ${settings.deviceCount}'),
          ],
        ),
      ),
    ),
    const SizedBox(height: 12),
    TextField(
      controller: _uidController,
      keyboardType: TextInputType.number,
      decoration: const InputDecoration(labelText: 'UID'),
    ),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Auto-randomize values'),
      subtitle: const Text('Apply a small random walk before each record is sent.'),
      value: _autoRandomize,
      onChanged: (value) => setState(() => _autoRandomize = value),
    ),
    const Divider(),
    Text('Relay states', style: Theme.of(context).textTheme.titleMedium),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('RelayState1'),
      value: _relayState1,
      onChanged: (value) => setState(() => _relayState1 = value),
    ),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('RelayState2'),
      value: _relayState2,
      onChanged: (value) => setState(() => _relayState2 = value),
    ),
    const Divider(),
    Text('Input statuses', style: Theme.of(context).textTheme.titleMedium),
    for (var index = 0; index < _inputStatuses.length; index++)
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text('InputStatus${index + 1}'),
        value: _inputStatuses[index],
        onChanged: (value) => setState(() => _inputStatuses[index] = value),
      ),
    const Divider(),
    Text('Devices and parameters', style: Theme.of(context).textTheme.titleMedium),
    const SizedBox(height: 8),
    for (final device in settings.devices) _deviceCard(device),
    const SizedBox(height: 8),
    FilledButton.icon(
      onPressed: _isSending ? null : _sendNow,
      icon: _isSending
          ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator())
          : const Icon(Icons.send),
      label: const Text('Send Now'),
    ),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Start Continuous Emulation'),
      subtitle: Text(
        'Repeats every ${settings.sendMessageInterval > 0 ? settings.sendMessageInterval : 60000} ms.',
      ),
      value: _continuous,
      onChanged: _setContinuous,
    ),
    if (_lastPostResponse != null) _commandCard(_lastPostResponse!),
  ];

  Widget _deviceCard(UlinkSettingsDevice device) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Device ${device.id}: ${device.code}', style: Theme.of(context).textTheme.titleSmall),
          Text('ByteSequence: ${device.byteSequence}'),
          Text('AddressMode: ${device.addressMode}'),
          Text('ParameterCount: ${device.parameterCount}'),
          const SizedBox(height: 8),
          for (final parameter in device.deviceParameters) ...[
            Text(
              'Serial ${parameter.serial} — ${parameter.dataType}, Address ${parameter.address}, Register ${parameter.register}',
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _valueControllers[_parameterKey(device, parameter)],
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              enabled: !_autoRandomize,
              decoration: const InputDecoration(labelText: 'Value'),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    ),
  );

  Widget _commandCard(UlinkPostRecordResponse response) => Card(
    margin: const EdgeInsets.only(top: 12),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Gateway commands', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text('UserCommand1: ${response.userCommand1}'),
          Text('UserCommand2: ${response.userCommand2}'),
          Text('RelayCommand1: ${response.relayCommand1}'),
          Text('RelayCommand2: ${response.relayCommand2}'),
          if (response.isSendMessage == 1) ...[
            const SizedBox(height: 8),
            Text('SendMessageTo: ${response.sendMessageTo}'),
            Text('MessageContent: ${response.messageContent}'),
          ],
        ],
      ),
    ),
  );
}

class _MessageBanner extends StatelessWidget {
  const _MessageBanner({required this.message, required this.isWarning});

  final String message;
  final bool isWarning;

  @override
  Widget build(BuildContext context) => Material(
    color: isWarning
        ? Theme.of(context).colorScheme.tertiaryContainer
        : Theme.of(context).colorScheme.errorContainer,
    borderRadius: BorderRadius.circular(8),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(isWarning ? Icons.warning_amber_rounded : Icons.error_outline),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
        ],
      ),
    ),
  );
}

class _RawPayloadPanel extends StatelessWidget {
  const _RawPayloadPanel({this.requestJson, this.responseJson});

  final String? requestJson;
  final String? responseJson;

  @override
  Widget build(BuildContext context) => Card(
    child: ExpansionTile(
      title: const Text('Raw request and response JSON'),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        if (requestJson != null) _jsonBlock(context, 'Request', requestJson!),
        if (responseJson != null) _jsonBlock(context, 'Response', responseJson!),
      ],
    ),
  );

  Widget _jsonBlock(BuildContext context, String label, String json) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        SelectableText(json, style: const TextStyle(fontFamily: 'monospace')),
      ],
    ),
  );
}
