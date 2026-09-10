from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    if old not in text:
        raise SystemExit(f'V75: {label} anchor missing')
    return text.replace(old, new, 1)


def replace_method(text: str, start_sig: str, next_marker: str, replacement: str, label: str) -> str:
    start = text.find(start_sig)
    if start < 0:
        raise SystemExit(f'V75: {label} start marker missing')
    end = text.find(next_marker, start)
    if end < 0:
        raise SystemExit(f'V75: {label} end marker missing')
    return text[:start] + replacement + text[end:]


# ---------------------------------------------------------------------------
# 1) Voice notes: one reliable URL playback path + real microphone RMS history.
#    A voice clip now persists its measured waveform in message metadata so the
#    sent/received bubble represents the actual recording rather than a pattern.
# ---------------------------------------------------------------------------
Path('lib/support/support_voice_note.dart').write_text(r'''import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:record/record.dart';

import '../services/vet_backend.dart';

class VetSupportVoiceClip {
  const VetSupportVoiceClip(this.bytes, this.duration, this.waveform);
  final Uint8List bytes;
  final Duration duration;
  final List<double> waveform;
}

class VetSupportVoiceRecorder {
  final AudioRecorder _recorder = AudioRecorder();
  final List<Uint8List> _chunks = <Uint8List>[];
  final List<double> _waveformRaw = <double>[];
  final ValueNotifier<double> level = ValueNotifier<double>(0);
  StreamSubscription<Uint8List>? _subscription;
  Completer<void>? _streamDone;
  DateTime? _startedAt;
  DateTime? _lastWaveSampleAt;
  bool _recording = false;
  bool _paused = false;

  bool get recording => _recording;
  bool get paused => _paused;

  Future<void> start() async {
    if (_recording) return;
    // On iOS browsers, hasPermission() may itself provoke the browser prompt.
    // Let the real recording request own the one explicit microphone request.
    if (!kIsWeb) {
      final allowed = await _recorder.hasPermission();
      if (!allowed) throw StateError('Microphone permission denied');
    }
    _chunks.clear();
    _waveformRaw.clear();
    _lastWaveSampleAt = null;
    level.value = 0;
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
        if (chunk.isEmpty) return;
        _chunks.add(Uint8List.fromList(chunk));
        _updateLevel(chunk);
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
    _paused = false;
    _recording = true;
  }

  void _updateLevel(Uint8List pcm) {
    if (!_recording || _paused || pcm.length < 2) {
      level.value = 0;
      return;
    }
    final data = ByteData.sublistView(pcm);
    var sumSquares = 0.0;
    var samples = 0;
    // RMS gives a speech meter that is stable and does not jump on a single
    // click. Sampling every fourth frame is enough for the visual indicator.
    for (var i = 0; i + 1 < pcm.length; i += 8) {
      final sample = data.getInt16(i, Endian.little) / 32768.0;
      sumSquares += sample * sample;
      samples++;
    }
    if (samples == 0) return;
    final rms = math.sqrt(sumSquares / samples);
    const noiseFloor = 0.010;
    final speech = rms <= noiseFloor
        ? 0.0
        : ((rms - noiseFloor) / 0.085).clamp(0.0, 1.0).toDouble();
    final smoothed = speech == 0
        ? level.value * .20
        : (level.value * .18 + speech * .82).clamp(0.0, 1.0).toDouble();
    final visual = smoothed < .035 ? 0.0 : smoothed;
    level.value = visual;

    final now = DateTime.now();
    if (_lastWaveSampleAt == null || now.difference(_lastWaveSampleAt!).inMilliseconds >= 42) {
      _lastWaveSampleAt = now;
      _waveformRaw.add(visual);
    }
  }

  Future<void> pause() async {
    if (!_recording || _paused) return;
    await _recorder.pause();
    _paused = true;
    level.value = 0;
    _waveformRaw.add(0);
  }

  Future<void> resume() async {
    if (!_recording || !_paused) return;
    await _recorder.resume();
    _paused = false;
  }

  List<double> _compressedWaveform([int target = 48]) {
    if (_waveformRaw.isEmpty) return List<double>.filled(target, 0);
    if (_waveformRaw.length <= target) {
      final result = List<double>.from(_waveformRaw);
      while (result.length < target) result.insert(0, 0);
      return result;
    }
    final result = <double>[];
    for (var i = 0; i < target; i++) {
      final start = (i * _waveformRaw.length / target).floor();
      var end = ((i + 1) * _waveformRaw.length / target).ceil();
      if (end <= start) end = start + 1;
      end = math.min(end, _waveformRaw.length);
      var peak = 0.0;
      var sum = 0.0;
      for (var j = start; j < end; j++) {
        peak = math.max(peak, _waveformRaw[j]);
        sum += _waveformRaw[j];
      }
      final average = sum / math.max(1, end - start);
      final value = peak < .035 && average < .025
          ? 0.0
          : (peak * .68 + average * .32).clamp(0.0, 1.0).toDouble();
      result.add(value);
    }
    return result;
  }

  Future<VetSupportVoiceClip?> stop() async {
    if (!_recording) return null;
    final started = _startedAt ?? DateTime.now();
    _recording = false;
    _paused = false;
    level.value = 0;
    await _recorder.stop();
    try {
      await _streamDone?.future.timeout(const Duration(milliseconds: 1800));
    } catch (_) {}
    await _subscription?.cancel();
    _subscription = null;
    final rawLength = _chunks.fold<int>(0, (sum, e) => sum + e.length);
    if (rawLength < 3200) {
      _chunks.clear();
      _waveformRaw.clear();
      throw StateError('VOICE_RECORDING_TOO_SHORT');
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
    final waveform = _compressedWaveform();
    _waveformRaw.clear();
    return VetSupportVoiceClip(_wav(raw), duration, waveform);
  }

  Future<void> cancel() async {
    if (_recording) {
      _recording = false;
      _paused = false;
      try { await _recorder.cancel(); } catch (_) {}
    }
    level.value = 0;
    await _subscription?.cancel();
    _subscription = null;
    _chunks.clear();
    _waveformRaw.clear();
  }

  void dispose() {
    unawaited(cancel());
    unawaited(_recorder.dispose());
    level.dispose();
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
      'metadata': {
        'duration_ms': clip.duration.inMilliseconds,
        'waveform': clip.waveform,
      },
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
  bool loading = false;
  bool playing = false;
  Duration position = Duration.zero;
  Duration total = Duration.zero;
  StreamSubscription<void>? completeSub;
  StreamSubscription<Duration>? positionSub;
  StreamSubscription<Duration>? durationSub;

  static const legacyPattern = <double>[
    .18,.46,.27,.62,.32,.54,.16,.72,.36,.57,.24,.78,.29,.51,.15,.66,
    .34,.55,.26,.73,.19,.46,.60,.31,.69,.23,.54,.38,.63,.18,.49,.71,
  ];

  @override
  void initState() {
    super.initState();
    total = Duration(milliseconds: durationMs);
    unawaited(player.setReleaseMode(ReleaseMode.stop));
    positionSub = player.onPositionChanged.listen((value) {
      if (mounted) setState(() => position = value);
    });
    durationSub = player.onDurationChanged.listen((value) {
      if (mounted && value.inMilliseconds > 0) setState(() => total = value);
    });
    completeSub = player.onPlayerComplete.listen((_) {
      if (mounted) setState(() {
        playing = false;
        position = Duration.zero;
      });
    });
  }

  int get durationMs {
    final meta = widget.row['metadata'];
    if (meta is Map && meta['duration_ms'] is num) {
      return (meta['duration_ms'] as num).toInt();
    }
    return 0;
  }

  List<double> get waveform {
    final meta = widget.row['metadata'];
    if (meta is Map && meta['waveform'] is List) {
      final result = <double>[];
      for (final value in meta['waveform'] as List) {
        if (value is num) result.add(value.toDouble().clamp(0.0, 1.0));
      }
      if (result.isNotEmpty) return result;
    }
    return legacyPattern;
  }

  String _durationLabel(Duration value) {
    final seconds = value.inSeconds.clamp(0, 3599);
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  double get progress {
    if (total.inMilliseconds <= 0) return 0;
    return (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0).toDouble();
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
      final path = '${widget.row['attachment_path'] ?? ''}'.trim();
      if (path.isEmpty) throw StateError('Voice attachment unavailable');
      final url = await VetBackend.instance.signedSupportAttachmentUrl(path);
      await player.play(UrlSource(url), position: position);
      if (mounted) setState(() => playing = true);
    } catch (_) {
      // Signed links are cheap and short lived. Refresh once so a stale URL or
      // Safari media-element hiccup does not make the voice note intermittent.
      try {
        final path = '${widget.row['attachment_path'] ?? ''}'.trim();
        final url = await VetBackend.instance.signedSupportAttachmentUrl(path);
        await Future<void>.delayed(const Duration(milliseconds: 80));
        await player.play(UrlSource(url), position: position);
        if (mounted) setState(() => playing = true);
      } catch (_) {
        if (mounted) setState(() => playing = false);
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> seek(double fraction) async {
    if (total.inMilliseconds <= 0) return;
    final target = Duration(milliseconds: (total.inMilliseconds * fraction.clamp(0.0, 1.0)).round());
    if (playing) {
      try { await player.seek(target); } catch (_) {}
    }
    if (mounted) setState(() => position = target);
  }

  @override
  void dispose() {
    completeSub?.cancel();
    positionSub?.cancel();
    durationSub?.cancel();
    unawaited(player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF00A884);
    const muted = Color(0xFF667781);
    final samples = waveform;
    return SizedBox(
      width: 260,
      child: Row(
        children: [
          InkWell(
            onTap: toggle,
            customBorder: const CircleBorder(),
            child: CircleAvatar(
              radius: 21,
              backgroundColor: green,
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
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) {
                    final box = context.findRenderObject() as RenderBox?;
                    if (box == null) return;
                    final x = details.localPosition.dx - 51;
                    final width = box.size.width - 67;
                    if (width > 0) unawaited(seek(x / width));
                  },
                  child: SizedBox(
                    height: 30,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        for (var i = 0; i < samples.length; i++)
                          Expanded(
                            child: Center(
                              child: Container(
                                width: samples[i] <= .02 ? 2.2 : 2.5,
                                height: samples[i] <= .02 ? 2.2 : 4 + samples[i] * 25,
                                decoration: BoxDecoration(
                                  color: i / math.max(1, samples.length) <= progress
                                      ? green
                                      : muted.withValues(alpha: .52),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  playing || position.inMilliseconds > 0 ? _durationLabel(position) : _durationLabel(total),
                  style: const TextStyle(fontSize: 10.5, color: muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 7),
          Icon(Icons.mic_rounded, size: 18, color: widget.mine ? green : muted),
        ],
      ),
    );
  }
}
''', encoding='utf-8')


