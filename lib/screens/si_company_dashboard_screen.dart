import 'package:flutter/material.dart';

import '../models/si_provisioning_models.dart';
import '../services/provisioning_repository.dart';
import '../services/ulink_provisioning_protocol.dart';

class SiCompanyDashboardScreen extends StatelessWidget {
  const SiCompanyDashboardScreen({
    super.key,
    required this.siUid,
    required this.company,
    required this.repository,
  });

  final String siUid;
  final ProvisioningCompany company;
  final ProvisioningRepository repository;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(company.name)),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Company Dashboard',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.flash_on_outlined),
              label: const Text('Flash new U-Link'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => AvailableUcodesScreen(
                    siUid: siUid,
                    company: company,
                    repository: repository,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.add_link),
              label: const Text('Add device to assigned U-Link'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => AssignedUlinksScreen(
                    siUid: siUid,
                    company: company,
                    repository: repository,
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

class AvailableUcodesScreen extends StatefulWidget {
  const AvailableUcodesScreen({
    super.key,
    required this.siUid,
    required this.company,
    required this.repository,
  });
  final String siUid;
  final ProvisioningCompany company;
  final ProvisioningRepository repository;

  @override
  State<AvailableUcodesScreen> createState() => _AvailableUcodesScreenState();
}

class _AvailableUcodesScreenState extends State<AvailableUcodesScreen> {
  late Future<List<ProvisioningUcode>> _ucodes = _load();
  Future<List<ProvisioningUcode>> _load() =>
      widget.repository.availableUcodesForSi(widget.siUid);

  Future<void> _confirm(ProvisioningUcode ucode) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Confirm U-Link flash'),
      content: Text(
        'Company: ${widget.company.name}\nUCode: ${ucode.ucode}\n\n'
        '${UlinkProvisioningFirmwareSupport.ucodeWriteUnavailableMessage}',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        const FilledButton(onPressed: null, child: Text('Flash U-Link')),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => _UcodeListScaffold(
    title: 'Flash new U-Link',
    future: _ucodes,
    emptyMessage: 'No available UCodes are assigned to this SI.',
    onRetry: () => setState(() => _ucodes = _load()),
    itemBuilder: (ucode) => ListTile(
      title: Text(ucode.ucode),
      subtitle: const Text('Available for a new U-Link'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _confirm(ucode),
    ),
  );
}

class AssignedUlinksScreen extends StatefulWidget {
  const AssignedUlinksScreen({
    super.key,
    required this.siUid,
    required this.company,
    required this.repository,
  });
  final String siUid;
  final ProvisioningCompany company;
  final ProvisioningRepository repository;

  @override
  State<AssignedUlinksScreen> createState() => _AssignedUlinksScreenState();
}

class _AssignedUlinksScreenState extends State<AssignedUlinksScreen> {
  late Future<List<ProvisioningUcode>> _ucodes = _load();
  Future<List<ProvisioningUcode>> _load() =>
      widget.repository.assignedUcodesForCompany(widget.company.id);

  Future<void> _select(ProvisioningUcode ucode) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Selected assigned U-Link'),
      content: Text(
        'Company: ${widget.company.name}\nUCode: ${ucode.ucode}\n\n'
        'This firmware does not provide a documented UCode advertisement '
        'format, so the app cannot safely select this U-Link for connection.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        const FilledButton(
          onPressed: null,
          child: Text('Connect selected U-Link'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => _UcodeListScaffold(
    title: 'Assigned U-Links',
    future: _ucodes,
    emptyMessage: 'No flashed U-Links are assigned to this company.',
    onRetry: () => setState(() => _ucodes = _load()),
    itemBuilder: (ucode) => ListTile(
      title: Text(ucode.ucode),
      subtitle: const Text('Assigned U-Link'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _select(ucode),
    ),
  );
}

class _UcodeListScaffold extends StatelessWidget {
  const _UcodeListScaffold({
    required this.title,
    required this.future,
    required this.emptyMessage,
    required this.onRetry,
    required this.itemBuilder,
  });
  final String title;
  final Future<List<ProvisioningUcode>> future;
  final String emptyMessage;
  final VoidCallback onRetry;
  final Widget Function(ProvisioningUcode ucode) itemBuilder;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: FutureBuilder<List<ProvisioningUcode>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: OutlinedButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          );
        }
        final ucodes = snapshot.data ?? const <ProvisioningUcode>[];
        if (ucodes.isEmpty) return Center(child: Text(emptyMessage));
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: ucodes.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (_, index) => Card(child: itemBuilder(ucodes[index])),
        );
      },
    ),
  );
}
