import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../models/ulink_api_models.dart';
import '../../../../services/ulink_api_repository.dart';
import '../../../../services/ulink_flash_workflow.dart';
import '../../../../services/ulink_login_preferences.dart';
import '../widgets/dashboard_widgets.dart';
import '../widgets/unflash_ulink_action.dart';

class ProvisionScreen extends StatelessWidget {
  const ProvisionScreen({
    super.key,
    required this.companies,
    required this.eligibleStock,
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
    required this.onCompanySelected,
    required this.onStockSelected,
    required this.onAppTypeSelected,
    required this.onFlash,
    required this.onOpenSettings,
    required this.onAssignedChanged,
    required this.onRetryAssigned,
  });

  final List<ApiCompany> companies;
  final List<ApiUlink> eligibleStock;
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
  final ValueChanged<ApiCompany> onCompanySelected;
  final ValueChanged<ApiUlink> onStockSelected;
  final ValueChanged<UlinkAppType> onAppTypeSelected;
  final VoidCallback onFlash;
  final VoidCallback onOpenSettings;
  final ValueChanged<List<ApiUlink>> onAssignedChanged;
  final VoidCallback onRetryAssigned;

  bool get _locked => flashStage != null;
  bool get _canFlash => !_locked && selectedCompany != null && selectedStock != null && selectedAppType != null;

  Future<void> _pickCompany(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Theme(
        data: Theme.of(context),
        child: SearchablePickerBottomSheet<ApiCompany>(
          title: 'Select company',
          items: companies,
          labelFor: (company) => company.cName,
          onSelected: (company) {
            Navigator.pop(sheetContext);
            onCompanySelected(company);
          },
        ),
      ),
    );
  }

  Future<void> _pickStock(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Theme(
        data: Theme.of(context),
        child: SearchablePickerBottomSheet<ApiUlink>(
          title: 'Select stock U-Link',
          items: eligibleStock,
          labelFor: (ulink) => ulink.uCode,
          onSelected: (ulink) {
            Navigator.pop(sheetContext);
            onStockSelected(ulink);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: ListView(
          key: const PageStorageKey('ulink-provision-scroll'),
          padding: const EdgeInsets.fromLTRB(AppTokens.s16, AppTokens.s16, AppTokens.s16, AppTokens.s16),
          children: [
            Text('Provision a U-Link', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: AppTokens.s4),
            Text('Factory device must advertise as ULINK.', style: TextStyle(color: Theme.of(context).extension<UlinkThemeTokens>()!.textMuted)),
            const SizedBox(height: AppTokens.s16),
            StepCard(
              number: 1,
              title: 'Company',
              unlocked: !_locked,
              completed: selectedCompany != null,
              summary: selectedCompany?.cName,
              child: PickerField(
                key: const Key('provision-company-picker'),
                label: 'Choose an authorized company',
                value: selectedCompany?.cName,
                enabled: !_locked,
                onTap: () => _pickCompany(context),
              ),
            ),
            const SizedBox(height: AppTokens.s12),
            StepCard(
              number: 2,
              title: 'Stock U-Link',
              unlocked: selectedCompany != null && !_locked,
              completed: selectedStock != null,
              summary: selectedStock?.uCode,
              child: PickerField(
                key: const Key('provision-stock-picker'),
                label: 'Choose an eligible not-flashed U-Link',
                value: selectedStock?.uCode,
                enabled: selectedCompany != null && !_locked,
                onTap: () => _pickStock(context),
              ),
            ),
            const SizedBox(height: AppTokens.s12),
            StepCard(
              number: 3,
              title: 'Deployment type',
              unlocked: selectedCompany != null && selectedStock != null && !_locked,
              completed: selectedAppType != null,
              summary: selectedAppType?.label,
              child: Row(
                children: [
                  SelectableOptionCard(
                    key: const Key('provision-app-type-demo'),
                    title: 'Demo',
                    icon: Icons.science_outlined,
                    selected: selectedAppType == UlinkAppType.demo,
                    onTap: selectedCompany != null && selectedStock != null && !_locked ? () => onAppTypeSelected(UlinkAppType.demo) : null,
                  ),
                  const SizedBox(width: AppTokens.s8),
                  SelectableOptionCard(
                    key: const Key('provision-app-type-live'),
                    title: 'Live',
                    icon: Icons.rocket_launch_outlined,
                    selected: selectedAppType == UlinkAppType.live,
                    onTap: selectedCompany != null && selectedStock != null && !_locked ? () => onAppTypeSelected(UlinkAppType.live) : null,
                  ),
                ],
              ),
            ),
            if (flashStage != null || flashError != null || settingsAvailable) ...[
              const SizedBox(height: AppTokens.s16),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                child: AppCard(
                  key: ValueKey('$flashStage-$flashError-$settingsAvailable'),
                  accent: flashError == null && (flashStage != null || settingsAvailable),
                  padding: const EdgeInsets.all(AppTokens.s16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Flash status', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: AppTokens.s12),
                      if (flashError != null)
                        Row(children: [Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error), const SizedBox(width: AppTokens.s8), Expanded(child: Text(flashError!))])
                      else if (settingsAvailable)
                        Row(children: [Icon(Icons.check_circle_outline, color: Theme.of(context).extension<UlinkThemeTokens>()!.success), const SizedBox(width: AppTokens.s8), const Text('U-Link provisioned')])
                      else ...[
                        const LinearProgressIndicator(),
                        const SizedBox(height: AppTokens.s12),
                        Text(flashStage?.label ?? 'Preparing U-Link'),
                      ],
                      if (settingsAvailable) ...[
                        const SizedBox(height: AppTokens.s12),
                        PrimaryActionButton(label: 'Open U-Link Settings', icon: Icons.settings_bluetooth, onPressed: onOpenSettings),
                      ],
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: AppTokens.s24),
            const SectionHeader(title: 'Assigned U-Links', subtitle: 'Available assigned records for the selected company'),
            const SizedBox(height: AppTokens.s8),
            _AssignedUlinks(
              company: selectedCompany,
              ulinks: assignedUlinks,
              session: session,
              repository: repository,
              loginPreferences: loginPreferences,
              onChanged: onAssignedChanged,
              onRetry: onRetryAssigned,
            ),
          ],
        ),
      ),
      SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(AppTokens.s16, AppTokens.s8, AppTokens.s16, AppTokens.s8),
        child: PrimaryActionButton(
          key: const Key('flash-new-ulink'),
          label: flashStage != null ? flashStage!.label : 'Flash New U-Link',
          loading: flashStage != null,
          onPressed: _canFlash ? onFlash : null,
        ),
      ),
    ],
  );
}