# ---------------------------------------------------------------------------
# 2) Live recorder bar. Silence is a row of tiny centered dots. Speech becomes
#    vertical bars centered on that line and grows with the measured RMS level.
# ---------------------------------------------------------------------------
Path('lib/support/support_voice_recorder_bar.dart').write_text(r'''import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class VetSupportVoiceRecorderBar extends StatefulWidget {
  const VetSupportVoiceRecorderBar({
    super.key,
    required this.seconds,
    required this.paused,
    required this.busy,
    required this.level,
    required this.onCancel,
    required this.onPauseResume,
    required this.onSend,
  });

  final int seconds;
  final bool paused;
  final bool busy;
  final ValueListenable<double> level;
  final VoidCallback onCancel;
  final VoidCallback onPauseResume;
  final VoidCallback onSend;

  @override
  State<VetSupportVoiceRecorderBar> createState() => _VetSupportVoiceRecorderBarState();
}

class _VetSupportVoiceRecorderBarState extends State<VetSupportVoiceRecorderBar> {
  final List<double> history = List<double>.filled(46, 0);

  @override
  void initState() {
    super.initState();
    widget.level.addListener(_onLevel);
  }

  @override
  void didUpdateWidget(covariant VetSupportVoiceRecorderBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.level != widget.level) {
      oldWidget.level.removeListener(_onLevel);
      widget.level.addListener(_onLevel);
    }
  }

  void _onLevel() {
    if (!mounted || widget.paused) return;
    final raw = widget.level.value.clamp(0.0, 1.0).toDouble();
    final visual = raw < .04 ? 0.0 : (.08 + raw * .92).clamp(.08, 1.0).toDouble();
    setState(() {
      history.removeAt(0);
      history.add(visual);
    });
  }

  @override
  void dispose() {
    widget.level.removeListener(_onLevel);
    super.dispose();
  }

  String get timeLabel {
    final m = widget.seconds ~/ 60;
    final s = widget.seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF00A884);
    const red = Color(0xFFE53935);
    const muted = Color(0xFF667781);
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(29)),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Delete recording',
            onPressed: widget.busy ? null : widget.onCancel,
            icon: const Icon(Icons.delete_outline_rounded, color: muted, size: 24),
          ),
          Container(width: 7, height: 7, decoration: const BoxDecoration(color: red, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(timeLabel, style: const TextStyle(fontSize: 13.5, color: Color(0xFF3B4A54), fontWeight: FontWeight.w700)),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 34,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  for (final value in history)
                    Expanded(
                      child: Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 55),
                          curve: Curves.easeOut,
                          width: value == 0 ? 2.2 : 2.6,
                          height: value == 0 ? 2.2 : 4 + value * 27,
                          decoration: BoxDecoration(
                            color: widget.paused ? muted.withValues(alpha: .28) : muted.withValues(alpha: .72),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            onTap: widget.busy ? null : widget.onPauseResume,
            customBorder: const CircleBorder(),
            child: CircleAvatar(
              radius: 20,
              backgroundColor: const Color(0xFFFFE8E8),
              child: Icon(widget.paused ? Icons.play_arrow_rounded : Icons.pause_rounded, color: red, size: 25),
            ),
          ),
          const SizedBox(width: 7),
          InkWell(
            onTap: widget.busy ? null : widget.onSend,
            customBorder: const CircleBorder(),
            child: CircleAvatar(
              radius: 23,
              backgroundColor: green,
              child: widget.busy
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded, color: Colors.white, size: 24),
            ),
          ),
          const SizedBox(width: 3),
        ],
      ),
    );
  }
}
''', encoding='utf-8')


