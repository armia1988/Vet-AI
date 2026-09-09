import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/vet_backend.dart';
import 'support_chat_sound.dart';

class VetSupportRichService {
  VetSupportRichService._();
  static final instance = VetSupportRichService._();

  SupabaseClient get client => VetBackend.instance.client;

  Future<Map<String, dynamic>?> farm(String farmId) async {
    final rows = await client.from('farms').select().eq('id', farmId).limit(1);
    if (rows.isEmpty) return null;
    return Map<String, dynamic>.from(rows.first);
  }

  Future<String?> signedFarmPhotoUrl(String? path) async {
    final clean = path?.trim() ?? '';
    if (clean.isEmpty) return null;
    return client.storage.from('farm-profile').createSignedUrl(clean, 3600);
  }

  Future<String> uploadFarmPhoto({
    required String farmId,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
      throw StateError('Farm profile photo must be between 1 byte and 5 MB.');
    }
    final safe = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path = '$farmId/${DateTime.now().millisecondsSinceEpoch}_${safe.isEmpty ? 'profile.jpg' : safe}';
    await client.storage.from('farm-profile').uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(upsert: false, contentType: mimeType),
    );
    await client.from('farms').update({
      'profile_photo_path': path,
      'profile_photo_updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', farmId);
    return path;
  }

  Future<void> sendRichMessage({
    required String threadId,
    required String senderRole,
    required String messageType,
    String? message,
    Map<String, dynamic> metadata = const <String, dynamic>{},
  }) async {
    final user = client.auth.currentUser;
    if (user == null) throw StateError('Sign in required.');
    const allowed = {'text', 'location', 'poll', 'event', 'system'};
    if (!allowed.contains(messageType)) {
      throw ArgumentError('Unsupported support message type.');
    }
    await client.from('support_messages').insert({
      'thread_id': threadId,
      'sender_id': user.id,
      'sender_role': senderRole,
      'message_type': messageType,
      'message': (message ?? '').trim().isEmpty ? null : message!.trim(),
      'metadata': metadata,
    });
    await client.from('support_threads').update({
      'status': 'open',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', threadId);
    await VetSupportChatSound.playSend();
  }

  Future<void> markThreadRead(String threadId) async {
    if (threadId.trim().isEmpty || client.auth.currentUser == null) return;
    await client.rpc(
      'mark_support_thread_read',
      params: {'p_thread_id': threadId},
    );
  }

  Stream<List<Map<String, dynamic>>> pollVotesStream(String messageId) => client
      .from('support_poll_votes')
      .stream(primaryKey: ['message_id', 'user_id'])
      .eq('message_id', messageId)
      .order('created_at');

  Future<void> votePoll(String messageId, int optionIndex) => client.rpc(
        'cast_support_poll_vote',
        params: {'p_message_id': messageId, 'p_option_index': optionIndex},
      );
}
