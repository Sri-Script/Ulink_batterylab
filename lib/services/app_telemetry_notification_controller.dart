import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'local_notification_service.dart';
import 'permission_service.dart';

/// Keeps best-effort local alerts active for the signed-in session.
class AppTelemetryNotificationController {
  AppTelemetryNotificationController({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    PermissionService? permissions,
    LocalNotificationService? notifications,
  }) : _auth = auth,
       _firestore = firestore,
       _permissions = permissions ?? PermissionService(),
       _notifications = notifications ?? LocalNotificationService.instance;

  FirebaseAuth? _auth;
  FirebaseFirestore? _firestore;
  final PermissionService _permissions;
  final LocalNotificationService _notifications;
  StreamSubscription<User?>? _authSubscription;
  final List<StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
  _dataSubscriptions = [];

  void start() {
    try {
      _auth ??= FirebaseAuth.instance;
      _firestore ??= FirebaseFirestore.instance;
    } catch (_) {
      // Firebase is optional during local widget tests and failed setup.
      return;
    }
    _authSubscription = _auth!.authStateChanges().listen((user) {
      if (user == null) {
        _stopDataListeners();
      } else {
        _beginDataListeners();
      }
    });
  }

  Future<void> _beginDataListeners() async {
    await _stopDataListeners();
    if (!await _permissions.requestNotifications()) return;
    final firestore = _firestore;
    if (firestore == null) return;

    _listenToCollection(firestore, 'telemetry', _telemetryBody);
    _listenToCollection(
      firestore,
      'live_status_snapshots',
      _statusSnapshotBody,
    );
  }

  void _listenToCollection(
    FirebaseFirestore firestore,
    String collectionId,
    String Function(Map<String, dynamic> data) bodyFor,
  ) {
    var receivedInitialSnapshot = false;
    final subscription = firestore
        .collectionGroup(collectionId)
        .snapshots()
        .listen((snapshot) {
          // Android may suspend or kill this process after enough time in the
          // background, depending on device battery-optimization settings.
          // These local alerts are therefore best-effort, not push delivery.
          if (!receivedInitialSnapshot) {
            receivedInitialSnapshot = true;
            return;
          }
          for (final change in snapshot.docChanges) {
            if (change.type != DocumentChangeType.added) continue;
            final deviceId = change.doc.reference.parent.parent?.id;
            final data = change.doc.data();
            if (deviceId == null || data == null) continue;
            _notifications.showDeviceData(
              deviceId: deviceId,
              body: bodyFor(data),
              documentPath: change.doc.reference.path,
            );
          }
        });
    _dataSubscriptions.add(subscription);
  }

  String _telemetryBody(Map<String, dynamic> data) {
    final key = data['key'];
    final value = data['value'];
    return key == null
        ? 'Value: ${value ?? 'unknown'}'
        : '$key: ${value ?? 'unknown'}';
  }

  String _statusSnapshotBody(Map<String, dynamic> data) {
    final gateway = data['gatewayId'];
    final devices = data['devices'];
    final count = devices is List ? devices.length : null;
    return '${gateway ?? 'Gateway'}: ${count ?? 'new'} device status${count == 1 ? '' : 'es'}';
  }

  Future<void> _stopDataListeners() async {
    final subscriptions = List.of(_dataSubscriptions);
    _dataSubscriptions.clear();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  }

  Future<void> dispose() async {
    await _authSubscription?.cancel();
    await _stopDataListeners();
  }
}