# ---------------------------------------------------------------------------
# 3) Bubble geometry: sent messages are always physically on the right and
#    received messages on the left, even in Arabic RTL. The timestamp footer
#    must shrink-wrap instead of forcing every short message to max bubble width.
# ---------------------------------------------------------------------------
for file_path in ['lib/support/support_chat_v6.dart', 'lib/support/support_agent_thread_v2.dart']:
    p = Path(file_path)
    s = p.read_text(encoding='utf-8')
    s = s.replace(
        'mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart',
        'mine ? Alignment.centerRight : Alignment.centerLeft',
    )
    # Some compact formatters put the ternary over two lines.
    s = s.replace(
        'mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,',
        'mine ? Alignment.centerRight : Alignment.centerLeft,',
    )
    p.write_text(s, encoding='utf-8')

p = Path('lib/support/support_agent_thread_v2.dart')
s = p.read_text(encoding='utf-8')
footer = """              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
"""
footer_physical = """              Align(
                alignment: Alignment.centerRight,
                widthFactor: 1,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
"""
if footer in s:
    s = s.replace(footer, footer_physical, 1)
else:
    footer2 = """              Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
"""
    if footer2 in s:
        s = s.replace(footer2, footer_physical, 1)
    elif 'widthFactor: 1,' not in s:
        raise SystemExit('V75: admin bubble footer width anchor missing')
