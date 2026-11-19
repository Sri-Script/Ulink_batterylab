import 'package:flutter/material.dart';

import '../models/si_provisioning_models.dart';
import '../services/provisioning_repository.dart';
import 'si_company_dashboard_screen.dart';

class SiCompanySelectionScreen extends StatefulWidget {
  const SiCompanySelectionScreen({
    super.key,
    required this.siUid,
    this.repository,
  });

  final String siUid;
  final ProvisioningRepository? repository;

  @override
  State<SiCompanySelectionScreen> createState() =>
      _SiCompanySelectionScreenState();
}

class _SiCompanySelectionScreenState extends State<SiCompanySelectionScreen> {
  late final ProvisioningRepository _repository =
      widget.repository ?? FirestoreProvisioningRepository();
  late Future<List<ProvisioningCompany>> _companies = _load();

  Future<List<ProvisioningCompany>> _load() async {
    final companies = List<ProvisioningCompany>.of(
      await _repository.companiesForSi(widget.siUid),
    );
    companies.sort((left, right) {
      final alphabetical = left.name.toLowerCase().compareTo(
        right.name.toLowerCase(),
      );
      return alphabetical != 0 ? alphabetical : left.name.compareTo(right.name);
    });
    return companies;
  }

  void _reloadCompanies() {
    setState(() {
      _companies = _load();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Select Company')),
    body: FutureBuilder<List<ProvisioningCompany>>(
      future: _companies,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _LoadError(
            message: snapshot.error is ProvisioningException
                ? snapshot.error.toString()
                : 'Could not load your assigned companies.',
            onRetry: _reloadCompanies,
          );
        }
        final companies = snapshot.data ?? const <ProvisioningCompany>[];
        if (companies.isEmpty) {
          return _EmptyCompanies(onRefresh: _reloadCompanies);
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: companies.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final company = companies[index];
            return Card(
              child: ListTile(
                title: Text(company.name),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SiCompanyDashboardScreen(
                      siUid: widget.siUid,
                      company: company,
                      repository: _repository,
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    ),
  );
}

class _EmptyCompanies extends StatelessWidget {
  const _EmptyCompanies({required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'No companies are assigned to this System Integrator.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRefresh, child: const Text('Refresh')),
        ],
      ),
    ),
  );
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}
