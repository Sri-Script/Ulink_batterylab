import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/ulink_api_models.dart';
import '../services/acknowledgement_sound_service.dart';
import '../services/ulink_api_repository.dart';
import '../services/ulink_ble_provisioning_client.dart';
import '../services/ulink_flash_workflow.dart';
import '../services/ulink_login_preferences.dart';
import 'ulink_device_picker_screen.dart';
import 'ulink_login_screen.dart';
import 'ulink_wifi_provisioning_screen.dart';

class ApiSiDashboardScreen extends StatefulWidget {
  const ApiSiDashboardScreen({
    super.key,
    required this.login,
    required this.repository,
    this.loginPreferences,
  });
  final ApiLoginResult login;
  final UlinkApiRepository repository;
  final UlinkLoginPreferences? loginPreferences;
  @override
  State<ApiSiDashboardScreen> createState() => _ApiSiDashboardScreenState();
}

class _ApiSiDashboardScreenState extends State<ApiSiDashboardScreen> {
  late ApiLoginResult _login = widget.login;
  bool _refreshing = false;
  ApiCompany? _selectedCompany;
  ApiUlink? _selectedStock;
  UlinkFlashStage? _flashStage;
  UlinkSettingsClient? _flashedSettingsClient;
  String? _flashError;

  static const _testUcode = String.fromEnvironment('ULINK_TEST_UCODE');

  @override
  void initState() {
    super.initState();
    _selectDevelopmentTestUcodeIfAvailable();
  }

  void _selectDevelopmentTestUcodeIfAvailable() {
    if (kReleaseMode || _testUcode.isEmpty || _selectedStock != null) return;
    for (final ulink in _eligibleStock) {
      if (ulink.uCode == _testUcode) {
        _selectedStock = ulink;
        return;
      }
    }
  }

  List<ApiUlink> get _eligibleStock => _login.ulinksInStock
      .where((ulink) => ulink.uif != true)
      .where((ulink) => UlinkFlashProtocol.isValidUcode(ulink.uCode))
      .toList();

  bool get _canFlash =>
      !_refreshing &&
      _flashStage == null &&
      _selectedCompany != null &&
      _selectedStock != null;

  Future<void> _refreshLoginData() async {
    final password = await _askForPassword(context);
    if (password == null || !mounted) return;
    setState(() => _refreshing = true);
    try {
      final username =
          await (widget.loginPreferences ??
                  SharedPreferencesUlinkLoginPreferences())
              .readUsername() ??
          _login.session.userName;
      final refreshed = await widget.repository.login(
        username: username,
        password: password,
      );
      if (mounted) {
        final selectedStockId = _selectedStock?.uid;
        final selectedCompanyId = _selectedCompany?.cid;
        setState(() {
          _login = refreshed;
          _selectedStock = _stockWithId(selectedStockId);
          _selectedCompany = _companyWithId(selectedCompanyId);
          _selectDevelopmentTestUcodeIfAvailable();
        });
      }
    } on UlinkApiException catch (error) {
      if (mounted) _showError(error.message);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  ApiUlink? _stockWithId(String? uid) {
    if (uid == null) return null;
    for (final stock in _eligibleStock) {
      if (stock.uid == uid) return stock;
    }
    return null;
  }

  ApiCompany? _companyWithId(String? cid) {
    if (cid == null) return null;
    for (final company in _login.companies) {
      if (company.cid == cid) return company;
    }
    return null;
  }

  Future<void> _logout() async {
    await widget.repository.logout();
    if (mounted) {
      await Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const UlinkLoginScreen()),
        (route) => route.isFirst,
      );
    }
  }

