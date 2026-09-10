from pathlib import Path

# V79: stabilize the native iPhone chat viewport, make voice-note playback
# reliable on iOS by using a real temporary audio file, and refine the live
# recorder into a compact ChatGPT-style interaction with a true speech waveform.

# ---------------------------------------------------------------------------
# 1) Platform-correct keyboard behavior.
# Web/Safari owns the visual viewport resize; native Flutter must resize its
# Scaffold so the composer remains attached to the keyboard instead of being
# overlaid/jumping. V77 had intentionally disabled resize for Safari but applied
# that choice to native too. Split the behavior by platform.
# ---------------------------------------------------------------------------
for file_path in [
    'lib/support/support_chat_v6.dart',
    'lib/support/support_agent_thread_v2.dart',
]:
    p = Path(file_path)
    s = p.read_text(encoding='utf-8')
    if "import 'package:flutter/foundation.dart';" not in s:
        marker = "import 'package:flutter/material.dart';\n"
        if marker not in s:
            raise SystemExit(f'V79: material import missing in {file_path}')
        s = s.replace(marker, "import 'package:flutter/foundation.dart';\n" + marker, 1)
    s = s.replace(
        'resizeToAvoidBottomInset: false,',
        'resizeToAvoidBottomInset: !kIsWeb,',
    )
    s = s.replace(
        'scrollPadding: EdgeInsets.zero,',
        'scrollPadding: kIsWeb ? EdgeInsets.zero : const EdgeInsets.only(bottom: 12),',
    )
    p.write_text(s, encoding='utf-8')

# ---------------------------------------------------------------------------
# 2) Reliable voice playback abstraction.
# Native iOS is materially more reliable when audioplayers receives a device
# file source rather than an in-memory WAV. Web keeps BytesSource so there is no
# dart:io dependency. The downloaded private attachment remains authenticated.
# ---------------------------------------------------------------------------
Path('lib/support/support_voice_playback.dart').write_text(r'''export 'support_voice_playback_native.dart'
    if (dart.library.html) 'support_voice_playback_web.dart';
''', encoding='utf-8')

Path('lib/support/support_voice_playback_native.dart').write_text(r'''import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

Future<void> playVetVoiceBytes(
  AudioPlayer player,
  Uint8List bytes, {
  required Duration position,
  required String cacheKey,
}) async {
  final dir = await getTemporaryDirectory();
  final safe = cacheKey.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  final file = File('${dir.path}/vet_voice_${safe.isEmpty ? bytes.length : safe}.wav');
  try {
    if (!await file.exists() || await file.length() != bytes.length) {
      await file.writeAsBytes(bytes, flush: true);
    }
    await player.stop();
    await player.play(DeviceFileSource(file.path), position: position);
  } catch (_) {
    // Last-resort in-memory path for platforms where temp storage is restricted.
    await player.play(BytesSource(bytes), position: position);
  }
}
''', encoding='utf-8')

Path('lib/support/support_voice_playback_web.dart').write_text(r'''import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

Future<void> playVetVoiceBytes(
  AudioPlayer player,
  Uint8List bytes, {
  required Duration position,
  required String cacheKey,
}) async {
  await player.stop();
  await player.play(BytesSource(bytes), position: position);
}
''', encoding='utf-8')

p = Path('lib/support/support_voice_note.dart')
s = p.read_text(encoding='utf-8')
if "import 'support_voice_playback.dart';" not in s:
    marker = "import '../services/vet_backend.dart';\n"
    if marker not in s:
        raise SystemExit('V79: voice backend import anchor missing')
    s = s.replace(marker, marker + "import 'support_voice_playback.dart';\n", 1)

old = "await player.play(BytesSource(bytes), position: position);"
new = """await playVetVoiceBytes(
        player,
        bytes,
        position: position,
        cacheKey: '${widget.row['id'] ?? widget.row['attachment_path'] ?? ''}',
      );"""
if new not in s:
    if old not in s:
        raise SystemExit('V79: V77 voice playback anchor missing')
    s = s.replace(old, new, 1)