p.write_text(s, encoding='utf-8')


# ---------------------------------------------------------------------------
# 4) User-facing call text must never expose STUN/TURN/WebRTC jargon. These are
#    transport diagnostics, not call-state labels.
# ---------------------------------------------------------------------------
p = Path('lib/support/support_webrtc_call_page.dart')
s = p.read_text(encoding='utf-8')
status_method = r'''  String _statusText(BuildContext context) {
    if (!ready && connectionLabel == 'Connecting') {
      return _ct(context, 'Preparing call…', 'جاري تجهيز المكالمة…', 'Oproep voorbereiden…');
    }
    if (callStatus == 'ringing' && connectionLabel != 'Connected') {
      return widget.isCaller
          ? _ct(context, 'Calling…', 'جاري الاتصال…', 'Bellen…')
          : _ct(context, 'Ringing…', 'مكالمة واردة…', 'Inkomende oproep…');
    }
    return switch (connectionLabel) {
      'Connected' => _ct(context, 'Connected', 'متصل', 'Verbonden'),
      'Reconnecting' => _ct(context, 'Reconnecting…', 'إعادة الاتصال…', 'Opnieuw verbinden…'),
      'Connection failed' => _ct(context, 'Connection failed', 'فشل الاتصال', 'Verbinding mislukt'),
      'Could not connect' => _ct(context, 'Could not connect', 'تعذر الاتصال', 'Kon niet verbinden'),
      'Ended' => _ct(context, 'Call ended', 'انتهت المكالمة', 'Oproep beëindigd'),
      _ => _ct(context, 'Connecting…', 'جاري الاتصال…', 'Verbinden…'),
    };
  }
'''
s = replace_method(
    s,
    '  String _statusText(BuildContext context) {',
    '\n}\n\nclass _WaitingView',
    status_method,
    'call status text',
)
p.write_text(s, encoding='utf-8')


