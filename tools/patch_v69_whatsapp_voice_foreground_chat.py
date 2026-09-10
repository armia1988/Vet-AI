from pathlib import Path


def add_import(text: str, anchor: str, line: str, label: str) -> str:
    if line in text:
        return text
    if anchor not in text:
        raise SystemExit(f'V69: {label} import anchor missing')
    return text.replace(anchor, anchor + line, 1)


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    if old not in text:
        raise SystemExit(f'V69: {label} anchor missing')
    return text.replace(old, new, 1)


# ---------------------------------------------------------------------------
# Dependency: cross-platform microphone recording. 6.2.1 supports iOS and web
# while remaining compatible with the project's Dart SDK floor.
# ---------------------------------------------------------------------------
pubspec = Path('pubspec.yaml')
ps = pubspec.read_text(encoding='utf-8')
if '  record: ^6.2.1\n' not in ps:
    anchor = '  audioplayers: ^6.8.1\n'
    if anchor not in ps:
        raise SystemExit('V69: pubspec audioplayers anchor missing')
    ps = ps.replace(anchor, anchor + '  record: ^6.2.1\n', 1)
pubspec.write_text(ps, encoding='utf-8')


# ---------------------------------------------------------------------------
# Persistent chat sound preference + one-shot dedupe. The preference is cached
# before playback so Safari send audio still begins inside the user gesture.
# ---------------------------------------------------------------------------
Path('lib/support/support_chat_sound.dart').write_text(r'''import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class VetSupportChatSound {
  VetSupportChatSound._();

  static final AudioPlayer _sendPlayer = AudioPlayer();
  static final AudioPlayer _receivePlayer = AudioPlayer();
  static const _prefKey = 'vet_ai_support_chat_muted';
  static bool _unlocked = false;
  static bool _muted = false;
  static bool _initialized = false;
  static String? _lastReceiveMessageId;
  static DateTime? _lastReceiveAt;

  static bool get muted => _muted;

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _muted = prefs.getBool(_prefKey) ?? false;
    } catch (_) {}
  }

  static Future<void> setMuted(bool value) async {
    _muted = value;
    _initialized = true;
    if (value) {
      try { await _sendPlayer.stop(); } catch (_) {}
      try { await _receivePlayer.stop(); } catch (_) {}
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, value);
    } catch (_) {}
  }

  static Future<void> unlock() async {
    if (_muted || _unlocked) return;
    _unlocked = true;
    try {
      await _sendPlayer.setReleaseMode(ReleaseMode.stop);
      await _receivePlayer.setReleaseMode(ReleaseMode.stop);
      await _sendPlayer.play(AssetSource('audio/vet_ai_chat_send.wav'), volume: 0.0);
      await _sendPlayer.stop();
    } catch (_) {
      _unlocked = false;
    }
  }

  static Future<void> playSend() async {
    if (_muted) return;
    try {
      _unlocked = true;
      await _sendPlayer.stop();
      await _sendPlayer.setReleaseMode(ReleaseMode.stop);
      await _sendPlayer.play(AssetSource('audio/vet_ai_chat_send.wav'), volume: 0.62);
    } catch (_) {}
  }

  static Future<void> playReceive() => playReceiveFor('');

  static Future<void> playReceiveFor(String messageId) async {
    if (_muted) return;
    final now = DateTime.now();
    if (messageId.isNotEmpty &&
        _lastReceiveMessageId == messageId &&
        _lastReceiveAt != null &&
        now.difference(_lastReceiveAt!) < const Duration(seconds: 5)) {
      return;
    }
    _lastReceiveMessageId = messageId.isEmpty ? _lastReceiveMessageId : messageId;
    _lastReceiveAt = now;
    try {
      await _receivePlayer.stop();
      await _receivePlayer.setReleaseMode(ReleaseMode.stop);
      await _receivePlayer.play(AssetSource('audio/vet_ai_chat_receive.wav'), volume: 0.54);
    } catch (_) {}
  }
}
''', encoding='utf-8')


