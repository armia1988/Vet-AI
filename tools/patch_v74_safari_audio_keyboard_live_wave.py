from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    if old not in text:
        raise SystemExit(f'V74: {label} anchor missing')
    return text.replace(old, new, 1)


# ---------------------------------------------------------------------------
# 1) Reliable chat sounds.
#    Safari/iOS web gets a dedicated HTMLAudioElement implementation so chat
#    cues do not depend on audioplayers BytesSource behavior. Native keeps an
#    audioplayers implementation. Both keep the existing public API.
# ---------------------------------------------------------------------------
Path('lib/support/support_chat_sound.dart').write_text(r'''export 'support_chat_sound_native.dart'
    if (dart.library.html) 'support_chat_sound_web.dart';
''', encoding='utf-8')

Path('lib/support/support_chat_sound_native.dart').write_text(r'''import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class VetSupportChatSound {
  VetSupportChatSound._();

  static final AudioPlayer _sendPlayer = AudioPlayer();
  static final AudioPlayer _receivePlayer = AudioPlayer();
  static const _prefKey = 'vet_ai_support_chat_muted';
  static bool _muted = false;
  static bool _initialized = false;
  static String? _lastReceiveMessageId;
  static DateTime? _lastReceiveAt;

  static final Uint8List _sendBytes = _tone(
    durationMs: 112,
    frequencies: const [920.0, 1480.0],
    weights: const [.72, .28],
    amplitude: .52,
    glide: .055,
    tailPower: 3.2,
  );
  static final Uint8List _receiveBytes = _tone(
    durationMs: 162,
    frequencies: const [650.0, 980.0, 1370.0],
    weights: const [.50, .32, .18],
    amplitude: .48,
    glide: .075,
    tailPower: 2.65,
  );

  static bool get muted => _muted;

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _muted = prefs.getBool(_prefKey) ?? false;
    } catch (_) {}
    try { await _sendPlayer.setReleaseMode(ReleaseMode.stop); } catch (_) {}
    try { await _receivePlayer.setReleaseMode(ReleaseMode.stop); } catch (_) {}
  }

  static Future<void> setMuted(bool value) async {
    _muted = value;
    _initialized = true;
    if (value) {
      try { await _sendPlayer.stop(); } catch (_) {}
      try { await _receivePlayer.stop(); } catch (_) {}
    } else {
      await playReceiveFor('__sound_test__');
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, value);
    } catch (_) {}
  }

  static Future<void> unlock() async {}

  static Future<void> playSend() async {
    if (_muted) return;
    try {
      await _sendPlayer.play(BytesSource(_sendBytes), volume: 1.0, position: Duration.zero);
    } catch (_) {
      try { await SystemSound.play(SystemSoundType.click); } catch (_) {}
    }
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
    if (messageId.isNotEmpty) _lastReceiveMessageId = messageId;
    _lastReceiveAt = now;
    try {
      await _receivePlayer.play(BytesSource(_receiveBytes), volume: 1.0, position: Duration.zero);
    } catch (_) {
      try { await SystemSound.play(SystemSoundType.click); } catch (_) {}
    }
  }

  static Uint8List _tone({
    required int durationMs,
    required List<double> frequencies,
    required List<double> weights,
    required double amplitude,
    required double glide,
    required double tailPower,
  }) {
    const sampleRate = 24000;
    const bytesPerSample = 2;
    final count = (sampleRate * durationMs / 1000).round();
    final dataLength = count * bytesPerSample;
    final data = ByteData(44 + dataLength);
    void ascii(int offset, String value) {
      for (var i = 0; i < value.length; i++) data.setUint8(offset + i, value.codeUnitAt(i));
    }
    ascii(0, 'RIFF');
    data.setUint32(4, 36 + dataLength, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, 1, Endian.little);
    data.setUint32(24, sampleRate, Endian.little);
    data.setUint32(28, sampleRate * bytesPerSample, Endian.little);
    data.setUint16(32, bytesPerSample, Endian.little);
    data.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    data.setUint32(40, dataLength, Endian.little);
    for (var i = 0; i < count; i++) {
      final t = i / sampleRate;
      final p = i / count;
      final attack = math.min(1.0, i / (sampleRate * .0018));
      final decay = math.pow(1.0 - p, tailPower).toDouble();
      final pitch = 1.0 + glide * p;
      var wave = 0.0;
      for (var n = 0; n < frequencies.length; n++) {
        final w = n < weights.length ? weights[n] : 1 / frequencies.length;
        wave += math.sin(2 * math.pi * frequencies[n] * pitch * t) * w;
      }
      final sample = (32767 * amplitude * attack * decay * wave)
          .round().clamp(-32767, 32767).toInt();
      data.setInt16(44 + i * 2, sample, Endian.little);
    }
    return data.buffer.asUint8List();
  }
}
''', encoding='utf-8')