# ---------------------------------------------------------------------------
# 5) One app-wide RLS-scoped realtime layer handles BOTH incoming calls and new
#    support messages. This makes foreground notifications work while the user
#    is elsewhere in the app/admin, not only while the exact chat is open.
# ---------------------------------------------------------------------------
Path('lib/support/support_incoming_call_overlay.dart').write_text(r'''import 'dart:async';

import 'package:flutter/material.dart';

import '../services/callkit_service.dart';
import '../services/vet_backend.dart';
import '../theme/app_theme.dart';
import 'support_call_service.dart';
import 'support_call_tone.dart';
import 'support_chat_notice.dart';
import 'support_chat_sound.dart';

class VetIncomingSupportCallLayer extends StatefulWidget {
  const VetIncomingSupportCallLayer({
    super.key,
    required this.role,
    required this.child,
  });

  final String role;
  final Widget child;

  @override
  State<VetIncomingSupportCallLayer> createState() => _VetIncomingSupportCallLayerState();
}

class _VetIncomingSupportCallLayerState extends State<VetIncomingSupportCallLayer> {
  final calls = VetSupportCallService.instance;
  StreamSubscription<List<Map<String, dynamic>>>? callSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? messageSubscription;
  StreamSubscription<Map<String, dynamic>>? callKitSubscription;
  String? currentDialogCallId;
  final Set<String> seenMessageIds = <String>{};
  bool messagesPrimed = false;

  @override
  void initState() {
    super.initState();
    unawaited(VetSupportChatSound.initialize());
    callSubscription = calls.accessibleCallsStream().listen(_onCalls);
    messageSubscription = VetBackend.instance.client
        .from('support_messages')
        .stream(primaryKey: ['id'])
        .order('created_at')
        .listen(_onMessages);
    callKitSubscription = VetCallKitService.instance.actions.listen(_onCallKitAction);
  }

  bool _isIncomingMessage(Map<String, dynamic> row) {
    final sender = '${row['sender_role'] ?? ''}';
    return widget.role == 'support' ? sender == 'user' : sender == 'support';
  }

  void _onMessages(List<Map<String, dynamic>> rows) {
    if (!messagesPrimed) {
      for (final row in rows) {
        final id = '${row['id'] ?? ''}';
        if (id.isNotEmpty) seenMessageIds.add(id);
      }
      messagesPrimed = true;
      return;
    }
    final now = DateTime.now().toUtc();
    final fresh = <Map<String, dynamic>>[];
    for (final row in rows) {
      final id = '${row['id'] ?? ''}';
      if (id.isEmpty || !seenMessageIds.add(id) || !_isIncomingMessage(row)) continue;
      final created = DateTime.tryParse('${row['created_at'] ?? ''}')?.toUtc();
      if (created == null || now.difference(created).abs() > const Duration(seconds: 45)) continue;
      fresh.add(row);
    }
    if (fresh.isEmpty || !mounted) return;
    fresh.sort((a, b) {
      final at = DateTime.tryParse('${a['created_at'] ?? ''}') ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bt = DateTime.tryParse('${b['created_at'] ?? ''}') ?? DateTime.fromMillisecondsSinceEpoch(0);
      return at.compareTo(bt);
    });
    final row = fresh.last;
    final id = '${row['id'] ?? ''}';
    unawaited(VetSupportChatSound.playReceiveFor(id));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final preview = VetSupportChatNotice.preview(
        row,
        newMessage: 'New support message',
        voiceMessage: 'Voice message',
        photo: 'Photo',
        attachment: 'Attachment',
      );
      VetSupportChatNotice.show(
        context,
        messageId: id,
        title: widget.role == 'support' ? 'New customer message' : 'Vet AI Support',
        preview: preview,
      );
    });
  }

  Map<String, dynamic>? _freshIncoming(List<Map<String, dynamic>> rows) {
    final cutoff = DateTime.now().toUtc().subtract(const Duration(seconds: 90));
    final incoming = rows.where((call) {
      if ('${call['status']}' != 'ringing') return false;
      if ('${call['caller_role']}' == widget.role) return false;
      final created = DateTime.tryParse('${call['created_at'] ?? ''}')?.toUtc();
      return created != null && created.isAfter(cutoff);
    }).toList(growable: true)
      ..sort((a, b) {
        final at = DateTime.tryParse('${a['created_at'] ?? ''}') ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bt = DateTime.tryParse('${b['created_at'] ?? ''}') ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bt.compareTo(at);
      });
    return incoming.isEmpty ? null : incoming.first;
  }

  void _onCalls(List<Map<String, dynamic>> rows) {
    final call = _freshIncoming(rows);
    final nextId = call?['id']?.toString();
    if (currentDialogCallId != null && nextId == null) {
      unawaited(VetSupportCallTone.stopIncoming(currentDialogCallId));
      currentDialogCallId = null;
      return;
    }
    if (call == null || nextId == null || currentDialogCallId == nextId || !mounted) return;
    currentDialogCallId = nextId;
    if (!VetCallKitService.instance.usesNativeCallKit) {
      unawaited(VetSupportCallTone.startIncoming(nextId));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showIncoming(call);
    });
  }

  void _onCallKitAction(Map<String, dynamic> action) {
    final callId = '${action['call_id'] ?? ''}';
    if (callId.isEmpty) return;
    final kind = '${action['action'] ?? ''}';
    if (kind == 'answer') {
      unawaited(_answerById(callId));
    } else if (kind == 'end') {
      unawaited(calls.end(callId));
    }
  }

  Future<void> _answerById(String callId) async {
    try {
      final rows = await calls.client.from('support_calls').select().eq('id', callId).limit(1);
      if (rows.isEmpty) return;
      final call = Map<String, dynamic>.from(rows.first);
      await calls.accept(callId);
      if (!mounted) return;
      await calls.openMediaRoom(call);
    } catch (_) {}
  }

  Future<void> _showIncoming(Map<String, dynamic> call) async {
    final callId = '${call['id']}';
    final video = call['call_type'] == 'video';
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        icon: CircleAvatar(
          radius: 34,
          backgroundColor: VetColors.softGreen,
          child: Icon(video ? Icons.videocam_rounded : Icons.call_rounded, size: 34, color: VetColors.green),
        ),
        title: Text(video ? 'Incoming video call' : 'Incoming voice call', textAlign: TextAlign.center),
        content: const Text('Vet AI Support', textAlign: TextAlign.center),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(backgroundColor: VetColors.red.withValues(alpha: .12), foregroundColor: VetColors.red),
            onPressed: () => Navigator.pop(dialogContext, false),
            icon: const Icon(Icons.call_end_rounded),
            label: const Text('Decline'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: VetColors.green),
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.call_rounded),
            label: const Text('Answer'),
          ),
        ],
      ),
    );
    unawaited(VetSupportCallTone.stopIncoming(callId));
    currentDialogCallId = null;
    if (accepted == true) {
      try {
        await calls.accept(callId);
        if (mounted) await calls.openMediaRoom(call);
      } catch (_) {}
    } else {
      try { await calls.decline(callId); } catch (_) {}
    }
  }

  @override
  void dispose() {
    callSubscription?.cancel();
    messageSubscription?.cancel();
    callKitSubscription?.cancel();
    unawaited(VetSupportCallTone.stopIncoming(currentDialogCallId));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
''', encoding='utf-8')


