import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../models/ulink_api_models.dart';
import '../widgets/dashboard_widgets.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.companies,
    required this.stock,
    required this.assignedCount,
    required this.onOpenSettings,
    required this.onOpenCompany,
    required this.onRefresh,
  });

  final List<ApiCompany> companies;
  final List<ApiUlink> stock;
  final int assignedCount;
  final VoidCallback onOpenSettings;
  final ValueChanged<ApiCompany> onOpenCompany;
  final Future<void> Function() onRefresh;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _query = '';
  bool _showAllStock = false;

  @override
  Widget build(BuildContext context) {
    final companies = widget.companies.where((company) => company.cName.toLowerCase().contains(_query.toLowerCase())).toList();
    final stock = _showAllStock ? widget.stock : widget.stock.take(3).toList();
    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView(
        key: const PageStorageKey('ulink-home-scroll'),
        padding: const EdgeInsets.fromLTRB(AppTokens.s16, AppTokens.s16, AppTokens.s16, AppTokens.s24),
        children: [
          Semantics(
            label: 'Connect to U-Link Settings',
            button: true,
            child: AppCard(
              accent: true,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: widget.onOpenSettings,
                  borderRadius: BorderRadius.circular(AppTokens.r16),
                  child: Padding(
                    padding: const EdgeInsets.all(AppTokens.s16),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(color: AppTokens.teal.withValues(alpha: .12), shape: BoxShape.circle),
                          child: const Icon(Icons.bluetooth_searching, color: AppTokens.teal),
                        ),
                        const SizedBox(width: AppTokens.s12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Connect to U-Link Settings', style: Theme.of(context).textTheme.titleMedium),
                              const SizedBox(height: AppTokens.s4),
                              const Text('Find a U-Link and manage its settings.', style: TextStyle(color: AppTokens.mutedText)),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppTokens.s8),
                        const StatusChip(label: 'Disconnected', icon: Icons.bluetooth_disabled, color: AppTokens.mutedText),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppTokens.s24),
          const SectionHeader(title: 'Overview', subtitle: 'Provisioning inventory at a glance'),
          const SizedBox(height: AppTokens.s12),
          Row(
            children: [
              Expanded(child: StatCard(label: 'Companies', value: '${widget.companies.length}', icon: Icons.apartment_outlined)),
              const SizedBox(width: AppTokens.s8),
              Expanded(child: StatCard(label: 'In Stock', value: '${widget.stock.length}', icon: Icons.inventory_2_outlined)),
              const SizedBox(width: AppTokens.s8),
              Expanded(child: StatCard(label: 'Assigned U-Links', value: '${widget.assignedCount}', icon: Icons.hub_outlined)),
            ],
          ),
          const SizedBox(height: AppTokens.s24),
          const SectionHeader(title: 'Companies', subtitle: 'Open a company to view its U-Links and devices'),
          if (widget.companies.length > 5) ...[
            const SizedBox(height: AppTokens.s12),
            TextField(
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search companies'),
            ),
          ],
          const SizedBox(height: AppTokens.s8),
          if (companies.isEmpty)
            const AppCard(child: EmptyState(icon: Icons.apartment_outlined, message: 'No companies are assigned to this System Integrator.')),
          ...companies.map((company) => Padding(
            padding: const EdgeInsets.only(top: AppTokens.s8),
            child: AppCard(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: AppTokens.s16, vertical: AppTokens.s4),
                title: Text(company.cName),
                subtitle: Text(company.uCount == null ? 'U-Link count unavailable' : '${company.uCount} U-Links'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StatusChip(
                      label: company.cia == null ? 'Status unknown' : company.cia! ? 'Active' : 'Inactive',
                      icon: company.cia == true ? Icons.check_circle_outline : Icons.pause_circle_outline,
                      color: company.cia == true ? AppTokens.success : AppTokens.warning,
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
                onTap: () => widget.onOpenCompany(company),
              ),
            ),
          )),
          const SizedBox(height: AppTokens.s24),
          SectionHeader(
            title: 'Stock U-Links',
            subtitle: '${widget.stock.length} eligible records',
            trailing: widget.stock.length > 3
                ? TextButton(onPressed: () => setState(() => _showAllStock = !_showAllStock), child: Text(_showAllStock ? 'Show less' : 'View all'))
                : null,
          ),
          const SizedBox(height: AppTokens.s8),
          if (stock.isEmpty)
            const AppCard(child: EmptyState(icon: Icons.inventory_2_outlined, message: 'No eligible U-Links are in stock.')),
          ...stock.map((ulink) => Padding(
            padding: const EdgeInsets.only(top: AppTokens.s8),
            child: AppCard(
              child: ListTile(
                leading: const Icon(Icons.memory_outlined, color: AppTokens.teal),
                title: Text(ulink.uCode),
                trailing: const StatusChip(label: 'Not flashed', icon: Icons.pending_outlined, color: AppTokens.warning),
              ),
            ),
          )),
        ],
      ),
    );
  }
}
