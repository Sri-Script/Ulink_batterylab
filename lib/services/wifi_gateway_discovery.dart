import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
      WifiDiscoveryMode.broadcast => _discoverBroadcast(),
      WifiDiscoveryMode.mdns => _discoverMdns(),
    // TODO: SoftAP discovery via SSIDs beginning with
    // DeviceContract.wifiSsidPrefix when firmware switches modes.
      WifiDiscoveryMode.softAp => Future.value(const []),
    };
  }

  /// Sends a UDP broadcast on the local subnet instead of requiring a
  /// specific IP up front. Any Ulink gateway listening on
  /// DeviceContract.broadcastDiscoveryPort replies, and each reply is
  /// confirmed against /status before being trusted.
  Future<List<DiscoveredGateway>> _discoverBroadcast() async {
    final found = <String, DiscoveredGateway>{};
    final client = http.Client();
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      socket.send(
        utf8.encode(DeviceContract.broadcastDiscoveryMessage),
        InternetAddress('255.255.255.255'),
        DeviceContract.broadcastDiscoveryPort,
      );
      final pending = <Future<void>>[];
      final subscription = socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket!.receive();
        if (datagram == null) return;
        pending.add(_verifyReply(datagram, client, found));
      });
      await Future<void>.delayed(const Duration(seconds: 3));
      await subscription.cancel();
      await Future.wait(pending);
      return found.values.toList();
    } finally {
      socket?.close();
      client.close();
    }
  }

  Future<void> _verifyReply(
      Datagram datagram,
      http.Client client,
      Map<String, DiscoveredGateway> found,
      ) async {
    try {
      final decoded = jsonDecode(utf8.decode(datagram.data));
      if (decoded is! Map<String, dynamic>) return;
      final id = decoded['deviceId']?.toString() ?? '';
      if (!DeviceContract.deviceIdPattern.hasMatch(id)) return;
      final ip = decoded['ip']?.toString() ?? datagram.address.address;
      final port = (decoded['port'] as num?)?.toInt() ?? 80;
      final response = await client
          .get(Uri.parse('http://$ip:$port/status'))
          .timeout(const Duration(seconds: 3));
      if (response.statusCode < 200 || response.statusCode >= 300) return;
      final status = jsonDecode(response.body);
      if (status is! Map<String, dynamic> ||
          status['deviceId']?.toString() != id) {
        return;
      }
      found[id] = DiscoveredGateway(
        descriptor: DeviceDescriptor(
          mode: TransportType.wifi,
          deviceId: id,
          gatewayId: id,
          ip: ip,
          port: port,
        ),
        firmwareVersion: status['firmwareVersion']?.toString(),
        batteryCount: (status['batteryCount'] as num?)?.toInt(),
      );
    } catch (_) {
      // Ignore malformed or unreachable broadcast replies.
    }
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