# ---------------------------------------------------------------------------
# 6) Re-register native APNs + PushKit tokens whenever the app returns to the
#    foreground. A stale/disabled token must not leave messages/calls dead until
#    the user signs out and back in.
# ---------------------------------------------------------------------------
p = Path('lib/services/alert_notification_service.dart')
s = p.read_text(encoding='utf-8')
if "import 'dart:async';\n" not in s:
    s = "import 'dart:async';\n" + s
if "import 'package:flutter/widgets.dart';\n" not in s:
    anchor = "import 'package:flutter/services.dart';\n"
    if anchor not in s:
        raise SystemExit('V75: notification widgets import anchor missing')
    s = s.replace(anchor, anchor + "import 'package:flutter/widgets.dart';\n", 1)
s = s.replace('class VetAlertNotificationService {', 'class VetAlertNotificationService with WidgetsBindingObserver {', 1)
field_anchor = '  bool _ready = false;\n'
if 'bool _lifecycleInstalled = false;' not in s:
    s = replace_once(
        s,
        field_anchor,
        field_anchor + "  bool _lifecycleInstalled = false;\n  String? _currentFarmId;\n  bool _adminRegistration = false;\n",
        'notification lifecycle fields',
    )
init_old = """  Future<void> initialize() async {
    if (_ready) return;
    if (kIsWeb) {
"""
init_new = """  Future<void> initialize() async {
    if (!kIsWeb && !_lifecycleInstalled) {
      WidgetsBinding.instance.addObserver(this);
      _lifecycleInstalled = true;
    }
    if (_ready) return;
    if (kIsWeb) {
"""
s = replace_once(s, init_old, init_new, 'notification lifecycle initialization')
reg_farm = """  Future<void> registerRemotePushForFarm(String farmId) async {
    if (!_isIOS || farmId.trim().isEmpty) return;
"""
reg_farm_new = """  Future<void> registerRemotePushForFarm(String farmId) async {
    _currentFarmId = farmId.trim();
    _adminRegistration = false;
    if (!_isIOS || _currentFarmId!.isEmpty) return;
"""
s = replace_once(s, reg_farm, reg_farm_new, 'farm APNs registration state')
reg_admin = """  Future<void> registerRemotePushForAdmin() async {
    if (!_isIOS) return;
"""
reg_admin_new = """  Future<void> registerRemotePushForAdmin() async {
    _adminRegistration = true;
    _currentFarmId = null;
    if (!_isIOS) return;
"""
s = replace_once(s, reg_admin, reg_admin_new, 'admin APNs registration state')
unreg = """  Future<void> unregisterRemotePush() async {
    if (!_isIOS) return;
"""
unreg_new = """  Future<void> unregisterRemotePush() async {
    _currentFarmId = null;
    _adminRegistration = false;
    if (!_isIOS) return;
"""
s = replace_once(s, unreg, unreg_new, 'APNs logout registration state')
if 'void didChangeAppLifecycleState(AppLifecycleState state)' not in s:
    marker = '  Future<void> showSensorAlert({\n'
    if marker not in s:
        raise SystemExit('V75: notification lifecycle method anchor missing')
    method = r'''  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_isIOS) return;
    final farmId = _currentFarmId;
    if (farmId != null && farmId.isNotEmpty) {
      unawaited(registerRemotePushForFarm(farmId));
    } else if (_adminRegistration) {
      unawaited(registerRemotePushForAdmin());
    }
  }

'''
    s = s.replace(marker, method + marker, 1)