# ---------------------------------------------------------------------------
# Foreground in-chat notification card. This is deliberately app-owned rather
# than an OS notification, so it also works while the chat itself is visible.
# ---------------------------------------------------------------------------
Path('lib/support/support_chat_notice.dart').write_text(r'''import 'dart:async';

import 'package:flutter/material.dart';

class VetSupportChatNotice {
  VetSupportChatNotice._();

  static OverlayEntry? _entry;
  static Timer? _timer;
  static String? _lastMessageId;

  static String preview(
    Map<String, dynamic> row, {
    required String newMessage,
    required String voiceMessage,
    required String photo,
    required String attachment,
  }) {
    final text = '${row['message'] ?? ''}'.trim();
    if (text.isNotEmpty) return text;
    final mime = '${row['attachment_mime'] ?? ''}'.toLowerCase();
    if (mime.startsWith('audio/')) return voiceMessage;
    if (mime.startsWith('image/')) return photo;
    if ('${row['attachment_path'] ?? ''}'.isNotEmpty) return attachment;
    return newMessage;
  }

  static void show(
    BuildContext context, {
    required String messageId,
    required String title,
    required String preview,
  }) {
    if (messageId.isNotEmpty && _lastMessageId == messageId) return;
    _lastMessageId = messageId;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    _timer?.cancel();
    _entry?.remove();
    _entry = OverlayEntry(
      builder: (overlayContext) {
        final top = MediaQuery.paddingOf(overlayContext).top + 8;
        return Positioned(
          top: top,
          left: 10,
          right: 10,
          child: IgnorePointer(
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xF2111B21),
                  borderRadius: BorderRadius.circular(17),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .20),
                      blurRadius: 18,
                      offset: const Offset(0, 7),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const CircleAvatar(
                      radius: 19,
                      backgroundColor: Color(0xFFD9FDD3),
                      child: Icon(Icons.chat_rounded, color: Color(0xFF00A884), size: 21),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            preview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Color(0xFFD5D9DB), fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(_entry!);
    _timer = Timer(const Duration(milliseconds: 2200), () {
      _entry?.remove();
      _entry = null;
    });
  }
}
''', encoding='utf-8')


