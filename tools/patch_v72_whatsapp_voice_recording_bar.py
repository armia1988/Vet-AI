from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    if old not in text:
        raise SystemExit(f'V72: {label} anchor missing')
    return text.replace(old, new, 1)


# ---------------------------------------------------------------------------
# Shared WhatsApp-style recording bar: delete, timer/waveform, pause/resume,
# and a dedicated green Send button. This is an original Vet AI implementation
# of the familiar voice-note interaction pattern.
# ---------------------------------------------------------------------------
Path('lib/support/support_voice_recorder_bar.dart').write_text(r'''import 'package:flutter/material.dart';

class VetSupportVoiceRecorderBar extends StatefulWidget {
  const VetSupportVoiceRecorderBar({
    super.key,
    required this.seconds,
    required this.paused,
    required this.busy,
    required this.onCancel,
    required this.onPauseResume,
    required this.onSend,
  });

  final int seconds;
  final bool paused;
  final bool busy;
  final VoidCallback onCancel;
  final VoidCallback onPauseResume;
  final VoidCallback onSend;

  @override
  State<VetSupportVoiceRecorderBar> createState() => _VetSupportVoiceRecorderBarState();
}

class _VetSupportVoiceRecorderBarState extends State<VetSupportVoiceRecorderBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController animation;

  @override
  void initState() {
    super.initState();
    animation = AnimationController(vsync: this, duration: const Duration(milliseconds: 680))..repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant VetSupportVoiceRecorderBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.paused && animation.isAnimating) {
      animation.stop();
    } else if (!widget.paused && !animation.isAnimating) {
      animation.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    animation.dispose();
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
    const pattern = <double>[6, 12, 9, 17, 8, 14, 20, 11, 7, 16, 10, 19, 8, 13, 18, 9, 15, 7, 12, 16, 9, 14];

    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Delete recording',
            onPressed: widget.busy ? null : widget.onCancel,
            icon: const Icon(Icons.delete_outline_rounded, color: muted, size: 26),
          ),
          const SizedBox(width: 2),
          Text(timeLabel, style: const TextStyle(fontSize: 14, color: Color(0xFF3B4A54), fontWeight: FontWeight.w600)),
          const SizedBox(width: 10),
          Expanded(
            child: AnimatedBuilder(
              animation: animation,
              builder: (context, _) {
                final pulse = widget.paused ? .35 : (.35 + animation.value * .65);
                return SizedBox(
                  height: 28,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      for (var i = 0; i < pattern.length; i++)
                        Expanded(
                          child: Align(
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: .7),
                              height: pattern[i] * (i.isEven ? pulse : (.72 + pulse * .28)),
                              decoration: BoxDecoration(
                                color: muted.withValues(alpha: widget.paused ? .45 : .72),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.mic_rounded, color: red, size: 18),
          const SizedBox(width: 5),
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
                  : const Icon(Icons.send_rounded, color: Colors.white, size: 25),
            ),
          ),
          const SizedBox(width: 5),
        ],
      ),
    );
  }
}
''', encoding='utf-8')


# ---------------------------------------------------------------------------
# Recorder pause/resume support.
# ---------------------------------------------------------------------------
p = Path('lib/support/support_voice_note.dart')
s = p.read_text(encoding='utf-8')
if '  bool _paused = false;\n' not in s:
    s = replace_once(s, '  bool _recording = false;\n', '  bool _recording = false;\n  bool _paused = false;\n', 'recorder paused field')
if '  bool get paused => _paused;\n' not in s:
    s = replace_once(s, '  bool get recording => _recording;\n', '  bool get recording => _recording;\n  bool get paused => _paused;\n', 'recorder paused getter')

s = s.replace('    _startedAt = DateTime.now();\n    _recording = true;\n', '    _startedAt = DateTime.now();\n    _paused = false;\n    _recording = true;\n', 1)

if '  Future<void> pause() async {' not in s:
    marker = '  Future<VetSupportVoiceClip?> stop() async {\n'
    methods = r'''  Future<void> pause() async {
    if (!_recording || _paused) return;
    await _recorder.pause();
    _paused = true;
  }

  Future<void> resume() async {
    if (!_recording || !_paused) return;
    await _recorder.resume();
    _paused = false;
  }

'''
    if marker not in s:
        raise SystemExit('V72: recorder stop marker missing')
    s = s.replace(marker, methods + marker, 1)

s = s.replace('    _recording = false;\n    await _recorder.stop();\n', '    _recording = false;\n    _paused = false;\n    await _recorder.stop();\n', 1)
s = s.replace('      _recording = false;\n      try { await _recorder.cancel(); } catch (_) {}\n', '      _recording = false;\n      _paused = false;\n      try { await _recorder.cancel(); } catch (_) {}\n', 1)
p.write_text(s, encoding='utf-8')


# ---------------------------------------------------------------------------
# Customer composer.
# ---------------------------------------------------------------------------
p = Path('lib/support/support_chat_v6.dart')
s = p.read_text(encoding='utf-8')
if "import 'support_voice_recorder_bar.dart';" not in s:
    s = replace_once(s, "import 'support_voice_note.dart';\n", "import 'support_voice_note.dart';\nimport 'support_voice_recorder_bar.dart';\n", 'customer recorder bar import')

if '  bool voicePaused = false;\n' not in s:
    s = replace_once(s, '  int voiceSeconds = 0;\n', '  int voiceSeconds = 0;\n  bool voicePaused = false;\n', 'customer paused state')