p.write_text(s, encoding='utf-8')

p = Path('lib/services/callkit_service.dart')
s = p.read_text(encoding='utf-8')
if "import 'package:flutter/widgets.dart';\n" not in s:
    anchor = "import 'package:flutter/services.dart';\n"
    if anchor not in s:
        raise SystemExit('V75: CallKit widgets import anchor missing')
    s = s.replace(anchor, anchor + "import 'package:flutter/widgets.dart';\n", 1)
s = s.replace('class VetCallKitService {', 'class VetCallKitService with WidgetsBindingObserver {', 1)
field_anchor = '  bool _initialized = false;\n'
if 'bool _lifecycleInstalled = false;' not in s:
    s = replace_once(
        s,
        field_anchor,
        field_anchor + "  bool _lifecycleInstalled = false;\n  String? _registeredFarmId;\n  bool _registeredAsAdmin = false;\n",
        'CallKit lifecycle fields',
    )
init_old = """  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    if (!_isIOS) return;
"""
init_new = """  Future<void> initialize() async {
    if (!_isIOS) return;
    if (!_lifecycleInstalled) {
      WidgetsBinding.instance.addObserver(this);
      _lifecycleInstalled = true;
    }
    if (_initialized) return;
    _initialized = true;
"""
s = replace_once(s, init_old, init_new, 'CallKit lifecycle initialization')
reg_farm = """  Future<void> registerForFarm(String farmId) async {
    if (!_isIOS || farmId.trim().isEmpty) return;
"""
reg_farm_new = """  Future<void> registerForFarm(String farmId) async {
    _registeredFarmId = farmId.trim();
    _registeredAsAdmin = false;
    if (!_isIOS || _registeredFarmId!.isEmpty) return;
"""
s = replace_once(s, reg_farm, reg_farm_new, 'farm PushKit registration state')
reg_admin = """  Future<void> registerForAdmin() async {
    if (!_isIOS) return;
"""
reg_admin_new = """  Future<void> registerForAdmin() async {
    _registeredAsAdmin = true;
    _registeredFarmId = null;
    if (!_isIOS) return;
"""
s = replace_once(s, reg_admin, reg_admin_new, 'admin PushKit registration state')
unreg = """  Future<void> unregister() async {
    if (!_isIOS || Supabase.instance.client.auth.currentUser == null) return;
"""
unreg_new = """  Future<void> unregister() async {
    _registeredFarmId = null;
    _registeredAsAdmin = false;
    if (!_isIOS || Supabase.instance.client.auth.currentUser == null) return;
"""
s = replace_once(s, unreg, unreg_new, 'PushKit logout registration state')
if 'void didChangeAppLifecycleState(AppLifecycleState state)' not in s:
    marker = '  Future<void> endSystemCall(String callId) async {\n'
    if marker not in s:
        raise SystemExit('V75: CallKit lifecycle method anchor missing')
    method = r'''  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_isIOS) return;
    final farmId = _registeredFarmId;
    if (farmId != null && farmId.isNotEmpty) {
      unawaited(registerForFarm(farmId));
    } else if (_registeredAsAdmin) {
      unawaited(registerForAdmin());
    }
  }

'''
    s = s.replace(marker, method + marker, 1)