# ---------------------------------------------------------------------------
# Real voice notes: record PCM from microphone as a stream on iOS/web, wrap it
# as WAV, upload through the existing private support-attachments bucket, and
# render/play it directly inside the conversation.
# ---------------------------------------------------------------------------
Path('lib/support/support_voice_note.dart').write_text(r'''import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:record/record.dart';

import '../services/vet_backend.dart';

class VetSupportVoiceClip {
  const VetSupportVoiceClip(this.bytes, this.duration);
  final Uint8List bytes;
  final Duration duration;
}

class VetSupportVoiceRecorder {
  final AudioRecorder _recorder = AudioRecorder();
  final List<Uint8List> _chunks = <Uint8List>[];
  StreamSubscription<Uint8List>? _subscription;
  Completer<void>? _streamDone;
  DateTime? _startedAt;
  bool _recording = false;

  bool get recording => _recording;

  Future<void> start() async {
    if (_recording) return;
    final allowed = await _recorder.hasPermission();
    if (!allowed) throw StateError('Microphone permission denied');
    _chunks.clear();
    _streamDone = Completer<void>();
    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        autoGain: true,
        echoCancel: true,
        noiseSuppress: true,
      ),
    );
    _subscription = stream.listen(
      (chunk) {
        if (chunk.isNotEmpty) _chunks.add(Uint8List.fromList(chunk));
      },
      onDone: () {
        if (_streamDone?.isCompleted == false) _streamDone?.complete();
      },
      onError: (Object error, StackTrace stack) {
        if (_streamDone?.isCompleted == false) _streamDone?.complete();
      },
      cancelOnError: false,
    );
    _startedAt = DateTime.now();
    _recording = true;
  }

  Future<VetSupportVoiceClip?> stop() async {
    if (!_recording) return null;
    final started = _startedAt ?? DateTime.now();
    _recording = false;
    await _recorder.stop();
    try {
      await _streamDone?.future.timeout(const Duration(milliseconds: 900));
    } catch (_) {}
    await _subscription?.cancel();
    _subscription = null;
    final rawLength = _chunks.fold<int>(0, (sum, e) => sum + e.length);
    if (rawLength < 6400) {
      _chunks.clear();
      return null;
    }
    final raw = Uint8List(rawLength);
    var offset = 0;
    for (final chunk in _chunks) {
      raw.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    _chunks.clear();
    final elapsed = DateTime.now().difference(started);
    final sampleDuration = Duration(milliseconds: ((rawLength / 2 / 16000) * 1000).round());
    final duration = sampleDuration.inMilliseconds > 0 ? sampleDuration : elapsed;
    return VetSupportVoiceClip(_wav(raw), duration);
  }

  Future<void> cancel() async {
    if (_recording) {
      _recording = false;
      try { await _recorder.cancel(); } catch (_) {}
    }
    await _subscription?.cancel();
    _subscription = null;
    _chunks.clear();
  }

  void dispose() {
    unawaited(cancel());
    unawaited(_recorder.dispose());
  }

  static Uint8List _wav(Uint8List pcm) {
    const sampleRate = 16000;
    const channels = 1;
    const bits = 16;
    final out = ByteData(44 + pcm.length);
    void ascii(int at, String s) {
      for (var i = 0; i < s.length; i++) out.setUint8(at + i, s.codeUnitAt(i));
    }
    ascii(0, 'RIFF');
    out.setUint32(4, 36 + pcm.length, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    out.setUint32(16, 16, Endian.little);
    out.setUint16(20, 1, Endian.little);
    out.setUint16(22, channels, Endian.little);
    out.setUint32(24, sampleRate, Endian.little);
    out.setUint32(28, sampleRate * channels * bits ~/ 8, Endian.little);
    out.setUint16(32, channels * bits ~/ 8, Endian.little);
    out.setUint16(34, bits, Endian.little);
    ascii(36, 'data');
    out.setUint32(40, pcm.length, Endian.little);
    out.buffer.asUint8List().setRange(44, 44 + pcm.length, pcm);
    return out.buffer.asUint8List();
  }
}

class VetSupportVoiceService {
  VetSupportVoiceService._();

  static Future<void> send({
    required String threadId,
    required String senderRole,
    required VetSupportVoiceClip clip,
  }) async {
    if (senderRole != 'user' && senderRole != 'support') {
      throw ArgumentError('Invalid support sender role');
    }
    final backend = VetBackend.instance;
    final user = backend.currentUser;
    if (user == null) throw StateError('Sign in required');
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final attachment = await backend.uploadSupportAttachment(
      threadId: threadId,
      bytes: clip.bytes,
      fileName: 'voice_$stamp.wav',
      mimeType: 'audio/wav',
    );
    await backend.client.from('support_messages').insert({
      'thread_id': threadId,
      'sender_id': user.id,
      'sender_role': senderRole,
      'message_type': 'audio',
      'attachment_path': attachment['path'],
      'attachment_name': attachment['name'],
      'attachment_mime': attachment['mime'],
      'attachment_size_bytes': attachment['size'],
      'metadata': {'duration_ms': clip.duration.inMilliseconds},
    });
    await backend.client.from('support_threads').update({
      'status': 'open',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', threadId);
  }
}

class VetSupportVoiceNote extends StatefulWidget {
  const VetSupportVoiceNote({super.key, required this.row, required this.mine});
  final Map<String, dynamic> row;
  final bool mine;

  @override
  State<VetSupportVoiceNote> createState() => _VetSupportVoiceNoteState();
}

class _VetSupportVoiceNoteState extends State<VetSupportVoiceNote> {
  final AudioPlayer player = AudioPlayer();
  Uint8List? bytes;
  bool loading = false;
  bool playing = false;
  StreamSubscription<void>? completeSub;

  @override
  void initState() {
    super.initState();
    completeSub = player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => playing = false);
      bytes = null;
    });
  }

  int get durationMs {
    final meta = widget.row['metadata'];
    if (meta is Map && meta['duration_ms'] is num) {
      return (meta['duration_ms'] as num).toInt();
    }
    return 0;
  }

  String get durationLabel {
    final seconds = (durationMs / 1000).round();
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Future<void> toggle() async {
    if (loading) return;
    if (playing) {
      await player.pause();
      if (mounted) setState(() => playing = false);
      return;
    }
    setState(() => loading = true);
    try {
      bytes ??= await VetBackend.instance.downloadSupportAttachment('${widget.row['attachment_path']}');
      await player.play(BytesSource(bytes!));
      if (mounted) setState(() => playing = true);
    } catch (_) {
      if (mounted) setState(() => playing = false);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    completeSub?.cancel();
    unawaited(player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const pattern = <double>[9, 17, 12, 23, 14, 19, 8, 21, 12, 17, 10, 24, 13, 18, 9, 20, 11, 16];
    return SizedBox(
      width: 245,
      child: Row(
        children: [
          InkWell(
            onTap: toggle,
            customBorder: const CircleBorder(),
            child: CircleAvatar(
              radius: 21,
              backgroundColor: const Color(0xFF00A884),
              child: loading
                  ? const SizedBox.square(dimension: 17, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 28),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 27,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      for (final h in pattern)
                        Expanded(
                          child: Align(
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 1),
                              height: h,
                              decoration: BoxDecoration(
                                color: const Color(0xFF667781).withValues(alpha: .72),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(durationLabel, style: const TextStyle(fontSize: 10.5, color: Color(0xFF667781))),
              ],
            ),
          ),
          const SizedBox(width: 7),
          const Icon(Icons.mic_rounded, size: 18, color: Color(0xFF00A884)),
        ],
      ),
    );
  }
}
''', encoding='utf-8')


