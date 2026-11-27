import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../models/ulink_api_models.dart';
import '../../../services/ulink_api_repository.dart';
import '../../../services/ulink_flash_workflow.dart';
import '../../../services/ulink_login_preferences.dart';
import 'attach_detach/attach_detach_screen.dart';
import 'home/home_screen.dart';
import 'provision/provision_screen.dart';

class DashboardShell extends StatefulWidget {
  const DashboardShell({
    super.key,
    required this.companies,
    required this.stock,
    required this.assignedCount,
    required this.selectedCompany,
    required this.selectedStock,
    required this.selectedAppType,
    required this.flashStage,
    required this.flashError,
    required this.settingsAvailable,
    required this.assignedUlinks,
    required this.session,
    required this.repository,
    this.loginPreferences,
    required this.onRefresh,
    required this.onLogout,
    required this.onOpenSettings,
    required this.onOpenCompany,
    required this.onCompanySelected,
    required this.onStockSelected,
    required this.onAppTypeSelected,
    required this.onFlash,
    required this.onOpenFlashedSettings,
    required this.onAssignedChanged,
    required this.onRetryAssigned,
  });

  final List<ApiCompany> companies;
  final List<ApiUlink> stock;
  final int assignedCount;
  final ApiCompany? selectedCompany;
  final ApiUlink? selectedStock;
  final UlinkAppType? selectedAppType;
  final UlinkFlashStage? flashStage;
  final String? flashError;
  final bool settingsAvailable;
  final Future<List<ApiUlink>>? assignedUlinks;
  final ApiSession session;
  final UlinkApiRepository repository;
  final UlinkLoginPreferences? loginPreferences;
  final Future<void> Function() onRefresh;
  final VoidCallback onLogout;
  final VoidCallback onOpenSettings;
  final ValueChanged<ApiCompany> onOpenCompany;
  final ValueChanged<ApiCompany> onCompanySelected;
  final ValueChanged<ApiUlink> onStockSelected;
  final ValueChanged<UlinkAppType> onAppTypeSelected;
  final VoidCallback onFlash;
  final VoidCallback onOpenFlashedSettings;
  final ValueChanged<List<ApiUlink>> onAssignedChanged;
  final VoidCallback onRetryAssigned;

  @override
  State<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends State<DashboardShell> {
  var _index = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        colorScheme: theme.colorScheme.copyWith(
          brightness: Brightness.dark,
          primary: AppTokens.teal,
          surface: AppTokens.surface,
          error: AppTokens.danger,
          onSurface: AppTokens.text,
          onSurfaceVariant: AppTokens.mutedText,
          outlineVariant: AppTokens.border,
        ),
        scaffoldBackgroundColor: AppTokens.background,
        appBarTheme: const AppBarTheme(backgroundColor: AppTokens.background, foregroundColor: AppTokens.text, elevation: 0),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppTokens.elevatedSurface,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTokens.r12), borderSide: const BorderSide(color: AppTokens.border)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTokens.r12), borderSide: const BorderSide(color: AppTokens.border)),
        ),
      ),
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('U-Link Dashboard'),
          actions: [
            Semantics(
              label: 'Refresh dashboard',
              button: true,
              child: IconButton(onPressed: widget.onRefresh, tooltip: 'Refresh Session Data', icon: const Icon(Icons.refresh)),
            ),
            Semantics(
              label: 'Log out',
              button: true,
              child: IconButton(onPressed: widget.onLogout, tooltip: 'Log out', icon: const Icon(Icons.logout)),
            ),
          ],
        ),
        body: IndexedStack(
          index: _index,
          children: [
            HomeScreen(
              companies: widget.companies,
              stock: widget.stock,
              assignedCount: widget.assignedCount,
              onOpenSettings: widget.onOpenSettings,
              onOpenCompany: widget.onOpenCompany,
              onRefresh: widget.onRefresh,
            ),
            ProvisionScreen(
              companies: widget.companies,
              eligibleStock: widget.stock,
              selectedCompany: widget.selectedCompany,
              selectedStock: widget.selectedStock,
              selectedAppType: widget.selectedAppType,
              flashStage: widget.flashStage,
              flashError: widget.flashError,
              settingsAvailable: widget.settingsAvailable,
              assignedUlinks: widget.assignedUlinks,
              session: widget.session,
              repository: widget.repository,
              loginPreferences: widget.loginPreferences,
              onCompanySelected: widget.onCompanySelected,
              onStockSelected: widget.onStockSelected,
              onAppTypeSelected: widget.onAppTypeSelected,
              onFlash: widget.onFlash,
              onOpenSettings: widget.onOpenFlashedSettings,
              onAssignedChanged: widget.onAssignedChanged,
              onRetryAssigned: widget.onRetryAssigned,
            ),
            const AttachDetachScreen(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (index) => setState(() => _index = index),
          indicatorColor: AppTokens.teal.withValues(alpha: .25),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.flash_on_outlined), selectedIcon: Icon(Icons.flash_on), label: 'Provision'),
            NavigationDestination(icon: Icon(Icons.link_outlined), selectedIcon: Icon(Icons.link), label: 'Attach / Detach'),
          ],
        ),
      ),
    );
  }
}
