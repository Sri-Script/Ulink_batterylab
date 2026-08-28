import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class LocalNotificationService {
  LocalNotificationService._();

  static final LocalNotificationService instance = LocalNotificationService._();

  static const _channel = AndroidNotificationChannel(
    'device_data',
    'Device data',
    description: 'Notifications for new Ulink device data.',
    importance: Importance.defaultImportance,
  );

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _notifications.initialize(const InitializationSettings(android: android));
    await _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_channel);
  }

  Future<void> showDeviceData({
    required String deviceId,
    required String body,
    required String documentPath,
  }) => _notifications.show(
    documentPath.hashCode & 0x7fffffff,
    'New data from $deviceId',
    body,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'device_data',
        'Device data',
        channelDescription: 'Notifications for new Ulink device data.',
        icon: '@mipmap/ic_launcher',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
    ),
  );
}