# ---------------------------------------------------------------------------
# Customer/app support chat.
# ---------------------------------------------------------------------------
p = Path('lib/support/support_chat_v6.dart')
s = p.read_text(encoding='utf-8')
s = add_import(s, "import 'support_chat_sound.dart';\n", "import 'support_chat_notice.dart';\nimport 'support_voice_note.dart';\n", 'customer V69 helpers')

field_anchor = '  final composerFocus = FocusNode();\n'
if 'final VetSupportVoiceRecorder voiceRecorder' not in s:
    if field_anchor not in s:
        raise SystemExit('V69: customer composer focus field missing')
    s = s.replace(
        field_anchor,
        field_anchor
        + '  final VetSupportVoiceRecorder voiceRecorder = VetSupportVoiceRecorder();\n'
        + '  Timer? voiceTimer;\n'
        + '  bool recordingVoice = false;\n'
        + '  int voiceSeconds = 0;\n',
        1,
    )

init_anchor = """  void initState() {
    super.initState();
"""
if 'VetSupportChatSound.initialize();' not in s:
    s = replace_once(
        s,
        init_anchor,
        init_anchor + '    unawaited(VetSupportChatSound.initialize());\n',
        'customer sound initialize',
    )

if 'Future<void> _beginVoiceRecording() async {' not in s:
    marker = '  Future<void> _sendText() async {\n'
    if marker not in s:
        raise SystemExit('V69: customer send marker missing')
    methods = r'''  Future<void> _beginVoiceRecording() async {
    if (threadId == null || sending || recordingVoice || message.text.trim().isNotEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      await voiceRecorder.start();
      if (!mounted) {
        await voiceRecorder.cancel();
        return;
      }
      setState(() {
        recordingVoice = true;
        voiceSeconds = 0;
      });
      voiceTimer?.cancel();
      voiceTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || !recordingVoice) return;
        setState(() => voiceSeconds += 1);
        if (voiceSeconds >= 120) unawaited(_finishVoiceRecording());
      });
    } catch (_) {
      if (mounted) _error(_t(context, 'Microphone access is needed to record a voice message.', 'لازم تسمح للميكروفون علشان تسجل رسالة صوتية.', 'Microfoontoegang is nodig om een spraakbericht op te nemen.'));
    }
  }

  Future<void> _finishVoiceRecording() async {
    if (!recordingVoice || sending || threadId == null) return;
    voiceTimer?.cancel();
    voiceTimer = null;
    setState(() {
      recordingVoice = false;
      sending = true;
    });
    unawaited(VetSupportChatSound.playSend());
    try {
      final clip = await voiceRecorder.stop();
      if (clip == null) return;
      await VetSupportVoiceService.send(threadId: threadId!, senderRole: 'user', clip: clip);
      _scrollToNewest(animated: false);
    } catch (_) {
      if (mounted) _error(_t(context, 'Voice message could not be sent.', 'الرسالة الصوتية مااتبعتتش. جرّب تاني.', 'Spraakbericht kon niet worden verzonden.'));
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> _cancelVoiceRecording() async {
    voiceTimer?.cancel();
    voiceTimer = null;
    await voiceRecorder.cancel();
    if (mounted) setState(() {
      recordingVoice = false;
      voiceSeconds = 0;
    });
  }

  Future<void> _toggleVoiceRecording() async {
    if (recordingVoice) {
      await _finishVoiceRecording();
    } else {
      await _beginVoiceRecording();
    }
  }

'''
    s = s.replace(marker, methods + marker, 1)

old_receive = """                        final incoming = rows.skip(start).any((row) => row['sender_role'] == 'support');
                        if (incoming) unawaited(VetSupportChatSound.playReceive());
"""
new_receive = """                        final incomingRows = rows.skip(start).where((row) => row['sender_role'] == 'support').toList(growable: false);
                        if (incomingRows.isNotEmpty) {
                          final newest = incomingRows.last;
                          final messageId = '${newest['id'] ?? ''}';
                          unawaited(VetSupportChatSound.playReceiveFor(messageId));
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!mounted) return;
                            VetSupportChatNotice.show(
                              context,
                              messageId: messageId,
                              title: _t(context, 'Vet AI Support', 'دعم Vet AI', 'Vet AI Support'),
                              preview: VetSupportChatNotice.preview(
                                newest,
                                newMessage: _t(context, 'New message', 'رسالة جديدة', 'Nieuw bericht'),
                                voiceMessage: _t(context, 'Voice message', 'رسالة صوتية', 'Spraakbericht'),
                                photo: _t(context, 'Photo', 'صورة', 'Foto'),
                                attachment: _t(context, 'Attachment', 'مرفق', 'Bijlage'),
                              ),
                            );
                          });
                        }
"""
s = replace_once(s, old_receive, new_receive, 'customer foreground receive notice')

