import 'dart:async';

import 'package:flutter/material.dart';

import '../services/callkit_service.dart';
import 'support_webrtc_call_page.dart';

/// One navigator key is mounted by either the customer app or the admin app.
/// Only one of those MaterialApps is active for a signed-in account.
final GlobalKey<NavigatorState> vetRootNavigatorKey = GlobalKey<NavigatorState>();

class VetCallKitCoordinator {
  VetCallKitCoordinator._();
  static final instance = VetCallKitCoordinator._();

  StreamSubscription<Map<String, dynamic>>? _subscription;
  String? _activeCallId;
  bool _initialized = false;

  void initialize() {
    if (_initialized) return;
    _initialized = true;
    _subscription = VetCallKitService.instance.actions.listen(_handle);
  }

  Future<void> _handle(Map<String, dynamic> action) async {
    final kind = '${action['action'] ?? ''}'.toLowerCase();
    final callId = '${action['call_id'] ?? ''}';
    if (callId.isEmpty) return;

    if (kind == 'end' || kind == 'decline') {
      if (_activeCallId == callId) {
        final nav = vetRootNavigatorKey.currentState;
        if (nav != null && nav.canPop()) nav.pop();
        _activeCallId = null;
      }
      return;
    }
    if (kind != 'answer' || _activeCallId == callId) return;

    NavigatorState? navigator;
    for (var i = 0; i < 40; i++) {
      navigator = vetRootNavigatorKey.currentState;
      if (navigator != null) break;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    if (navigator == null) return;

    final callerRole = '${action['caller_role'] ?? ''}';
    final role = callerRole == 'user' ? 'support' : 'user';
    final call = <String, dynamic>{
      'id': callId,
      'thread_id': '${action['thread_id'] ?? ''}',
      'farm_id': '${action['farm_id'] ?? ''}',
      'call_type': '${action['call_type'] ?? 'voice'}',
      'caller_role': callerRole,
      'status': 'accepted',
      'room_key': '${action['room_key'] ?? ''}',
      'caller_name': '${action['caller_name'] ?? ''}',
      'farm_name': '${action['farm_name'] ?? ''}',
    };
    if ('${call['thread_id']}'.isEmpty) return;

    _activeCallId = callId;
    try {
      await navigator.push<void>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => VetWebRtcCallPage(
            call: call,
            role: role,
            isCaller: false,
          ),
        ),
      );
    } finally {
      if (_activeCallId == callId) _activeCallId = null;
      unawaited(VetCallKitService.instance.endSystemCall(callId));
    }
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _initialized = false;
  }
}
