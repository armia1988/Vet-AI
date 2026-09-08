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
  String? _adminRemoteToken;

  bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> initialize() async {
    if (_ready) return;
    if (kIsWeb) {
      _ready = true;
      return;
    }
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

  Future<String?> _fetchApnsTokenWithRetry() async {
    if (!_isIOS) return null;
    for (var attempt = 0; attempt < 8; attempt++) {
      try {
        final token = await _apnsChannel.invokeMethod<String>('getToken');
        final clean = token?.trim().toLowerCase() ?? '';
        if (clean.length >= 64) return clean;
      } catch (e) {
        debugPrint('Vet AI APNs token attempt ${attempt + 1} failed: $e');
      }
      await Future<void>.delayed(Duration(milliseconds: 700 + (attempt * 500)));
    }
    return null;
  }

  Future<void> registerRemotePushForFarm(String farmId) async {
    if (!_isIOS || farmId.trim().isEmpty) return;
    await initialize();
    try {
      final clean = await _fetchApnsTokenWithRetry();
      if (clean == null || clean.isEmpty) {
        debugPrint('Vet AI APNs token unavailable after retry window');
        return;
      }
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

  Future<void> registerRemotePushForAdmin() async {
    if (!_isIOS) return;
    await initialize();
    try {
      final clean = await _fetchApnsTokenWithRetry();
      if (clean == null || clean.isEmpty) {
        debugPrint('Vet AI admin APNs token unavailable after retry window');
        return;
      }
      await Supabase.instance.client.rpc(
        'register_admin_push_device',
        params: {
          'p_device_token': clean,
          'p_environment': 'production',
        },
      );
      _adminRemoteToken = clean;
      debugPrint('Vet AI admin APNs device registered');
    } catch (e) {
      debugPrint('Vet AI admin APNs registration failed: $e');
    }
  }

  Future<void> unregisterRemotePush() async {
    if (!_isIOS) return;
    try {
      var token = _remoteToken ?? _adminRemoteToken;
      token ??= await _fetchApnsTokenWithRetry();
      final clean = token?.trim().toLowerCase() ?? '';
      if (clean.isEmpty || Supabase.instance.client.auth.currentUser == null) return;
      if (_remoteToken != null) {
        await Supabase.instance.client.rpc(
          'disable_push_device',
          params: {'p_device_token': clean},
        );
      }
      if (_adminRemoteToken != null) {
        await Supabase.instance.client.rpc(
          'disable_admin_push_device',
          params: {'p_device_token': clean},
        );
      }
      _remoteToken = null;
      _adminRemoteToken = null;
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
    if (kIsWeb) return;
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