# Sound toggle in the app bar.
state_start = s.find('class _V6SupportScreenState')
state_end = s.find('\nclass SupportMessageBubble', state_start)
segment = s[state_start:state_end]
if 'vet_ai_support_chat_muted' not in segment and 'VetSupportChatSound.muted' not in segment:
    target = """        ]),
      ),
      body: threadId == null
"""
    replacement = """        ]),
        actions: [
          IconButton(
            tooltip: VetSupportChatSound.muted
                ? _t(context, 'Turn chat sound on', 'تشغيل صوت الشات', 'Chatgeluid aan')
                : _t(context, 'Mute chat sound', 'كتم صوت الشات', 'Chatgeluid dempen'),
            onPressed: () async {
              await VetSupportChatSound.setMuted(!VetSupportChatSound.muted);
              if (mounted) setState(() {});
            },
            icon: Icon(VetSupportChatSound.muted ? Icons.volume_off_rounded : Icons.volume_up_rounded),
          ),
        ],
      ),
      body: threadId == null
"""
    if target not in segment:
        raise SystemExit('V69: customer AppBar target missing')
    segment = segment.replace(target, replacement, 1)
    s = s[:state_start] + segment + s[state_end:]

# WhatsApp-like camera + mic/send action. GestureDetector does not take text
# focus, which also prevents iOS Safari from dropping the keyboard on Send.
old_customer_action = """                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: sending ? null : _sendText,
                      icon: sending
                          ? const SizedBox.square(dimension: 21, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.send_rounded, size: 29),
                    ),
"""
new_customer_action = """                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: _t(context, 'Camera', 'الكاميرا', 'Camera'),
                      onPressed: sending || recordingVoice ? null : () => _pickImage(ImageSource.camera),
                      icon: const Icon(Icons.photo_camera_outlined, size: 28),
                    ),
                    const SizedBox(width: 3),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: message,
                      builder: (context, value, _) {
                        final hasText = value.text.trim().isNotEmpty;
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapDown: sending || recordingVoice || !hasText
                              ? null
                              : (_) {
                                  if (composerFocus.canRequestFocus) composerFocus.requestFocus();
                                },
                          onTap: sending
                              ? null
                              : () {
                                  if (hasText) {
                                    if (composerFocus.canRequestFocus) composerFocus.requestFocus();
                                    unawaited(_sendText());
                                  } else {
                                    unawaited(_toggleVoiceRecording());
                                  }
                                },
                          onLongPressStart: sending || hasText || recordingVoice
                              ? null
                              : (_) => unawaited(_beginVoiceRecording()),
                          onLongPressEnd: !recordingVoice
                              ? null
                              : (_) => unawaited(_finishVoiceRecording()),
                          child: CircleAvatar(
                            radius: 24,
                            backgroundColor: recordingVoice ? const Color(0xFFE53935) : VetColors.primary,
                            child: sending
                                ? const SizedBox.square(dimension: 19, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : Icon(
                                    hasText
                                        ? Icons.send_rounded
                                        : recordingVoice
                                            ? Icons.stop_rounded
                                            : Icons.mic_rounded,
                                    color: Colors.white,
                                    size: 27,
                                  ),
                          ),
                        );
                      },
                    ),
"""
s = replace_once(s, old_customer_action, new_customer_action, 'customer camera/mic action')

old_plus = """                    IconButton.filledTonal(
                      onPressed: sending ? null : _chooseAttachment,
                      style: IconButton.styleFrom(backgroundColor: VetColors.surface3),
                      icon: const Icon(Icons.add_rounded, size: 31, color: VetColors.history),
                    ),
"""
new_plus = """                    IconButton(
                      onPressed: sending || recordingVoice ? null : _chooseAttachment,
                      icon: const Icon(Icons.add_rounded, size: 31, color: VetColors.history),
                    ),
"""
s = replace_once(s, old_plus, new_plus, 'customer WhatsApp plus')