Path('lib/support/support_chat_sound_web.dart').write_text(r'''// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

class VetSupportChatSound {
  VetSupportChatSound._();

  static const _prefKey = 'vet_ai_support_chat_muted';
  static bool _muted = false;
  static bool _initialized = false;
  static bool _unlocked = false;
  static bool _gestureArmInstalled = false;
  static html.AudioElement? _sendAudio;
  static html.AudioElement? _receiveAudio;
  static String? _lastReceiveMessageId;
  static DateTime? _lastReceiveAt;

  static final Uint8List _sendBytes = _tone(
    durationMs: 112,
    frequencies: const [920.0, 1480.0],
    weights: const [.72, .28],
    amplitude: .56,
    glide: .055,
    tailPower: 3.2,
  );
  static final Uint8List _receiveBytes = _tone(
    durationMs: 162,
    frequencies: const [650.0, 980.0, 1370.0],
    weights: const [.50, .32, .18],
    amplitude: .52,
    glide: .075,
    tailPower: 2.65,
  );

  static bool get muted => _muted;

  static void _ensurePlayers() {
    _sendAudio ??= html.AudioElement(_dataUri(_sendBytes))
      ..preload = 'auto'
      ..setAttribute('playsinline', 'true');
    _receiveAudio ??= html.AudioElement(_dataUri(_receiveBytes))
      ..preload = 'auto'
      ..setAttribute('playsinline', 'true');
  }

  static String _dataUri(Uint8List bytes) =>
      'data:audio/wav;base64,${base64Encode(bytes)}';

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _ensurePlayers();
    _installGestureArm();
    try {
      final prefs = await SharedPreferences.getInstance();
      _muted = prefs.getBool(_prefKey) ?? false;
    } catch (_) {}
  }

  static void _installGestureArm() {
    if (_gestureArmInstalled) return;
    _gestureArmInstalled = true;
    void arm(html.Event _) {
      if (!_muted && !_unlocked) unawaited(unlock());
    }
    html.document.addEventListener('touchend', arm, true);
    html.document.addEventListener('pointerup', arm, true);
    html.document.addEventListener('click', arm, true);
  }

  static Future<void> setMuted(bool value) async {
    _muted = value;
    _initialized = true;
    _ensurePlayers();
    if (value) {
      _sendAudio?.pause();
      _receiveAudio?.pause();
    } else {
      // The sound button itself is a user gesture: unlock and give immediate
      // audible confirmation that chat sounds are enabled.
      await unlock();
      await playReceiveFor('__sound_test__');
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, value);
    } catch (_) {}
  }

  static Future<void> unlock() async {
    if (_muted || _unlocked) return;
    _ensurePlayers();
    final send = _sendAudio!;
    final receive = _receiveAudio!;
    try {
      send.pause();
      receive.pause();
      try { send.currentTime = 0; } catch (_) {}
      try { receive.currentTime = 0; } catch (_) {}
      send.volume = 0.001;
      receive.volume = 0.001;
      final a = send.play();
      final b = receive.play();
      await Future.wait<void>([a, b]);
      send.pause();
      receive.pause();
      try { send.currentTime = 0; } catch (_) {}
      try { receive.currentTime = 0; } catch (_) {}
      _unlocked = true;
    } catch (_) {
      _unlocked = false;
    }
  }

  static Future<void> playSend() async {
    if (_muted) return;
    _ensurePlayers();
    final audio = _sendAudio!;
    try {
      audio.pause();
      try { audio.currentTime = 0; } catch (_) {}
      audio.volume = 1.0;
      await audio.play();
      _unlocked = true;
    } catch (_) {
      // A blocked first play can be unlocked by the next user touch; the
      // global gesture listener is intentionally left installed.
      _unlocked = false;
    }
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
    if (messageId.isNotEmpty) _lastReceiveMessageId = messageId;
    _lastReceiveAt = now;
    _ensurePlayers();
    final audio = _receiveAudio!;
    try {
      audio.pause();
      try { audio.currentTime = 0; } catch (_) {}
      audio.volume = 1.0;
      await audio.play();
    } catch (_) {
      _unlocked = false;
    }
  }

  static Uint8List _tone({
    required int durationMs,
    required List<double> frequencies,
    required List<double> weights,
    required double amplitude,
    required double glide,
    required double tailPower,
  }) {
    const sampleRate = 24000;
    const bytesPerSample = 2;
    final count = (sampleRate * durationMs / 1000).round();
    final dataLength = count * bytesPerSample;
    final data = ByteData(44 + dataLength);
    void ascii(int offset, String value) {
      for (var i = 0; i < value.length; i++) data.setUint8(offset + i, value.codeUnitAt(i));
    }
    ascii(0, 'RIFF');
    data.setUint32(4, 36 + dataLength, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, 1, Endian.little);
    data.setUint32(24, sampleRate, Endian.little);
    data.setUint32(28, sampleRate * bytesPerSample, Endian.little);
    data.setUint16(32, bytesPerSample, Endian.little);
    data.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    data.setUint32(40, dataLength, Endian.little);
    for (var i = 0; i < count; i++) {
      final t = i / sampleRate;
      final p = i / count;
      final attack = math.min(1.0, i / (sampleRate * .0018));
      final decay = math.pow(1.0 - p, tailPower).toDouble();
      final pitch = 1.0 + glide * p;
      var wave = 0.0;
      for (var n = 0; n < frequencies.length; n++) {
        final w = n < weights.length ? weights[n] : 1 / frequencies.length;
        wave += math.sin(2 * math.pi * frequencies[n] * pitch * t) * w;
      }
      final sample = (32767 * amplitude * attack * decay * wave)
          .round().clamp(-32767, 32767).toInt();
      data.setInt16(44 + i * 2, sample, Endian.little);
    }
    return data.buffer.asUint8List();
  }
}
''', encoding='utf-8')


