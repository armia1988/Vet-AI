import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class VetAlertNotificationService {
  VetAlertNotificationService._();
  static final VetAlertNotificationService instance = VetAlertNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> initialize() async {
    if (_ready) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      defaultPresentAlert: true,
      defaultPresentBanner: true,
      defaultPresentList: true,
      defaultPresentSound: true,
      defaultPresentBadge: true,
    );
    const settings = InitializationSettings(android: android, iOS: ios);
    await _plugin.initialize(settings: settings);
    _ready = true;
  }

  Future<void> showSensorAlert({
    required String alertId,
    required String title,
    required String body,
    String? payload,
  }) async {
    await initialize();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'vet_ai_sensor_alerts',
        'Vet AI sensor alerts',
        channelDescription: 'Real alerts generated from connected Vet AI sensors',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBanner: true,
        presentList: true,
        presentSound: true,
        presentBadge: true,
        sound: 'default',
      ),
    );
    final id = alertId.hashCode & 0x7fffffff;
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: details,
      payload: payload,
    );
  }
}
