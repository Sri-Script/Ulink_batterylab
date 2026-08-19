import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:multicast_dns/multicast_dns.dart';

import '../config/app_config.dart';
import '../config/device_contract.dart';
import '../models/device_descriptor.dart';

class DiscoveredGateway {
  const DiscoveredGateway({
    required this.descriptor,
    this.firmwareVersion,
    this.batteryCount,
  });

  final DeviceDescriptor descriptor;
  final String? firmwareVersion;
  final int? batteryCount;
}

class WifiGatewayDiscovery {
  Future<List<DiscoveredGateway>> discover() async {
    return switch (DeviceContract.kWifiDiscoveryMode) {
      WifiDiscoveryMode.mdns => _discoverMdns(),
      // TODO: SoftAP discovery via SSIDs beginning with
      // DeviceContract.wifiSsidPrefix when firmware switches modes.
      WifiDiscoveryMode.softAp => Future.value(const []),
    };
  }

  Future<List<DiscoveredGateway>> _discoverMdns() async {
    final mdns = MDnsClient();
    final client = http.Client();
    final found = <String, DiscoveredGateway>{};
    try {
      await mdns.start();
      final pointers = await mdns
          .lookup<PtrResourceRecord>(
            ResourceRecordQuery.serverPointer(DeviceContract.mdnsServiceName),
          )
          .timeout(AppConfig.connectionTimeout)
          .toList();
      for (final pointer in pointers) {
        final services = await mdns
            .lookup<SrvResourceRecord>(
              ResourceRecordQuery.service(pointer.domainName),
            )
            .timeout(AppConfig.connectionTimeout)
            .toList();
        for (final service in services) {
          final addresses = await mdns
              .lookup<IPAddressResourceRecord>(
                ResourceRecordQuery.addressIPv4(service.target),
              )
              .timeout(AppConfig.connectionTimeout)
              .toList();
          for (final address in addresses) {
            final ip = address.address.address;
            final statusUri = Uri.parse('http://$ip:${service.port}/status');
            try {
              final response = await client
                  .get(statusUri)
                  .timeout(const Duration(seconds: 3));
              final decoded = jsonDecode(response.body);
              if (response.statusCode < 200 ||
                  response.statusCode >= 300 ||
                  decoded is! Map<String, dynamic>) {
                continue;
              }
              final id = decoded['deviceId']?.toString() ?? '';
              if (!DeviceContract.deviceIdPattern.hasMatch(id)) continue;
              final descriptor = DeviceDescriptor(
                mode: TransportType.wifi,
                deviceId: id,
                gatewayId: id,
                ip: ip,
                port: service.port,
              );
              found[id] = DiscoveredGateway(
                descriptor: descriptor,
                firmwareVersion: decoded['firmwareVersion']?.toString(),
                batteryCount: (decoded['batteryCount'] as num?)?.toInt(),
              );
            } catch (_) {
              // Ignore stale/unreachable mDNS records and keep discovering.
            }
          }
        }
      }
      return found.values.toList();
    } on TimeoutException {
      return found.values.toList();
    } finally {
      mdns.stop();
      client.close();
    }
  }
}
