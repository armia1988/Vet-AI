import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

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

  /// Current transport uses a unique Jitsi Meet room so voice/video buttons are
  /// functional on web and phone while Vet AI keeps the call lifecycle in its
  /// own protected database. This can be replaced with native TURN/WebRTC later
  /// without changing the support thread/call model.
  Future<void> openMediaRoom(Map<String, dynamic> call) async {
    final key = '${call['room_key'] ?? ''}'.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    if (key.isEmpty) throw StateError('Call room is missing.');
    final type = '${call['call_type'] ?? 'video'}';
    final uri = Uri.parse('https://meet.jit.si/VetAI-$key#config.prejoinPageEnabled=false&config.startWithVideoMuted=${type == 'voice' ? 'true' : 'false'}');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) throw StateError('Could not open call room.');
  }
}