s = s.replace('        recordingVoice = true;\n        voiceSeconds = 0;\n', '        recordingVoice = true;\n        voicePaused = false;\n        voiceSeconds = 0;\n', 1)
s = s.replace('        if (!mounted || !recordingVoice) return;\n        setState(() => voiceSeconds += 1);\n', '        if (!mounted || !recordingVoice || voicePaused) return;\n        setState(() => voiceSeconds += 1);\n', 1)
s = s.replace('      recordingVoice = false;\n      sending = true;\n', '      recordingVoice = false;\n      voicePaused = false;\n      sending = true;\n', 1)
s = s.replace('      recordingVoice = false;\n      voiceSeconds = 0;\n', '      recordingVoice = false;\n      voicePaused = false;\n      voiceSeconds = 0;\n', 1)

if 'Future<void> _toggleVoicePause() async {' not in s:
    marker = '  Future<void> _toggleVoiceRecording() async {\n'
    method = r'''  Future<void> _toggleVoicePause() async {
    if (!recordingVoice || sending) return;
    try {
      if (voicePaused) {
        await voiceRecorder.resume();
      } else {
        await voiceRecorder.pause();
      }
      if (mounted) setState(() => voicePaused = !voicePaused);
    } catch (_) {}
  }

'''
    if marker not in s:
        raise SystemExit('V72: customer voice toggle marker missing')
    s = s.replace(marker, method + marker, 1)

customer_row = '                  child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [\n'
customer_ternary = """                  child: recordingVoice
                      ? VetSupportVoiceRecorderBar(
                          seconds: voiceSeconds,
                          paused: voicePaused,
                          busy: sending,
                          onCancel: () => unawaited(_cancelVoiceRecording()),
                          onPauseResume: () => unawaited(_toggleVoicePause()),
                          onSend: () => unawaited(_finishVoiceRecording()),
                        )
                      : Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
"""
s = replace_once(s, customer_row, customer_ternary, 'customer recording composer')
p.write_text(s, encoding='utf-8')


# ---------------------------------------------------------------------------
# Admin/support-agent composer.
# ---------------------------------------------------------------------------
p = Path('lib/support/support_agent_thread_v2.dart')
s = p.read_text(encoding='utf-8')
if "import 'support_voice_recorder_bar.dart';" not in s:
    s = replace_once(s, "import 'support_voice_note.dart';\n", "import 'support_voice_note.dart';\nimport 'support_voice_recorder_bar.dart';\n", 'agent recorder bar import')
if '  bool voicePaused = false;\n' not in s:
    s = replace_once(s, '  int voiceSeconds = 0;\n', '  int voiceSeconds = 0;\n  bool voicePaused = false;\n', 'agent paused state')

# There is one second begin/timer/finish block in the agent state after the
# customer file has already been written separately.
s = s.replace('        recordingVoice = true;\n        voiceSeconds = 0;\n', '        recordingVoice = true;\n        voicePaused = false;\n        voiceSeconds = 0;\n', 1)
s = s.replace('        if (!mounted || !recordingVoice) return;\n        setState(() => voiceSeconds += 1);\n', '        if (!mounted || !recordingVoice || voicePaused) return;\n        setState(() => voiceSeconds += 1);\n', 1)
s = s.replace('      recordingVoice = false;\n      sending = true;\n', '      recordingVoice = false;\n      voicePaused = false;\n      sending = true;\n', 1)

if 'Future<void> _cancelVoiceRecording() async {' not in s:
    marker = '  Future<void> _toggleVoiceRecording() async {\n'
    methods = r'''  Future<void> _cancelVoiceRecording() async {
    voiceTimer?.cancel();
    voiceTimer = null;
    await voiceRecorder.cancel();
    if (mounted) setState(() {
      recordingVoice = false;
      voicePaused = false;
      voiceSeconds = 0;
    });
  }

  Future<void> _toggleVoicePause() async {
    if (!recordingVoice || sending) return;
    try {
      if (voicePaused) {
        await voiceRecorder.resume();
      } else {
        await voiceRecorder.pause();
      }
      if (mounted) setState(() => voicePaused = !voicePaused);
    } catch (_) {}
  }

'''
    if marker not in s:
        raise SystemExit('V72: agent voice toggle marker missing')
    s = s.replace(marker, methods + marker, 1)

agent_row = """              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
"""
agent_ternary = """              child: recordingVoice
                  ? VetSupportVoiceRecorderBar(
                      seconds: voiceSeconds,
                      paused: voicePaused,
                      busy: sending,
                      onCancel: () => unawaited(_cancelVoiceRecording()),
                      onPauseResume: () => unawaited(_toggleVoicePause()),
                      onSend: () => unawaited(_finishVoiceRecording()),
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
"""
s = replace_once(s, agent_row, agent_ternary, 'agent recording composer')
p.write_text(s, encoding='utf-8')


checks = {
    'lib/support/support_voice_note.dart': ['Future<void> pause()', 'Future<void> resume()', 'bool get paused'],
    'lib/support/support_voice_recorder_bar.dart': ['VetSupportVoiceRecorderBar', 'Icons.pause_rounded', 'Icons.send_rounded', 'Icons.delete_outline_rounded'],
    'lib/support/support_chat_v6.dart': ['VetSupportVoiceRecorderBar(', '_toggleVoicePause()', 'voicePaused'],
    'lib/support/support_agent_thread_v2.dart': ['VetSupportVoiceRecorderBar(', '_cancelVoiceRecording()', '_toggleVoicePause()', 'voicePaused'],
}
for path, markers in checks.items():
    text = Path(path).read_text(encoding='utf-8')
    for marker in markers:
        if marker not in text:
            raise SystemExit(f'V72 verification missing: {path} / {marker}')

print('Vet AI V72 applied: WhatsApp-style voice recording bar with timer, waveform, pause/resume, delete and send')