  void _showError(String message) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: Theme.of(context).colorScheme.error,
    ),
  );

  Future<void> _flashSelectedUlink() async {
    final company = _selectedCompany;
    final stock = _selectedStock;
    if (company == null || stock == null) return;
    final selection = UlinkFlashSelection(
      session: _login.session,
      company: company,
      stockUlink: stock,
    );
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Flash U-Link?'),
            content: Text(
              'This Rev5 operation is write-once.\n\nCompany: ${company.cName}\nUlinkID: ${stock.uid}\nUCode: ${stock.uCode}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Flash'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    setState(() {
      _flashError = null;
      _flashStage = UlinkFlashStage.checkingApiConnection;
    });
    final workflow = UlinkFlashWorkflow(
      ble: FlutterUlinkFlashBleGateway(),
      api: UlinkRepositoryFlashGateway(widget.repository),
    );
    try {
      final result = await workflow.run(
        selection,
        onProgress: (stage) {
          if (mounted) setState(() => _flashStage = stage);
        },
      );
      if (!mounted) {
        await result.settingsClient.disconnect();
        return;
      }
      setState(() => _flashedSettingsClient = result.settingsClient);
      await const AcknowledgementSoundService().play();
    } on UlinkFlashException catch (error) {
      if (mounted) setState(() => _flashError = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _flashError =
              (_flashStage ?? UlinkFlashStage.checkingApiConnection)
                  .failureMessage,
        );
      }
    } finally {
      if (mounted && _flashedSettingsClient == null) {
        setState(() => _flashStage = null);
      }
    }
  }

  Future<void> _openFlashedSettings() async {
    final client = _flashedSettingsClient;
    if (client == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => UlinkWifiProvisioningScreen(client: client),
      ),
    );
    if (mounted) setState(() => _flashedSettingsClient = null);
  }

  @override
  void dispose() {
    _flashedSettingsClient?.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('U-Link dashboard'),
      actions: [
        IconButton(
          onPressed: _refreshing ? null : _refreshLoginData,
          icon: const Icon(Icons.refresh),
          tooltip: 'Refresh Session Data',
        ),
        IconButton(
          onPressed: _logout,
          icon: const Icon(Icons.logout),
          tooltip: 'Log out',
        ),
      ],
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton.icon(
            icon: const Icon(Icons.bluetooth_connected),
            label: const Text('Connect to U-Link Settings'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => UlinkDevicePickerScreen(
                  loginPreferences: widget.loginPreferences,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Companies', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (_login.companies.isEmpty)
            const _Empty(
              'No companies are assigned to this System Integrator.',
            ),
          ..._login.companies.map(
            (company) => Card(
              child: ListTile(
                title: Text(company.cName),
                subtitle: Text(_companyMeta(company)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ApiCompanyUlinksScreen(
                      company: company,
                      session: _login.session,
                      repository: widget.repository,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'U-Links in Stock',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          if (_login.ulinksInStock.isEmpty)
            const _Empty('No U-Links in stock.'),
          ..._login.ulinksInStock.map(
            (ulink) => Card(child: _UlinkTile(ulink: ulink)),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<ApiCompany>(
            key: ValueKey<String?>('company-${_selectedCompany?.cid}'),
            initialValue: _selectedCompany,
            decoration: const InputDecoration(
              labelText: 'Company for this U-Link',
            ),
            items: _login.companies
                .map(
                  (company) => DropdownMenuItem(
                    value: company,
                    child: Text(company.cName),
                  ),
                )
                .toList(),
            onChanged: _flashStage == null
                ? (company) => setState(() => _selectedCompany = company)
                : null,
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<ApiUlink>(
            key: ValueKey<String?>('stock-${_selectedStock?.uid}'),
            initialValue: _selectedStock,
            decoration: const InputDecoration(
              labelText: 'U-Link In Stock (not flashed)',
            ),
            items: _eligibleStock
                .map(
                  (ulink) => DropdownMenuItem(
                    value: ulink,
                    child: Text(
                      ulink.uCode == _testUcode && !kReleaseMode
                          ? '${ulink.uCode} (test)'
                          : ulink.uCode,
                    ),
                  ),
                )
                .toList(),
            onChanged: _flashStage == null
                ? (ulink) => setState(() => _selectedStock = ulink)
                : null,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _canFlash ? _flashSelectedUlink : null,
            icon: const Icon(Icons.flash_on_outlined),
            label: const Text('Flash New U-Link'),
          ),
          if (_flashStage != null) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Text(
              _flashStage!.label +
                  (_flashStage == UlinkFlashStage.verifyingAssignedUlink &&
                          _selectedStock != null
                      ? ' ULINK-${_selectedStock!.uCode}'
                      : ''),
            ),
          ],
          if (_flashError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _flashError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (_flashedSettingsClient != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: FilledButton.icon(
                onPressed: _openFlashedSettings,
                icon: const Icon(Icons.settings_bluetooth),
                label: const Text('Open U-Link Settings'),
              ),
            ),
        ],
      ),
    ),
  );
}

class ApiCompanyUlinksScreen extends StatefulWidget {
  const ApiCompanyUlinksScreen({
    super.key,
    required this.company,
    required this.session,
    required this.repository,
  });
  final ApiCompany company;
  final ApiSession session;
  final UlinkApiRepository repository;
  @override
  State<ApiCompanyUlinksScreen> createState() => _ApiCompanyUlinksScreenState();
}

class _ApiCompanyUlinksScreenState extends State<ApiCompanyUlinksScreen> {
  late Future<List<ApiUlink>> _ulinks = _load();
  Future<List<ApiUlink>> _load() => widget.repository.getCompanyUlinks(
    userId: widget.session.userId,
    companyId: widget.company.cid,
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.company.cName)),
    body: FutureBuilder<List<ApiUlink>>(
      future: _ulinks,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _Retry(
            error: _friendly(snapshot.error),
            onRetry: () => setState(() => _ulinks = _load()),
          );
        }
        final ulinks = snapshot.data ?? const <ApiUlink>[];
        if (ulinks.isEmpty) {
          return const _Empty('No U-Links are assigned to this company.');
        }
        return RefreshIndicator(
          onRefresh: () async => setState(() => _ulinks = _load()),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: ulinks
                .map(
                  (ulink) => Card(
                    child: _UlinkTile(
                      ulink: ulink,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ApiDevicesScreen(
                            company: widget.company,
                            ulink: ulink,
                            session: widget.session,
                            repository: widget.repository,
                          ),
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        );
      },
    ),
  );
}

class ApiDevicesScreen extends StatefulWidget {
  const ApiDevicesScreen({
    super.key,
    required this.company,
    required this.ulink,
    required this.session,
    required this.repository,
  });
  final ApiCompany company;
  final ApiUlink ulink;
  final ApiSession session;
  final UlinkApiRepository repository;
  @override
  State<ApiDevicesScreen> createState() => _ApiDevicesScreenState();
}

class _ApiDevicesScreenState extends State<ApiDevicesScreen> {
  late Future<List<ApiDevice>> _devices = _load();
  Future<List<ApiDevice>> _load() => widget.repository.getDevices(
    userId: widget.session.userId,
    companyId: widget.company.cid,
    ulinkId: widget.ulink.uid,
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.ulink.uCode)),
    body: FutureBuilder<List<ApiDevice>>(
      future: _devices,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _Retry(
            error: _friendly(snapshot.error),
            onRetry: () => setState(() => _devices = _load()),
          );
        }
        final devices = snapshot.data ?? const <ApiDevice>[];
        if (devices.isEmpty) {
          return const _Empty('No devices are assigned to this U-Link.');
        }
        return RefreshIndicator(
          onRefresh: () async => setState(() => _devices = _load()),
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: devices.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, index) {
              final device = devices[index];
              return Card(
                child: ListTile(
                  title: Text(device.dCode),
                  subtitle: Text(
                    [
                      if (device.deviceName != null) device.deviceName!,
                      if (device.deviceType != null) device.deviceType!,
                      'Flashed: ${_yesNo(device.dif)}',
                      'Active: ${_yesNo(device.dia)}',
                    ].join('\n'),
                  ),
                ),
              );
            },
          ),
        );
      },
    ),
  );
}

