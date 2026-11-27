import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../models/ulink_api_models.dart';
import '../../../../services/ulink_api_repository.dart';
import '../../../../services/ulink_login_preferences.dart';
import '../../../../services/ulink_unflash_workflow.dart';
import 'dashboard_widgets.dart';

/// The single presentation entry point for the existing irreversible unflash
/// workflow. It deliberately delegates every BLE and API step to the existing
/// workflow and gateways; no protocol or mutation logic lives in a screen.
class UlinkUnflashAction extends StatefulWidget {
  const UlinkUnflashAction({
    super.key,
    required this.company,
    required this.ulink,
    required this.session,
    required this.repository,
    this.loginPreferences,
    this.onCompleted,
    this.filled = false,
  });

  final ApiCompany company;
  final ApiUlink ulink;
  final ApiSession session;
  final UlinkApiRepository repository;
  final UlinkLoginPreferences? loginPreferences;
  final ValueChanged<List<ApiUlink>>? onCompleted;
  final bool filled;

  @override
  State<UlinkUnflashAction> createState() => _UlinkUnflashActionState();
}

class _UlinkUnflashActionState extends State<UlinkUnflashAction> {
  UlinkUnflashStage? _stage;
  String? _error;
  UlinkRepositoryUnflashApiGateway? _pendingApi;
  UlinkUnflashSelection? _pendingSelection;

  Future<void> _unflashSelectedUlink() async {
    if (widget.ulink.uif != true || _stage != null) return;
    final password = await _askForPassword(
      context,
      title: 'Confirm API password',
      actionLabel: 'Sign in and continue',
    );
    if (password == null || !mounted) return;
    try {
      final username =
          await (widget.loginPreferences ?? SharedPreferencesUlinkLoginPreferences()).readUsername() ??
          widget.session.userName;
      final api = UlinkRepositoryUnflashApiGateway(widget.repository);
      final freshLogin = await api.authenticateFreshly(username: username, password: password);
      if (!mounted) return;
      await _runUnflashFlow(freshLogin, api);
    } on UlinkApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _runUnflashFlow(
    ApiLoginResult freshLogin,
    UlinkRepositoryUnflashApiGateway api,
  ) async {
    if (widget.ulink.uif != true || _stage != null) return;
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Unflash U-Link?'),
            content: Text(
              'Company: ${widget.company.cName}\n'
              'U-Link UCode: ${widget.ulink.uCode}\n'
              'U-Link UID: ${widget.ulink.uid}\n\n'
              'This permanently clears the UCode from the physical U-Link and returns its Bluetooth name to ULINK.\n\n'
              'The server operation may delete linked device data.\n\n'
              'Wi-Fi, password, APN, mode, calibration, and unrelated settings are not erased.\n\n'
              'Unflashing removes this U-Link identity and resets associated server device data. This cannot be undone automatically.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Permanently unflash U-Link'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    setState(() {
      _error = null;
      _stage = null;
    });
    try {
      final selection = UlinkUnflashSelection(session: freshLogin.session, company: widget.company, ulink: widget.ulink);
      _pendingApi = api;
      _pendingSelection = selection;
      final ulinks = await UlinkUnflashWorkflow(
        ble: FlutterUlinkUnflashBleGateway(),
        api: api,
      ).run(
        selection,
        onProgress: (stage) {
          if (mounted) setState(() => _stage = stage);
        },
      );
      if (!mounted) return;
      final next = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('U-Link unflashed successfully'),
          content: const Text('The U-Link is now factory-advertising as ULINK and its server assignment has been cleared.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, 'dashboard'), child: const Text('Return to dashboard')),
            FilledButton(onPressed: () => Navigator.pop(context, 'flash'), child: const Text('Flash a new U-Code')),
          ],
        ),
      );
      if (mounted && next != null) widget.onCompleted?.call(ulinks);
    } on UlinkUnflashException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          if (!error.pendingServerRetry) {
            _pendingApi = null;
            _pendingSelection = null;
          }
        });
      }
    } on UlinkApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted && _stage != UlinkUnflashStage.completed) setState(() => _stage = null);
    }
  }

  Future<void> _retryPendingUnflashServerUpdate() async {
    final api = _pendingApi;
    final selection = _pendingSelection;
    if (api == null || selection == null || _stage != null) return;
    setState(() {
      _error = null;
      _stage = UlinkUnflashStage.updatingServer;
    });
    try {
      final ulinks = await api.retryPendingUpdate(selection);
      if (ulinks.any((item) => item.uid == selection.ulink.uid && item.uif == true)) {
        throw const UlinkUnflashException('The server still shows this U-Link as flashed. Needs reconciliation; do not reflash it.', needsReconciliation: true);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('U-Link unflashed successfully')));
      widget.onCompleted?.call(ulinks);
    } on UlinkUnflashException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on UlinkApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _stage = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.ulink.uif != true) return const SizedBox.shrink();
    final button = widget.filled
        ? FilledButton.icon(
            key: const Key('unflash-ulink'),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error, minimumSize: const Size.fromHeight(48)),
            onPressed: _stage == null ? _unflashSelectedUlink : null,
            icon: const Icon(Icons.warning_amber_outlined),
            label: const Text('Unflash U-Link'),
          )
        : OutlinedButton.icon(
            key: const Key('unflash-ulink'),
            style: OutlinedButton.styleFrom(foregroundColor: AppTokens.danger, side: const BorderSide(color: AppTokens.danger), minimumSize: const Size(48, 44)),
            onPressed: _stage == null ? _unflashSelectedUlink : null,
            icon: _stage == null ? const Icon(Icons.warning_amber_outlined) : const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            label: const Text('Unflash'),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        button,
        if (_stage != null || _error != null) ...[
          const SizedBox(height: AppTokens.s12),
          AppCard(
            padding: const EdgeInsets.all(AppTokens.s12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Unflash status', style: Theme.of(context).textTheme.titleSmall),
                if (_stage != null) ...[const SizedBox(height: AppTokens.s8), Text(_stage!.label)],
                if (_error != null) ...[const SizedBox(height: AppTokens.s8), Text(_error!, style: const TextStyle(color: AppTokens.danger))],
                if (_pendingApi != null && _pendingSelection != null) ...[
                  const SizedBox(height: AppTokens.s12),
                  OutlinedButton(onPressed: _retryPendingUnflashServerUpdate, child: const Text('Retry pending server update')),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

Future<String?> _askForPassword(
  BuildContext context, {
  required String title,
  required String actionLabel,
}) async {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(controller: controller, obscureText: true, autofocus: true, decoration: const InputDecoration(labelText: 'Password')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: Text(actionLabel)),
      ],
    ),
  );
}