# ---------------------------------------------------------------------------
# 2) Make the live microphone level visibly react to speech, then render a
#    moving bar-by-bar waveform instead of a nearly-flat decorative line.
# ---------------------------------------------------------------------------
p = Path('lib/support/support_voice_note.dart')
s = p.read_text(encoding='utf-8')
s = replace_once(
    s,
    """    final normalized = (peak / 32768.0).clamp(0.0, 1.0).toDouble();
    final boosted = (normalized * 2.8).clamp(0.0, 1.0).toDouble();
    level.value = (level.value * .45 + boosted * .55).clamp(0.0, 1.0).toDouble();
""",
    """    final normalized = (peak / 32768.0).clamp(0.0, 1.0).toDouble();
    // Speech on phone microphones is often well below full-scale PCM. Boost
    // it aggressively for the UI meter only; recorded audio bytes are not
    // modified. The smoothing still keeps the bars readable instead of noisy.
    final boosted = (normalized * 8.5).clamp(0.0, 1.0).toDouble();
    level.value = (level.value * .18 + boosted * .82).clamp(0.0, 1.0).toDouble();
""",
    'microphone level boost',
)
p.write_text(s, encoding='utf-8')

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
  final List<double> history = List<double>.filled(32, .04);

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

  @override
  void dispose() {
    widget.level.removeListener(_onLevel);
    super.dispose();
  }

  void _onLevel() {
    if (!mounted || widget.paused) return;
    final raw = widget.level.value.clamp(0.0, 1.0).toDouble();
    // Keep silence as a tiny dash, but make actual speech visibly tall.
    final visual = raw < .025 ? .025 : (.12 + raw * .88).clamp(.12, 1.0).toDouble();
    setState(() {
      history.removeAt(0);
      history.add(visual);
    });
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
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(29),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Delete recording',
            onPressed: widget.busy ? null : widget.onCancel,
            icon: const Icon(Icons.delete_outline_rounded, color: muted, size: 25),
          ),
          const SizedBox(width: 1),
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(color: red, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            timeLabel,
            style: const TextStyle(fontSize: 13.5, color: Color(0xFF3B4A54), fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: SizedBox(
              height: 34,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      for (var i = 0; i < history.length; i++)
                        Expanded(
                          child: Align(
                            alignment: Alignment.center,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 70),
                              curve: Curves.easeOut,
                              margin: const EdgeInsets.symmetric(horizontal: .7),
                              width: 2.4,
                              height: 3.0 + history[i] * 28.0,
                              decoration: BoxDecoration(
                                color: i >= history.length - 4 ? green : muted.withValues(alpha: .72),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 7),
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
# 3) Safari keyboard stability.
#    The previous code re-requested focus after every send. On iPhone Safari
#    this can reopen the native keyboard after Safari itself has just changed
#    the visual viewport, producing the up/down loop seen in the recording.
#    Keep the existing focus when typing; only the user's tap may open it.
# ---------------------------------------------------------------------------
focus_before = """    message.clear();
    if (composerFocus.canRequestFocus) composerFocus.requestFocus();
"""
focus_after = """    message.clear();
"""
finally_focus = """    } finally {
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && composerFocus.canRequestFocus) composerFocus.requestFocus();
        });
      }
    }
"""

for path, key in [
    ('lib/support/support_chat_v6.dart', 'vet-support-customer-message-field'),
    ('lib/support/support_agent_thread_v2.dart', 'vet-support-agent-message-field'),
]:
    p = Path(path)
    s = p.read_text(encoding='utf-8')
    if focus_before in s:
      s = s.replace(focus_before, focus_after, 1)
    if finally_focus in s:
      s = s.replace(finally_focus, '    }\n', 1)
    # Give the native text input a stable identity across realtime message
    # rebuilds. FocusNode alone is not enough on iOS Safari when the render
    # tree around the composer changes height.
    field = '                        focusNode: composerFocus,\n'
    keyed = f"                        key: const ValueKey('{key}'),\n                        focusNode: composerFocus,\n"
    if keyed not in s:
      if field not in s:
        raise SystemExit(f'V74: {path} composer focus field missing')
      s = s.replace(field, keyed, 1)
    # Starting voice recording is an explicit mode change. Close the keyboard
    # once and do not let any async completion reopen it.
    sig = '  Future<void> _toggleVoiceRecording() async {\n'
    guard = sig + '    if (!recordingVoice) composerFocus.unfocus();\n'
    if guard not in s:
      if sig not in s:
        raise SystemExit(f'V74: {path} voice toggle missing')
      s = s.replace(sig, guard, 1)
    p.write_text(s, encoding='utf-8')

# The fixed-body rule from V65 fights Safari's visualViewport resize while the
# keyboard animates. Keep scrolling locked, but let the document participate in
# the viewport resize normally.
index = Path('web/index.html')
if index.exists():
    html = index.read_text(encoding='utf-8')
    html = html.replace(
        """      body {
        position: fixed;
        inset: 0;
      }
""",
        """      body {
        position: relative;
        inset: auto;
        min-height: 100%;
      }
""",
        1,
    )
    index.write_text(html, encoding='utf-8')


# ---------------------------------------------------------------------------
# Verification markers.
# ---------------------------------------------------------------------------
for path, markers in {
    'lib/support/support_chat_sound.dart': ["dart.library.html", 'support_chat_sound_web.dart'],
    'lib/support/support_chat_sound_web.dart': ['html.AudioElement', "data:audio/wav;base64", "addEventListener('touchend'", 'volume = 1.0'],
    'lib/support/support_chat_sound_native.dart': ['BytesSource(_sendBytes)', 'SystemSoundType.click'],
    'lib/support/support_voice_note.dart': ['normalized * 8.5', 'level.value * .18'],
    'lib/support/support_voice_recorder_bar.dart': ['history.removeAt(0)', 'AnimatedContainer', 'history[i] * 28.0'],
    'lib/support/support_chat_v6.dart': ["ValueKey('vet-support-customer-message-field')", 'composerFocus.unfocus()'],
    'lib/support/support_agent_thread_v2.dart': ["ValueKey('vet-support-agent-message-field')", 'composerFocus.unfocus()'],
}.items():
    text = Path(path).read_text(encoding='utf-8')
    for marker in markers:
        if marker not in text:
            raise SystemExit(f'V74 verification missing: {path} / {marker}')

for path in ['lib/support/support_chat_v6.dart', 'lib/support/support_agent_thread_v2.dart']:
    text = Path(path).read_text(encoding='utf-8')
    if 'addPostFrameCallback((_) {\n          if (mounted && composerFocus.canRequestFocus) composerFocus.requestFocus();' in text:
        raise SystemExit(f'V74: automatic post-send keyboard reopen still present in {path}')

print('Vet AI V74 applied: Safari HTML chat audio, stable keyboard focus, and strong live speech waveform')