old_deco = """                        decoration: InputDecoration(
                          hintText: _t(context, 'Write a message…', 'اكتب رسالة…', 'Schrijf een bericht…'),
                          prefixIcon: const Icon(Icons.chat_bubble_outline_rounded, size: 26),
                        ),
"""
new_deco = """                        decoration: InputDecoration(
                          hintText: recordingVoice
                              ? _t(context, 'Recording voice… tap red button to send', 'جاري تسجيل الصوت… اضغط الزر الأحمر للإرسال', 'Spraak wordt opgenomen… tik op rood om te verzenden')
                              : _t(context, 'Write a message…', 'اكتب رسالة…', 'Schrijf een bericht…'),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(27), borderSide: BorderSide.none),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(27), borderSide: BorderSide.none),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(27), borderSide: BorderSide.none),
                        ),
"""
s = replace_once(s, old_deco, new_deco, 'customer WhatsApp field')

# Voice-note rendering inside customer bubbles.
old_audio_vars = """    final isImage = path != null && mime.startsWith('image/');

    return Align(
"""
new_audio_vars = """    final isImage = path != null && mime.startsWith('image/');
    final isAudio = path != null && mime.startsWith('audio/');

    return Align(
"""
s = replace_once(s, old_audio_vars, new_audio_vars, 'customer audio type')
s = replace_once(
    s,
    """          if (isImage)
            _PrivateImage(path: path, onTap: onAnnotate),
          if (path != null && !isImage)
""",
    """          if (isImage)
            _PrivateImage(path: path, onTap: onAnnotate),
          if (isAudio)
            VetSupportVoiceNote(row: row, mine: mine),
          if (path != null && !isImage && !isAudio)
""",
    'customer voice bubble',
)

if 'voiceRecorder.dispose();' not in s:
    dispose_anchor = '    composerFocus.dispose();\n'
    if dispose_anchor not in s:
        raise SystemExit('V69: customer dispose focus anchor missing')
    s = s.replace(
        dispose_anchor,
        dispose_anchor + '    voiceTimer?.cancel();\n    voiceRecorder.dispose();\n',
        1,
    )

p.write_text(s, encoding='utf-8')


# ---------------------------------------------------------------------------
# Support/admin browser chat.
# ---------------------------------------------------------------------------
p = Path('lib/support/support_agent_thread_v2.dart')
s = p.read_text(encoding='utf-8')
s = add_import(s, "import 'package:flutter/services.dart';\n", "import 'package:image_picker/image_picker.dart';\n", 'agent image picker')
s = add_import(s, "import 'support_chat_sound.dart';\n", "import 'support_chat_notice.dart';\nimport 'support_voice_note.dart';\n", 'agent V69 helpers')

field_anchor = '  final composerFocus = FocusNode();\n'
if 'final VetSupportVoiceRecorder voiceRecorder' not in s:
    if field_anchor not in s:
        raise SystemExit('V69: agent composer focus field missing')
    s = s.replace(
        field_anchor,
        field_anchor
        + '  final VetSupportVoiceRecorder voiceRecorder = VetSupportVoiceRecorder();\n'
        + '  Timer? voiceTimer;\n'
        + '  bool recordingVoice = false;\n'
        + '  int voiceSeconds = 0;\n',
        1,
    )

if 'VetSupportChatSound.initialize();' not in s:
    marker = '  @override\n  void dispose() {\n'
    if marker not in s:
        raise SystemExit('V69: agent dispose marker missing')
    init = """  @override
  void initState() {
    super.initState();
    unawaited(VetSupportChatSound.initialize());
  }

"""
    s = s.replace(marker, init + marker, 1)

