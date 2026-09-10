from pathlib import Path


def replace_required(text: str, old: str, new: str, label: str, count: int = 1) -> str:
    if new in text:
        return text
    if old not in text:
        raise SystemExit(f'V77: {label} anchor missing')
    return text.replace(old, new, count)


# ---------------------------------------------------------------------------
# 1) iOS Safari keyboard stability.
# Safari already resizes its visual viewport for the software keyboard. Letting
# Flutter's Scaffold resize again causes the double-shrink / giant blank chat
# area / composer jumping seen on iPhone. Keep the chat scaffold fixed and let
# Safari own the viewport resize. Also remove the large 140 px TextField scroll
# padding that was pushing the whole page upward on focus.
# ---------------------------------------------------------------------------
for file_path in [
    'lib/support/support_chat_v6.dart',
    'lib/support/support_agent_thread_v2.dart',
]:
    p = Path(file_path)
    s = p.read_text(encoding='utf-8')
    s = s.replace('resizeToAvoidBottomInset: true,', 'resizeToAvoidBottomInset: false,')
    s = s.replace('scrollPadding: const EdgeInsets.only(bottom: 140),', 'scrollPadding: EdgeInsets.zero,')
    p.write_text(s, encoding='utf-8')

# Admin chat auto-scroll must not animate the entire viewport while the iOS
# keyboard is visible. A direct jump keeps the last message visible without the
# visible up/down oscillation in Safari.
p = Path('lib/support/support_agent_thread_v2.dart')
s = p.read_text(encoding='utf-8')
old = """      if (animated) {
        scroll.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      } else {
        scroll.jumpTo(target);
      }
"""
new = """      final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
      if (animated && !keyboardVisible) {
        scroll.animateTo(
          target,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        );
      } else {
        scroll.jumpTo(target);
      }
"""
s = replace_required(s, old, new, 'admin keyboard-safe autoscroll')
p.write_text(s, encoding='utf-8')


# ---------------------------------------------------------------------------
# 2) Voice-note playback reliability on iOS app + Safari.
# The old path fetched a signed URL only after the user's tap. Safari can revoke
# the transient user gesture while that network await is happening, so audio
# playback becomes intermittent or completely silent. Preload the private WAV
# bytes when the bubble appears and start BytesSource directly on tap.
# ---------------------------------------------------------------------------
p = Path('lib/support/support_voice_note.dart')
s = p.read_text(encoding='utf-8')
field_anchor = """  Duration position = Duration.zero;
  Duration total = Duration.zero;
"""
field_new = """  Duration position = Duration.zero;
  Duration total = Duration.zero;
  Uint8List? cachedAudioBytes;
  Future<void>? preloadTask;
"""
s = replace_required(s, field_anchor, field_new, 'voice preload fields')

init_anchor = """    total = Duration(milliseconds: durationMs);
    unawaited(player.setReleaseMode(ReleaseMode.stop));
"""
init_new = """    total = Duration(milliseconds: durationMs);
    unawaited(player.setReleaseMode(ReleaseMode.stop));
    preloadTask = _preloadAudio();
"""
s = replace_required(s, init_anchor, init_new, 'voice preload init')

method_anchor = """  Future<void> toggle() async {
"""
if 'Future<void> _preloadAudio() async {' not in s:
    preload_method = r'''  Future<void> _preloadAudio() async {
    final path = '${widget.row['attachment_path'] ?? ''}'.trim();
    if (path.isEmpty || cachedAudioBytes != null) return;
    try {
      final bytes = await VetBackend.instance.downloadSupportAttachment(path);
      if (bytes.isNotEmpty) cachedAudioBytes = bytes;
    } catch (_) {
      // A tap will retry the same authenticated byte download if preload failed.
    }
  }

'''
    if method_anchor not in s:
        raise SystemExit('V77: voice toggle anchor missing')
    s = s.replace(method_anchor, preload_method + method_anchor, 1)

start = s.find('  Future<void> toggle() async {')
end = s.find('\n  Future<void> seek(', start)
if start < 0 or end < 0:
    raise SystemExit('V77: voice toggle method bounds missing')
new_toggle = r'''  Future<void> toggle() async {
    if (loading) return;
    if (playing) {
      await player.pause();
      if (mounted) setState(() => playing = false);
      return;
    }
    setState(() => loading = true);
    try {
      var bytes = cachedAudioBytes;
      if (bytes == null || bytes.isEmpty) {
        await (preloadTask ??= _preloadAudio());
        bytes = cachedAudioBytes;
      }
      if (bytes == null || bytes.isEmpty) {
        // The first preload can fail after a stale auth/session transition.
        preloadTask = _preloadAudio();
        await preloadTask;
        bytes = cachedAudioBytes;
      }
      if (bytes == null || bytes.isEmpty) {
        throw StateError('Voice attachment unavailable');
      }
      await player.play(BytesSource(bytes), position: position);
      if (mounted) setState(() => playing = true);
    } catch (_) {
      if (mounted) setState(() => playing = false);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }
'''
s = s[:start] + new_toggle + s[end:]

for required in [
    'Uint8List? cachedAudioBytes;',
    'preloadTask = _preloadAudio();',
    'downloadSupportAttachment(path)',
    'BytesSource(bytes)',
]:
    if required not in s:
        raise SystemExit(f'V77 voice verification missing: {required}')
p.write_text(s, encoding='utf-8')


# ---------------------------------------------------------------------------
# 3) Reduce call freezes/crashes on iPhone and mobile Safari.
# 1280x720 capture is unnecessarily expensive for a small support-call UI and
# can spike memory/encoder load. Use a conservative mobile profile and request
# a small ICE candidate pool. TURN remains supported automatically whenever a
# production TURN server is configured in Supabase.
# ---------------------------------------------------------------------------
p = Path('lib/support/support_webrtc_call_page.dart')
s = p.read_text(encoding='utf-8')
s = s.replace(
    """      final connection = await createPeerConnection({
        'iceServers': iceServers,
        'sdpSemantics': 'unified-plan',
      });
""",
    """      final connection = await createPeerConnection({
        'iceServers': iceServers,
        'sdpSemantics': 'unified-plan',
        'iceTransportPolicy': 'all',
        'bundlePolicy': 'max-bundle',
        'rtcpMuxPolicy': 'require',
        'iceCandidatePoolSize': 2,
      });
""",
)
s = s.replace(
    """                'width': <String, dynamic>{'ideal': 1280},
                'height': <String, dynamic>{'ideal': 720},
""",
    """                'width': <String, dynamic>{'ideal': 640, 'max': 960},
                'height': <String, dynamic>{'ideal': 480, 'max': 720},
                'frameRate': <String, dynamic>{'ideal': 20, 'max': 24},
""",
)

# Avoid declaring a call connected merely because a track object arrived; on
# iOS this can happen before ICE has a viable path, which produces the brief
# one-second picture followed by an immediate reconnect banner. Connection
# state is the authoritative source.
s = s.replace(
    """        if (mounted) setState(() => connectionLabel = 'Connected');
""",
    """        if (mounted && connectionLabel == 'Connecting') setState(() {});
""",
)

for required in [
    "'iceCandidatePoolSize': 2",
    "'ideal': 640",
    "'frameRate': <String, dynamic>{'ideal': 20, 'max': 24}",
]:
    if required not in s:
        raise SystemExit(f'V77 call verification missing: {required}')
p.write_text(s, encoding='utf-8')

print('Vet AI V77 applied: stable iOS Safari keyboard, preloaded voice-note playback, lower-memory WebRTC video')
