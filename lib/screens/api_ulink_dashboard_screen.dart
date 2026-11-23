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
    @visibleForTesting this.flashWorkflowBuilder,
  });
  final ApiLoginResult login;
  final UlinkApiRepository repository;
  final UlinkLoginPreferences? loginPreferences;
  final UlinkFlashWorkflow Function()? flashWorkflowBuilder;
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
    final workflow =
        widget.flashWorkflowBuilder?.call() ??
        UlinkFlashWorkflow(
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
  Widget build(BuildContext context) {
    const charcoal = Color(0xFF0C1116);
    const navy = Color(0xFF111E2B);
    final colors =
        ColorScheme.fromSeed(
          seedColor: const Color(0xFF36D6D0),
          brightness: Brightness.dark,
        ).copyWith(
          surface: const Color(0xFF15212B),
          surfaceContainerHighest: const Color(0xFF1D2B36),
          primary: const Color(0xFF45DCD5),
          secondary: const Color(0xFF80CBC4),
          error: const Color(0xFFFF8A80),
        );
    final assignedCount = _login.companies.fold<int>(
      0,
      (total, company) => total + (company.uCount ?? 0),
    );
    final hasFlashStatus =
        _flashStage != null ||
        _flashError != null ||
        _flashedSettingsClient != null;
    final selectedCompany = _selectedCompany;
    final assignedUlinks = selectedCompany == null
        ? const <ApiUlink>[]
        : _login.ulinks;

    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: colors,
        scaffoldBackgroundColor: charcoal,
        appBarTheme: const AppBarTheme(
          backgroundColor: navy,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
        ),
        dividerColor: colors.outlineVariant,
      ),
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back',
          ),
          title: const Text('U-Link Dashboard'),
          actions: [
            IconButton(
              onPressed: _refreshing ? null : _refreshLoginData,
              icon: _refreshing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
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
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  foregroundColor: colors.primary,
                  side: BorderSide(color: colors.primary.withValues(alpha: .6)),
                ),
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
              const SizedBox(height: 24),
              _DashboardSectionTitle(
                title: 'Overview',
                subtitle: 'Provisioning inventory at a glance',
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      label: 'Companies',
                      value: '${_login.companies.length}',
                      icon: Icons.apartment_outlined,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _StatCard(
                      label: 'In Stock',
                      value: '${_eligibleStock.length}',
                      icon: Icons.inventory_2_outlined,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _StatCard(
                      label: 'Assigned U-Links',
                      value: '$assignedCount',
                      icon: Icons.hub_outlined,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              const _DashboardSectionTitle(
                title: 'Companies',
                subtitle: 'Open a company to view its U-Links and devices',
              ),
              const SizedBox(height: 8),
              if (_login.companies.isEmpty)
                const _DashboardCard(
                  child: _Empty(
                    'No companies are assigned to this System Integrator.',
                  ),
                ),
              ..._login.companies.map(
                (company) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _DashboardCard(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      minVerticalPadding: 12,
                      title: Text(company.cName),
                      subtitle: Text(
                        company.uCount == null
                            ? 'U-Link count unavailable'
                            : '${company.uCount} U-Links',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _StateChip(
                            label: _activeLabel(company.cia),
                            positive: company.cia == true,
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
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
              ),
              const SizedBox(height: 20),
              _DashboardCard(
                child: ExpansionTile(
                  key: const Key('stock-ulinks-expansion'),
                  tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                  title: const Text('Stock U-Links'),
                  subtitle: Text(
                    '${_login.ulinksInStock.length} available records',
                  ),
                  leading: const Icon(Icons.inventory_2_outlined),
                  children: [
                    if (_login.ulinksInStock.isEmpty)
                      const _Empty('No U-Links in stock.'),
                    ..._login.ulinksInStock.map(
                      (ulink) => _StockDashboardRow(ulink: ulink),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              _DashboardCard(
                accent: true,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Provision a U-Link',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Factory device must advertise as ULINK.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text('1. Select company'),
                      const SizedBox(height: 8),
                      Semantics(
                        label: 'Select company',
                        child: DropdownButtonFormField<ApiCompany>(
                          key: const Key('provision-company-dropdown'),
                          initialValue: _selectedCompany,
                          decoration: const InputDecoration(
                            labelText: 'Company for this U-Link',
                            border: OutlineInputBorder(),
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
                              ? (company) =>
                                    setState(() => _selectedCompany = company)
                              : null,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text('2. Select stock U-Link'),
                      const SizedBox(height: 8),
                      Semantics(
                        label: 'Select stock U-Link',
                        child: DropdownButtonFormField<ApiUlink>(
                          key: const Key('provision-stock-dropdown'),
                          initialValue: _selectedStock,
                          decoration: const InputDecoration(
                            labelText: 'U-Link In Stock (not flashed)',
                            border: OutlineInputBorder(),
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
                              ? (ulink) =>
                                    setState(() => _selectedStock = ulink)
                              : null,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Semantics(
                        label: 'Flash New U-Link',
                        button: true,
                        child: FilledButton.icon(
                          key: const Key('flash-new-ulink'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                          ),
                          onPressed: _canFlash ? _flashSelectedUlink : null,
                          icon: const Icon(Icons.flash_on_outlined),
                          label: const Text('Flash New U-Link'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (hasFlashStatus) ...[
                const SizedBox(height: 16),
                _FlashStatusPanel(
                  stage: _flashStage,
                  error: _flashError,
                  settingsClientAvailable: _flashedSettingsClient != null,
                  onOpenSettings: _flashedSettingsClient == null
                      ? null
                      : _openFlashedSettings,
                ),
              ],
              const SizedBox(height: 28),
              const _DashboardSectionTitle(
                title: 'Recent / assigned U-Links',
                subtitle: 'Available assigned records for the selected company',
              ),
              const SizedBox(height: 8),
              if (selectedCompany == null)
                const _DashboardCard(
                  child: _Empty(
                    'Select a company above to view available assigned U-Links.',
                  ),
                )
              else if (assignedUlinks.isEmpty)
                const _DashboardCard(
                  child: _Empty('No assigned U-Links were returned.'),
                )
              else
                ...assignedUlinks.map(
                  (ulink) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _DashboardCard(
                      child: _AssignedDashboardRow(
                        ulink: ulink,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ApiDevicesScreen(
                              company: selectedCompany,
                              ulink: ulink,
                              session: _login.session,
                              repository: widget.repository,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardSectionTitle extends StatelessWidget {
  const _DashboardSectionTitle({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 2),
      Text(
        subtitle,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  );
}

class _DashboardCard extends StatelessWidget {
  const _DashboardCard({required this.child, this.accent = false});
  final Widget child;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: accent
              ? colors.primary.withValues(alpha: .5)
              : colors.outlineVariant,
        ),
      ),
      child: child,
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
  });
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => _DashboardCard(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary, size: 20),
          const SizedBox(height: 14),
          Text(value, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 2),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    ),
  );
}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.label, required this.positive});
  final String label;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = positive ? const Color(0xFF71D99B) : const Color(0xFFD0A15D);
    return Semantics(
      label: label,
      child: Chip(
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        avatar: Icon(
          positive ? Icons.check_circle_outline : Icons.pause_circle_outline,
          size: 14,
          color: color,
        ),
        label: Text(label),
        labelStyle: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: color),
        side: BorderSide(color: color.withValues(alpha: .45)),
        backgroundColor: colors.surfaceContainerHighest,
      ),
    );
  }
}

class _StockDashboardRow extends StatelessWidget {
  const _StockDashboardRow({required this.ulink});
  final ApiUlink ulink;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        const SizedBox(height: 8),
        Text(ulink.uCode, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        Text('Integration mode: ${ulink.udimC ?? ulink.udimI ?? 'Unknown'}'),
        Text('Maximum devices: ${ulink.umd ?? 'Unknown'}'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            _StateChip(
              label: _activeLabel(ulink.uia),
              positive: ulink.uia == true,
            ),
            _StateChip(
              label: ulink.uif == true ? 'Flashed' : 'Not flashed',
              positive: ulink.uif == true,
            ),
          ],
        ),
      ],
    ),
  );
}

class _AssignedDashboardRow extends StatelessWidget {
  const _AssignedDashboardRow({required this.ulink, required this.onTap});
  final ApiUlink ulink;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    minVerticalPadding: 12,
    title: Text(ulink.uCode),
    subtitle: Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          _StateChip(
            label: ulink.uif == true ? 'Flashed' : 'Not flashed',
            positive: ulink.uif == true,
          ),
          _StateChip(
            label: _activeLabel(ulink.uia),
            positive: ulink.uia == true,
          ),
          Chip(
            visualDensity: VisualDensity.compact,
            label: Text('Devices: ${ulink.dCount ?? 'Unknown'}'),
          ),
        ],
      ),
    ),
    trailing: const Icon(Icons.chevron_right),
    onTap: onTap,
  );
}

class _FlashStatusPanel extends StatelessWidget {
  const _FlashStatusPanel({
    required this.stage,
    required this.error,
    required this.settingsClientAvailable,
    required this.onOpenSettings,
  });
  final UlinkFlashStage? stage;
  final String? error;
  final bool settingsClientAvailable;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final completed = stage == UlinkFlashStage.completed && error == null;
    return _DashboardCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Flash status',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (error != null) ...[
              Row(
                children: [
                  Icon(Icons.error_outline, color: colors.error),
                  const SizedBox(width: 8),
                  Expanded(child: Text(error!)),
                ],
              ),
            ] else if (completed) ...[
              const Row(
                children: [
                  Icon(Icons.check_circle_outline, color: Color(0xFF71D99B)),
                  SizedBox(width: 8),
                  Text('U-Link provisioned'),
                ],
              ),
            ] else ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 12),
              Text(stage?.label ?? 'Preparing U-Link'),
            ],
            if (settingsClientAvailable) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onOpenSettings,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                icon: const Icon(Icons.settings_bluetooth),
                label: const Text('Open U-Link Settings'),
              ),
            ],
          ],
        ),
      ),
    );
  }
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

String _yesNo(bool? value) => value == null
    ? 'Unknown'
    : value
    ? 'Yes'
    : 'No';
String _activeLabel(bool? value) => value == null
    ? 'Active unknown'
    : value
    ? 'Active'
    : 'Inactive';
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
