import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Native iOS incoming-call bridge for Vet AI support calls.
///
/// Normal APNs remains responsible for alerts. PushKit provides a dedicated
/// VoIP token; iOS CallKit owns the phone-style incoming-call ringtone/UI.
class VetCallKitService {
  VetCallKitService._();
  static final instance = VetCallKitService._();

  static const MethodChannel _channel = MethodChannel('vet_ai/callkit');
  final StreamController<Map<String, dynamic>> _actions =
      StreamController<Map<String, dynamic>>.broadcast();

  bool _initialized = false;
  String? _voipToken;
  final Set<String> _seenActionIds = <String>{};

  bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  bool get usesNativeCallKit => _isIOS;
  Stream<Map<String, dynamic>> get actions => _actions.stream;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    if (!_isIOS) return;

    _channel.setMethodCallHandler((call) async {
      if (call.method != 'callKitAction') return;
      final map = _map(call.arguments);
      if (map.isEmpty) return;
      _publish(map);
      final actionId = '${map['action_id'] ?? ''}';
      if (actionId.isNotEmpty) {
        try {
          await _channel.invokeMethod<void>('ackCallKitAction', {'action_id': actionId});
        } catch (_) {}
      }
    });

    // If CallKit was answered while Flutter was still waking up, native iOS
    // keeps the action until this bridge is ready.
    try {
      final pending = await _channel.invokeMapMethod<String, dynamic>(
        'consumeCallKitAction',
      );
      if (pending != null && pending.isNotEmpty) {
        _publish(Map<String, dynamic>.from(pending));
        final actionId = '${pending['action_id'] ?? ''}';
        if (actionId.isNotEmpty) {
          try {
            await _channel.invokeMethod<void>('ackCallKitAction', {'action_id': actionId});
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  Map<String, dynamic> _map(dynamic value) {
    if (value is Map<String, dynamic>) return Map<String, dynamic>.from(value);
    if (value is Map) {
      return value.map((key, value) => MapEntry('$key', value));
    }
    return <String, dynamic>{};
  }

  void _publish(Map<String, dynamic> map) {
    final id = '${map['action_id'] ?? ''}';
    if (id.isNotEmpty && !_seenActionIds.add(id)) return;
    _actions.add(map);
  }

  Future<String?> _fetchVoipTokenWithRetry() async {
    if (!_isIOS) return null;
    if (_voipToken != null && _voipToken!.isNotEmpty) return _voipToken;
    for (var attempt = 0; attempt < 10; attempt++) {
      try {
        final token = await _channel.invokeMethod<String>('getVoipToken');
        final clean = token?.trim().toLowerCase() ?? '';
        if (clean.length >= 64) {
          _voipToken = clean;
          return clean;
        }
      } catch (_) {}
      await Future<void>.delayed(Duration(milliseconds: 450 + attempt * 250));
    }
    return null;
  }

  Future<void> registerForFarm(String farmId) async {
    if (!_isIOS || farmId.trim().isEmpty) return;
    await initialize();
    final token = await _fetchVoipTokenWithRetry();
    if (token == null) return;
    try {
      await Supabase.instance.client.rpc(
        'register_voip_push_device',
        params: {
          'p_device_token': token,
          'p_environment': 'production',
          'p_farm_id': farmId,
          'p_scope': 'farm',
        },
      );
    } catch (error) {
      debugPrint('Vet AI VoIP farm registration failed: $error');
    }
  }

  Future<void> registerForAdmin() async {
    if (!_isIOS) return;
    await initialize();
    final token = await _fetchVoipTokenWithRetry();
    if (token == null) return;
    try {
      await Supabase.instance.client.rpc(
        'register_voip_push_device',
        params: {
          'p_device_token': token,
          'p_environment': 'production',
          'p_farm_id': null,
          'p_scope': 'admin',
        },
      );
    } catch (error) {
      debugPrint('Vet AI VoIP admin registration failed: $error');
    }
  }

  Future<void> unregister() async {
    if (!_isIOS || Supabase.instance.client.auth.currentUser == null) return;
    final token = _voipToken ?? await _fetchVoipTokenWithRetry();
    if (token == null || token.isEmpty) return;
    try {
      await Supabase.instance.client.rpc(
        'disable_voip_push_device',
        params: {'p_device_token': token},
      );
    } catch (_) {}
    _voipToken = null;
  }

  Future<void> endSystemCall(String callId) async {
    if (!_isIOS || callId.isEmpty) return;
    try {
      await _channel.invokeMethod<void>('endSystemCall', {'call_id': callId});
    } catch (_) {}
  }
}
