import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support_call_service.dart';
import 'support_webrtc_call_page.dart';

/// Bridges iOS CallKit answer actions back into the authenticated Flutter app.
///
/// PushKit/CallKit can wake Vet AI before the Flutter navigator exists.  The
/// native side therefore keeps one pending action; this coordinator consumes it
/// after Supabase/session restoration and opens the exact WebRTC support call.
class VetIncomingCallCoordinator {
  VetIncomingCallCoordinator._();
  static final instance = VetIncomingCallCoordinator._();

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>(debugLabel: 'vet-ai-root-navigator');

  static const MethodChannel _channel = MethodChannel('vet_ai/voip');

  Map<String, dynamic>? _pending;
  final Set<String> _opening = <String>{};
  bool _initialized = false;
  Timer? _retryTimer;

  Future<void> initialize() async {
    if (_initialized || kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      _initialized = true;
      return;
    }
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'callAction') return;
      final args = _map(call.arguments);
      if (args.isEmpty) return;
      _pending = args;
      _scheduleConsume();
    });
    try {
      final pending = await _channel.invokeMethod<dynamic>('getPendingCallAction');
      final map = _map(pending);
      if (map.isNotEmpty) {
        _pending = map;
        _scheduleConsume();
      }
    } catch (_) {
      // The channel becomes available as soon as the iOS Flutter engine is ready.
    }
  }

  /// Call whenever auth/root navigation becomes ready (customer or admin).
  void onAuthReady() => _scheduleConsume(immediate: true);

  Map<String, dynamic> _map(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  void _scheduleConsume({bool immediate = false}) {
    _retryTimer?.cancel();
    _retryTimer = Timer(immediate ? Duration.zero : const Duration(milliseconds: 180), () {
      unawaited(_consumePending());
    });
  }

  Future<void> _consumePending() async {
    final pending = _pending;
    if (pending == null) return;
    if ('${pending['action'] ?? ''}' != 'answer') {
      _pending = null;
      return;
    }
    final callId = '${pending['call_id'] ?? ''}'.trim();
    if (callId.isEmpty || _opening.contains(callId)) return;
    final user = Supabase.instance.client.auth.currentUser;
    final navigator = navigatorKey.currentState;
    if (user == null || navigator == null) {
      _scheduleConsume();
      return;
    }

    _opening.add(callId);
    try {
      final raw = await Supabase.instance.client
          .from('support_calls')
          .select()
          .eq('id', callId)
          .maybeSingle();
      if (raw == null) {
        _pending = null;
        return;
      }
      final call = Map<String, dynamic>.from(raw);
      final status = '${call['status'] ?? ''}';
      if (status == 'ended' || status == 'declined') {
        _pending = null;
        return;
      }
      if (status == 'ringing') {
        try {
          await VetSupportCallService.instance.accept(callId);
          call['status'] = 'accepted';
        } catch (_) {
          // Native CallKit also calls the server-side accept endpoint. If that
          // request won the race, the call is already accepted and can open.
        }
      }
      final callerRole = '${call['caller_role'] ?? 'user'}';
      final receiverRole = callerRole == 'support' ? 'user' : 'support';
      _pending = null;
      try {
        await _channel.invokeMethod<void>('clearPendingCallAction');
      } catch (_) {}
      if (navigator.mounted) {
        await navigator.push(
          MaterialPageRoute(
            builder: (_) => VetWebRtcCallPage(
              call: call,
              role: receiverRole,
              isCaller: false,
            ),
          ),
        );
      }
    } catch (_) {
      // Session/navigator may still be restoring after a cold CallKit launch.
      _scheduleConsume();
    } finally {
      _opening.remove(callId);
    }
  }
}
