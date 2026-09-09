import 'package:supabase_flutter/supabase_flutter.dart';

class VetSupportCallService {
  VetSupportCallService._();
  static final instance = VetSupportCallService._();

  SupabaseClient get client => Supabase.instance.client;

  Future<Map<String, dynamic>> startCall({
    required String threadId,
    required String callerRole,
    required String callType,
  }) async {
    final user = client.auth.currentUser;
    if (user == null) throw StateError('Sign in required.');
    if (!{'voice', 'video'}.contains(callType)) {
      throw ArgumentError('Unsupported call type.');
    }
    final row = await client.from('support_calls').insert({
      'thread_id': threadId,
      'initiated_by': user.id,
      'caller_role': callerRole,
      'call_type': callType,
      'status': 'ringing',
    }).select().single();
    return Map<String, dynamic>.from(row);
  }

  Stream<List<Map<String, dynamic>>> callsStream(String threadId) => client
      .from('support_calls')
      .stream(primaryKey: ['id'])
      .eq('thread_id', threadId)
      .order('created_at', ascending: false);

  Stream<List<Map<String, dynamic>>> signalsStream(String callId) => client
      .from('support_webrtc_signals')
      .stream(primaryKey: ['id'])
      .eq('call_id', callId)
      .order('created_at');

  Future<void> sendSignal({
    required String callId,
    required String type,
    required Map<String, dynamic> payload,
  }) async {
    final user = client.auth.currentUser;
    if (user == null) throw StateError('Sign in required.');
    if (!{'offer', 'answer', 'candidate'}.contains(type)) {
      throw ArgumentError('Unsupported WebRTC signal.');
    }
    await client.from('support_webrtc_signals').insert({
      'call_id': callId,
      'sender_id': user.id,
      'signal_type': type,
      'payload': payload,
    });
  }

  Future<Map<String, dynamic>> iceConfiguration(String callId) async {
    final value = await client.rpc(
      'get_support_webrtc_ice',
      params: {'p_call_id': callId},
    );
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return {
      'iceServers': [
        {
          'urls': ['stun:stun.l.google.com:19302'],
        },
      ],
      'turnConfigured': false,
    };
  }

  Future<void> accept(String callId) => client.from('support_calls').update({
        'status': 'accepted',
        'answered_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', callId);

  Future<void> end(String callId) => client.from('support_calls').update({
        'status': 'ended',
        'ended_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', callId);

  Future<void> decline(String callId) => client.from('support_calls').update({
        'status': 'declined',
        'ended_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', callId);
}