if 'Future<void> _beginVoiceRecording() async {' not in s:
    marker = '  Future<void> _send() async {\n'
    if marker not in s:
        raise SystemExit('V69: agent send marker missing')
    methods = r'''  Future<void> _beginVoiceRecording() async {
    if (sending || recordingVoice || message.text.trim().isNotEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      await voiceRecorder.start();
      if (!mounted) {
        await voiceRecorder.cancel();
        return;
      }
      setState(() {
        recordingVoice = true;
        voiceSeconds = 0;
      });
      voiceTimer?.cancel();
      voiceTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || !recordingVoice) return;
        setState(() => voiceSeconds += 1);
        if (voiceSeconds >= 120) unawaited(_finishVoiceRecording());
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_wt(context, 'Microphone access is needed to record a voice message.', 'لازم تسمح للميكروفون علشان تسجل رسالة صوتية.', 'Microfoontoegang is nodig om een spraakbericht op te nemen.'))),
        );
      }
    }
  }

  Future<void> _finishVoiceRecording() async {
    if (!recordingVoice || sending) return;
    voiceTimer?.cancel();
    voiceTimer = null;
    setState(() {
      recordingVoice = false;
      sending = true;
    });
    unawaited(VetSupportChatSound.playSend());
    try {
      final clip = await voiceRecorder.stop();
      if (clip == null) return;
      await VetSupportVoiceService.send(threadId: threadId, senderRole: 'support', clip: clip);
      _toBottom(animated: false);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_wt(context, 'Voice message could not be sent.', 'الرسالة الصوتية مااتبعتتش.', 'Spraakbericht kon niet worden verzonden.'))),
        );
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> _toggleVoiceRecording() async {
    if (recordingVoice) {
      await _finishVoiceRecording();
    } else {
      await _beginVoiceRecording();
    }
  }

  Future<void> _sendCameraPhoto() async {
    if (sending || recordingVoice) return;
    final picked = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 94, maxWidth: 2600);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (bytes.isEmpty) return;
    setState(() => sending = true);
    try {
      final upload = await backend.uploadSupportAttachment(
        threadId: threadId,
        bytes: bytes,
        fileName: picked.name.isEmpty ? 'camera.jpg' : picked.name,
        mimeType: 'image/jpeg',
      );
      final user = backend.currentUser;
      if (user == null) throw StateError('Support login required');
      await backend.client.from('support_messages').insert({
        'thread_id': threadId,
        'sender_id': user.id,
        'sender_role': 'support',
        'attachment_path': upload['path'],
        'attachment_name': upload['name'],
        'attachment_mime': upload['mime'],
        'attachment_size_bytes': upload['size'],
      });
      await backend.client.from('support_threads').update({
        'status': 'open',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', threadId);
      _toBottom(animated: false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_wt(context, 'Photo could not be sent.', 'الصورة مااتبعتتش.', 'Foto kon niet worden verzonden.')} $e')),
        );
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

'''
    s = s.replace(marker, methods + marker, 1)

old_receive = """                      final incoming = rows.skip(start).any((row) => row['sender_role'] == 'user');
                      if (incoming) unawaited(VetSupportChatSound.playReceive());
"""
new_receive = """                      final incomingRows = rows.skip(start).where((row) => row['sender_role'] == 'user').toList(growable: false);
                      if (incomingRows.isNotEmpty) {
                        final newest = incomingRows.last;
                        final messageId = '${newest['id'] ?? ''}';
                        unawaited(VetSupportChatSound.playReceiveFor(messageId));
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          VetSupportChatNotice.show(
                            context,
                            messageId: messageId,
                            title: _wt(context, 'Customer', 'العميل', 'Klant'),
                            preview: VetSupportChatNotice.preview(
                              newest,
                              newMessage: _wt(context, 'New message', 'رسالة جديدة', 'Nieuw bericht'),
                              voiceMessage: _wt(context, 'Voice message', 'رسالة صوتية', 'Spraakbericht'),
                              photo: _wt(context, 'Photo', 'صورة', 'Foto'),
                              attachment: _wt(context, 'Attachment', 'مرفق', 'Bijlage'),
                            ),
                          );
                        });
                      }
"""
s = replace_once(s, old_receive, new_receive, 'agent foreground receive notice')

# Add persistent sound toggle before call controls.
old_actions = """        actions: [
          IconButton(
            tooltip: _wt(context, 'Video call', 'مكالمة فيديو', 'Videogesprek'),
"""
new_actions = """        actions: [
          IconButton(
            tooltip: VetSupportChatSound.muted
                ? _wt(context, 'Turn chat sound on', 'تشغيل صوت الشات', 'Chatgeluid aan')
                : _wt(context, 'Mute chat sound', 'كتم صوت الشات', 'Chatgeluid dempen'),
            onPressed: () async {
              await VetSupportChatSound.setMuted(!VetSupportChatSound.muted);
              if (mounted) setState(() {});
            },
            icon: Icon(VetSupportChatSound.muted ? Icons.volume_off_rounded : Icons.volume_up_rounded),
          ),
          IconButton(
            tooltip: _wt(context, 'Video call', 'مكالمة فيديو', 'Videogesprek'),
"""
s = replace_once(s, old_actions, new_actions, 'agent sound toggle')

