import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class VetAlertNotificationService {
  VetAlertNotificationService._();
  static final VetAlertNotificationService instance = VetAlertNotificationService._();

  static const MethodChannel _apnsChannel = MethodChannel('vet_ai/apns');
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  String? _remoteToken;

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

  Future<void> registerRemotePushForFarm(String farmId) async {
    if (!Platform.isIOS || farmId.trim().isEmpty) return;
    await initialize();
    try {
      final token = await _apnsChannel.invokeMethod<String>('getToken');
      final clean = token?.trim().toLowerCase() ?? '';
      if (clean.isEmpty) return;
      await Supabase.instance.client.rpc(
        'register_push_device',
        params: {
          'p_farm_id': farmId,
          'p_device_token': clean,
          'p_environment': 'production',
        },
      );
      _remoteToken = clean;
      debugPrint('Vet AI APNs device registered for farm $farmId');
    } catch (e) {
      debugPrint('Vet AI APNs registration failed: $e');
    }
  }

  Future<void> unregisterRemotePush() async {
    if (!Platform.isIOS) return;
    try {
      var token = _remoteToken;
      token ??= await _apnsChannel.invokeMethod<String>('getToken');
      final clean = token?.trim().toLowerCase() ?? '';
      if (clean.isEmpty || Supabase.instance.client.auth.currentUser == null) return;
      await Supabase.instance.client.rpc(
        'disable_push_device',
        params: {'p_device_token': clean},
      );
      _remoteToken = null;
    } catch (e) {
      debugPrint('Vet AI APNs unregister failed: $e');
    }
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