class ApiCompanyAdminDashboardScreen extends StatelessWidget {
  const ApiCompanyAdminDashboardScreen({
    super.key,
    required this.login,
    required this.repository,
    this.loginPreferences,
  });
  final ApiLoginResult login;
  final UlinkApiRepository repository;
  final UlinkLoginPreferences? loginPreferences;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Company Admin dashboard'),
      actions: [
        IconButton(
          onPressed: () async {
            await repository.logout();
            if (context.mounted) {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute<void>(
                  builder: (_) => const UlinkLoginScreen(),
                ),
                (route) => route.isFirst,
              );
            }
          },
          icon: const Icon(Icons.logout),
          tooltip: 'Log out',
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('U-Links', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        if (login.ulinks.isEmpty)
          const _Empty('No U-Links were returned for this account.'),
        ...login.ulinks.map((ulink) => Card(child: _UlinkTile(ulink: ulink))),
        const SizedBox(height: 16),
        const Text(
          'Device provisioning is restricted to an authorized CompanyID. The current API Login response does not provide CompanyID, so GetDevices and device provisioning remain disabled.',
        ),
        const SizedBox(height: 8),
        const Text(
          'U-Link reset is disabled until the destructive confirmation and fresh-password flow is completed.',
        ),
      ],
    ),
  );
}

class _UlinkTile extends StatelessWidget {
  const _UlinkTile({required this.ulink, this.onTap});
  final ApiUlink ulink;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => ListTile(
    onTap: onTap,
    title: Text(ulink.uCode),
    trailing: onTap == null ? null : const Icon(Icons.chevron_right),
    subtitle: Text(
      [
        'Integration mode: ${ulink.udimC ?? ulink.udimI ?? 'Unknown'}',
        'Active: ${_yesNo(ulink.uia)}',
        'Flashed: ${_yesNo(ulink.uif)}',
        if (ulink.umd != null) 'Maximum devices: ${ulink.umd}',
        if (ulink.dCount != null) 'Devices: ${ulink.dCount}',
      ].join('\n'),
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Text(text, textAlign: TextAlign.center),
  );
}

class _Retry extends StatelessWidget {
  const _Retry({required this.error, required this.onRetry});
  final String error;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(error, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    ),
  );
}

String _companyMeta(ApiCompany company) => [
  if (company.uCount != null) '${company.uCount} U-Links',
  if (company.cia != null) 'Active: ${_yesNo(company.cia)}',
].join(' • ');
String _yesNo(bool? value) => value == null
    ? 'Unknown'
    : value
    ? 'Yes'
    : 'No';
String _friendly(Object? error) {
  if (error is! UlinkApiException) {
    return 'The service is unavailable. Please check your connection and try again.';
  }
  return switch (error.statusCode) {
    401 => 'Your API session has expired. Sign in again.',
    403 => 'You do not have permission to view this data.',
    404 => 'The requested U-Link data was not found.',
    429 => 'Too many requests. Please wait and try again.',
    503 => 'The API service is temporarily unavailable.',
    _ => error.message,
  };
}

Future<String?> _askForPassword(BuildContext context) async {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Refresh session data'),
      content: TextField(
        controller: controller,
        obscureText: true,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Password'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('Refresh'),
        ),
      ],
    ),
  );
}