# Add camera and replace the focus-stealing IconButton send control with a pure
# gesture surface. The persistent FocusNode from V65 then stays attached while
# a text message is sent, fixing the browser keyboard down/up flash.
old_agent_action = """                  const SizedBox(width: 7),
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: _waGreen,
                    child: IconButton(
                      onPressed: sending ? null : _send,
                      icon: sending
                          ? const SizedBox.square(
                              dimension: 19,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.send_rounded,
                              color: Colors.white,
                            ),
                    ),
                  ),
"""
new_agent_action = """                  const SizedBox(width: 3),
                  IconButton(
                    tooltip: _wt(context, 'Camera', 'الكاميرا', 'Camera'),
                    onPressed: sending || recordingVoice ? null : _sendCameraPhoto,
                    icon: const Icon(Icons.photo_camera_outlined, size: 28),
                  ),
                  const SizedBox(width: 2),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: message,
                    builder: (context, value, _) {
                      final hasText = value.text.trim().isNotEmpty;
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: sending || recordingVoice || !hasText
                            ? null
                            : (_) {
                                if (composerFocus.canRequestFocus) composerFocus.requestFocus();
                              },
                        onTap: sending
                            ? null
                            : () {
                                if (hasText) {
                                  if (composerFocus.canRequestFocus) composerFocus.requestFocus();
                                  unawaited(_send());
                                } else {
                                  unawaited(_toggleVoiceRecording());
                                }
                              },
                        onLongPressStart: sending || hasText || recordingVoice
                            ? null
                            : (_) => unawaited(_beginVoiceRecording()),
                        onLongPressEnd: !recordingVoice
                            ? null
                            : (_) => unawaited(_finishVoiceRecording()),
                        child: CircleAvatar(
                          radius: 24,
                          backgroundColor: recordingVoice ? const Color(0xFFE53935) : _waGreen,
                          child: sending
                              ? const SizedBox.square(
                                  dimension: 19,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : Icon(
                                  hasText
                                      ? Icons.send_rounded
                                      : recordingVoice
                                          ? Icons.stop_rounded
                                          : Icons.mic_rounded,
                                  color: Colors.white,
                                  size: 27,
                                ),
                        ),
                      );
                    },
                  ),
"""
s = replace_once(s, old_agent_action, new_agent_action, 'agent camera/mic action')

# Voice-note rendering in admin WhatsApp-style bubbles.
old_preview_vars = """    final image = mime.startsWith('image/');

    if (image) {
"""
new_preview_vars = """    final image = mime.startsWith('image/');
    final audio = mime.startsWith('audio/');

    if (audio) {
      return VetSupportVoiceNote(
        row: widget.row,
        mine: widget.row['sender_role'] == 'support',
      );
    }

    if (image) {
"""
s = replace_once(s, old_preview_vars, new_preview_vars, 'agent voice preview')

if 'voiceRecorder.dispose();' not in s:
    dispose_anchor = '    composerFocus.dispose();\n'
    if dispose_anchor not in s:
        raise SystemExit('V69: agent dispose focus anchor missing')
    s = s.replace(
        dispose_anchor,
        dispose_anchor + '    voiceTimer?.cancel();\n    voiceRecorder.dispose();\n',
        1,
    )

p.write_text(s, encoding='utf-8')


# Build-time verification.
for path, markers in {
    'lib/support/support_chat_v6.dart': [
        'VetSupportVoiceRecorder voiceRecorder',
        '_toggleVoiceRecording()',
        'Icons.photo_camera_outlined',
        'Icons.mic_rounded',
        'VetSupportChatNotice.show(',
        'VetSupportChatSound.muted',
        'VetSupportVoiceNote(row: row, mine: mine)',
    ],
    'lib/support/support_agent_thread_v2.dart': [
        'VetSupportVoiceRecorder voiceRecorder',
        '_sendCameraPhoto()',
        'Icons.photo_camera_outlined',
        'Icons.mic_rounded',
        'VetSupportChatNotice.show(',
        'VetSupportChatSound.muted',
        'ValueListenableBuilder<TextEditingValue>',
    ],
    'lib/support/support_voice_note.dart': [
        'AudioRecorder()',
        'startStream(',
        "mimeType: 'audio/wav'",
        'VetSupportVoiceNote extends StatefulWidget',
    ],
}.items():
    text = Path(path).read_text(encoding='utf-8')
    for marker in markers:
        if marker not in text:
            raise SystemExit(f'V69 verification missing: {path} / {marker}')

print('Vet AI V69 applied: stable admin browser composer, foreground chat notices, persistent sound mute, WhatsApp camera/mic UI and real voice notes')
