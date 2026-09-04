from pathlib import Path

p = Path('lib/services/vet_backend.dart')
s = p.read_text()
old = '''  Future<void> sendSupportMessage(String threadId, String message) async {
    final user = currentUser;
    if (user == null) throw StateError('You must be signed in.');
    final clean = message.trim();
    if (clean.isEmpty) return;
    await client.from('support_messages').insert({
      'thread_id': threadId,
      'sender_id': user.id,
      'sender_role': 'user',
      'message': clean,
    });
  }
'''
new = '''  String _safeSupportFileName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return cleaned.isEmpty ? 'attachment' : cleaned;
  }

  Future<Map<String, dynamic>> uploadSupportAttachment({
    required String threadId,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    final user = currentUser;
    if (user == null || !emailConfirmed) throw StateError('A verified account is required.');
    if (bytes.isEmpty || bytes.length > 25 * 1024 * 1024) {
      throw StateError('Support attachments must be between 1 byte and 25 MB.');
    }
    final safeName = _safeSupportFileName(fileName);
    final path = '$threadId/${user.id}/${DateTime.now().millisecondsSinceEpoch}_$safeName';
    await client.storage.from('support-attachments').uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(upsert: false, contentType: mimeType),
    );
    return {
      'path': path,
      'name': fileName,
      'mime': mimeType,
      'size': bytes.length,
    };
  }

  Future<Uint8List> downloadSupportAttachment(String path) async {
    return client.storage.from('support-attachments').download(path);
  }

  Future<String> signedSupportAttachmentUrl(String path) async {
    return client.storage.from('support-attachments').createSignedUrl(path, 3600);
  }

  Future<void> sendSupportMessage(
    String threadId,
    String message, {
    Map<String, dynamic>? attachment,
    String? annotatedFromMessageId,
  }) async {
    final user = currentUser;
    if (user == null) throw StateError('You must be signed in.');
    final clean = message.trim();
    if (clean.isEmpty && attachment == null) return;
    await client.from('support_messages').insert({
      'thread_id': threadId,
      'sender_id': user.id,
      'sender_role': 'user',
      'message': clean.isEmpty ? null : clean,
      if (attachment != null) 'attachment_path': attachment['path'],
      if (attachment != null) 'attachment_name': attachment['name'],
      if (attachment != null) 'attachment_mime': attachment['mime'],
      if (attachment != null) 'attachment_size_bytes': attachment['size'],
      if (annotatedFromMessageId != null) 'annotated_from_message_id': annotatedFromMessageId,
    });
  }
'''
if old not in s:
    raise SystemExit('support send method not found')
s = s.replace(old, new, 1)
p.write_text(s)
print('support backend patch applied')