p.write_text(s, encoding='utf-8')


# ---------------------------------------------------------------------------
# Verification: these are the regressions this patch is specifically locking.
# ---------------------------------------------------------------------------
checks = {
    'lib/support/support_voice_note.dart': [
        'noiseFloor = 0.010', "'waveform': clip.waveform", 'UrlSource(url)',
        'if (!kIsWeb)', '_compressedWaveform',
    ],
    'lib/support/support_voice_recorder_bar.dart': [
        'List<double>.filled(46, 0)', 'height: value == 0 ? 2.2', 'value * 27',
    ],
    'lib/support/support_incoming_call_overlay.dart': [
        "from('support_messages')", 'playReceiveFor(id)', 'VetSupportChatNotice.show',
    ],
    'lib/services/alert_notification_service.dart': [
        'WidgetsBindingObserver', 'AppLifecycleState.resumed', '_currentFarmId',
    ],
    'lib/services/callkit_service.dart': [
        'WidgetsBindingObserver', 'AppLifecycleState.resumed', '_registeredFarmId',
    ],
    'lib/support/support_webrtc_call_page.dart': [
        "'Calling…'", "'Ringing…'", "'Connected'",
    ],
}
for path, markers in checks.items():
    text = Path(path).read_text(encoding='utf-8')
    for marker in markers:
        if marker not in text:
            raise SystemExit(f'V75 verification missing: {path} / {marker}')

call_text = Path('lib/support/support_webrtc_call_page.dart').read_text(encoding='utf-8')
status_start = call_text.index('  String _statusText(BuildContext context) {')
status_end = call_text.index('\n}\n\nclass _WaitingView', status_start)
status_text = call_text[status_start:status_end]
for technical in ['STUN', 'TURN/WebRTC', 'WebRTC']:
    if technical in status_text:
        raise SystemExit(f'V75: technical call label still visible: {technical}')

for path in ['lib/support/support_chat_v6.dart', 'lib/support/support_agent_thread_v2.dart']:
    text = Path(path).read_text(encoding='utf-8')
    if 'mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart' in text:
        raise SystemExit(f'V75: RTL-dependent message side still present in {path}')

if 'widthFactor: 1,' not in Path('lib/support/support_agent_thread_v2.dart').read_text(encoding='utf-8'):
    raise SystemExit('V75: admin message footer can still force max bubble width')

print('Vet AI V75 applied: correct chat sides/sizing, true speech waveform, reliable voice URL playback, clean call labels, foreground message alerts and native token refresh')