class _AssignedUlinks extends StatelessWidget {
  const _AssignedUlinks({
    required this.company,
    required this.ulinks,
    required this.session,
    required this.repository,
    required this.loginPreferences,
    required this.onChanged,
    required this.onRetry,
  });

  final ApiCompany? company;
  final Future<List<ApiUlink>>? ulinks;
  final ApiSession session;
  final UlinkApiRepository repository;
  final UlinkLoginPreferences? loginPreferences;
  final ValueChanged<List<ApiUlink>> onChanged;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (company == null) {
      return const AppCard(child: EmptyState(icon: Icons.business_outlined, message: 'Select a company to see its U-Links.'));
    }
    final future = ulinks;
    if (future == null) return const AppCard(child: SkeletonBox(height: 96));
    return FutureBuilder<List<ApiUlink>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const AppCard(padding: EdgeInsets.all(AppTokens.s12), child: Column(children: [SkeletonBox(), SizedBox(height: AppTokens.s8), SkeletonBox()]));
        }
        if (snapshot.hasError) {
          return AppCard(child: ErrorState(onRetry: onRetry));
        }
        final items = snapshot.data ?? const <ApiUlink>[];
        if (items.isEmpty) {
          return const AppCard(child: EmptyState(icon: Icons.hub_outlined, message: 'No U-Links flashed for this company yet.'));
        }
        return Column(
          children: items.map((ulink) => Padding(
            padding: const EdgeInsets.only(bottom: AppTokens.s8),
            child: AppCard(
              padding: const EdgeInsets.all(AppTokens.s12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(ulink.uCode, style: Theme.of(context).textTheme.titleMedium)),
                      StatusChip(
                        label: ulink.uif == true ? 'Flashed' : 'Not flashed',
                        icon: ulink.uif == true ? Icons.check_circle_outline : Icons.pending_outlined,
                        color: ulink.uif == true ? Theme.of(context).extension<UlinkThemeTokens>()!.success : Theme.of(context).extension<UlinkThemeTokens>()!.warning,
                      ),
                    ],
                  ),
                  if (ulink.uif == true) ...[
                    const SizedBox(height: AppTokens.s12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: UlinkUnflashAction(
                        company: company!,
                        ulink: ulink,
                        session: session,
                        repository: repository,
                        loginPreferences: loginPreferences,
                        onCompleted: onChanged,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          )).toList(),
        );
      },
    );
  }
}