# Surface a retry affordance instead of silently doing nothing after playback
# failure. Keep the bubble responsive and reset preload so the next tap retries.
old_catch = """    } catch (_) {
      if (mounted) setState(() => playing = false);
    } finally {
"""
new_catch = """    } catch (_) {
      cachedAudioBytes = null;
      preloadTask = _preloadAudio();
      if (mounted) setState(() => playing = false);
    } finally {
"""
if old_catch in s:
    s = s.replace(old_catch, new_catch, 1)
p.write_text(s, encoding='utf-8')

# ---------------------------------------------------------------------------
# 3) ChatGPT-style live recorder bar.
# Silence stays as a center dot/short line; speech creates symmetric bars around
# the center line. Controls are compact: cancel, timer, live wave, pause, send.
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
    final value = raw < .035 ? 0.0 : raw;
    setState(() {
      history.removeAt(0);
      history.add(value);
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
    const green = Color(0xFF10A37F);
    const ink = Color(0xFF202123);
    const muted = Color(0xFF6E6E73);
    const border = Color(0xFFE5E5E5);
    return Container(
      height: 54,
      padding: const EdgeInsets.fromLTRB(4, 4, 5, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(27),
        border: Border.all(color: border),
        boxShadow: const [
          BoxShadow(color: Color(0x12000000), blurRadius: 10, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Cancel recording',
            visualDensity: VisualDensity.compact,
            onPressed: widget.busy ? null : widget.onCancel,
            icon: const Icon(Icons.close_rounded, color: muted, size: 22),
          ),
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: widget.paused ? muted : const Color(0xFFE5484D),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 38,
            child: Text(
              timeLabel,
              style: const TextStyle(fontSize: 12.5, color: ink, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: SizedBox(
              height: 30,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  for (final value in history)
                    Expanded(
                      child: Align(
                        alignment: Alignment.center,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 70),
                          curve: Curves.easeOut,
                          margin: const EdgeInsets.symmetric(horizontal: .45),
                          width: 2.1,
                          height: value == 0 ? 2.2 : (4 + value * 24),
                          decoration: BoxDecoration(
                            color: widget.paused ? muted.withValues(alpha: .28) : ink.withValues(alpha: value == 0 ? .32 : .70),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 5),
          IconButton.filledTonal(
            visualDensity: VisualDensity.compact,
            tooltip: widget.paused ? 'Resume' : 'Pause',
            onPressed: widget.busy ? null : widget.onPauseResume,
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFFF1F1F1),
              foregroundColor: ink,
              minimumSize: const Size(38, 38),
              maximumSize: const Size(38, 38),
            ),
            icon: Icon(widget.paused ? Icons.play_arrow_rounded : Icons.pause_rounded, size: 21),
          ),
          const SizedBox(width: 5),
          IconButton.filled(
            visualDensity: VisualDensity.compact,
            tooltip: 'Send voice note',
            onPressed: widget.busy ? null : widget.onSend,
            style: IconButton.styleFrom(
              backgroundColor: green,
              foregroundColor: Colors.white,
              minimumSize: const Size(40, 40),
              maximumSize: const Size(40, 40),
            ),
            icon: widget.busy
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.arrow_upward_rounded, size: 21),
          ),
        ],
      ),
    );
  }
}
''', encoding='utf-8')

for required_file, required_tokens in {
    'lib/support/support_chat_v6.dart': ['resizeToAvoidBottomInset: !kIsWeb', 'scrollPadding: kIsWeb ? EdgeInsets.zero'],
    'lib/support/support_agent_thread_v2.dart': ['resizeToAvoidBottomInset: !kIsWeb', 'scrollPadding: kIsWeb ? EdgeInsets.zero'],
    'lib/support/support_voice_note.dart': ['playVetVoiceBytes(', 'cachedAudioBytes = null'],
    'lib/support/support_voice_recorder_bar.dart': ["import 'package:flutter/foundation.dart';", 'ValueListenable<double> level', 'List<double>.filled(46, 0)', 'height: value == 0 ? 2.2', 'Icons.arrow_upward_rounded'],
}.items():
    text = Path(required_file).read_text(encoding='utf-8')
    for token in required_tokens:
        if token not in text:
            raise SystemExit(f'V79 verification missing {token} in {required_file}')

print('Vet AI V79 applied: native keyboard stability, reliable iOS voice-file playback, ChatGPT-style live recorder')
