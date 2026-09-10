from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    if old not in text:
        raise SystemExit(f'V68: {label} anchor missing')
    return text.replace(old, new, 1)


# ---------------------------------------------------------------------------
# 1) WebRTC: Safari/iOS can occasionally deliver an RTCTrackEvent without a
# MediaStream in event.streams. The track was real, but the old UI had nothing
# to attach to the renderer, so users could see a black remote view and/or no
# audible remote track. Build a renderer stream from that track.
# ---------------------------------------------------------------------------
p = Path('lib/support/support_webrtc_call_page.dart')
s = p.read_text(encoding='utf-8')

field_anchor = '  MediaStream? switchedCameraStream;\n'
if '  MediaStream? remoteFallbackStream;\n' not in s:
    if field_anchor not in s:
        field_anchor = '  MediaStream? localStream;\n'
        if field_anchor not in s:
            raise SystemExit('V68: remote fallback field anchor missing')
    s = s.replace(field_anchor, field_anchor + '  MediaStream? remoteFallbackStream;\n', 1)

old_track = """      connection.onTrack = (event) {
        if (event.streams.isNotEmpty) {
          remoteRenderer.srcObject = event.streams.first;
        }
        unawaited(_activateRemoteAudio());
        if (mounted) setState(() {});
      };
"""
new_track = """      connection.onTrack = (event) {
        if (event.streams.isNotEmpty) {
          remoteRenderer.srcObject = event.streams.first;
        } else {
          // Unified-plan Safari may provide a valid remote track with an empty
          // streams list. Attach it to a renderer-owned stream instead of
          // leaving the call black or silent.
          unawaited(_attachStreamlessRemoteTrack(event.track));
        }
        unawaited(_activateRemoteAudio());
        if (mounted) setState(() {});
      };
"""
s = replace_once(s, old_track, new_track, 'streamless remote track')

helper_anchor = '  Future<void> _startRingback() async {\n'
if 'Future<void> _attachStreamlessRemoteTrack(MediaStreamTrack track)' not in s:
    if helper_anchor not in s:
        raise SystemExit('V68: remote fallback helper anchor missing')
    helper = r'''  Future<void> _attachStreamlessRemoteTrack(MediaStreamTrack track) async {
    try {
      var stream = remoteFallbackStream;
      if (stream == null) {
        stream = await createLocalMediaStream('vet-ai-remote-$callId');
        remoteFallbackStream = stream;
      }
      final alreadyAttached = stream.getTracks().any((item) => item.id == track.id);
      if (!alreadyAttached) {
        await stream.addTrack(track, addToNative: false);
      }
      remoteRenderer.srcObject = stream;
      await _activateRemoteAudio();
      if (mounted) setState(() {});
    } catch (_) {
      // The normal event.streams route stays primary. This compatibility path
      // must never tear down an otherwise working call.
    }
  }

'''
    s = s.replace(helper_anchor, helper + helper_anchor, 1)

# Dispose the renderer-only stream with the call.
dispose_anchor = '    localStream?.dispose();\n'
if '    remoteFallbackStream?.dispose();\n' not in s:
    if dispose_anchor not in s:
        raise SystemExit('V68: remote fallback dispose anchor missing')
    s = s.replace(dispose_anchor, dispose_anchor + '    remoteFallbackStream?.dispose();\n', 1)

p.write_text(s, encoding='utf-8')


# ---------------------------------------------------------------------------
# 2) Native iOS CallKit: V65 already bundles vet_ai_incoming_call.caf, but V66
# left ringtoneSound unset. Explicitly select our bundled original phone-style
# ringtone and make the active CallKit audio session explicit on answer.
# ---------------------------------------------------------------------------
app_delegate = Path('ios/Runner/AppDelegate.swift')
if app_delegate.exists():
    native = app_delegate.read_text(encoding='utf-8')
    old = """    configuration.includesCallsInRecents = true
    // Intentionally leave ringtoneSound unset: CallKit uses the iPhone's normal
    // system incoming-call ringtone and respects mute/Focus/accessibility rules.
"""
    new = """    configuration.includesCallsInRecents = true
    // Vet AI original phone-style incoming support-call ringtone. iOS still
    // applies the user's mute, Focus and accessibility rules.
    configuration.ringtoneSound = \"vet_ai_incoming_call.caf\"
"""
    native = replace_once(native, old, new, 'CallKit ringtone selection')

    old_activate = """  func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
    configureVoiceAudio()
  }
"""
    new_activate = """  func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
    configureVoiceAudio()
    try? audioSession.setActive(true)
  }
"""
    native = replace_once(native, old_activate, new_activate, 'CallKit active audio session')
    app_delegate.write_text(native, encoding='utf-8')

    ringtone = Path('ios/Runner/vet_ai_incoming_call.caf')
    if not ringtone.exists() or ringtone.stat().st_size < 1000:
        raise SystemExit('V68: bundled CallKit ringtone is missing')
else:
    print('V68: iOS project not present; native CallKit ringtone step skipped for web build')


call_text = Path('lib/support/support_webrtc_call_page.dart').read_text(encoding='utf-8')
for marker in [
    'remoteFallbackStream',
    '_attachStreamlessRemoteTrack(event.track)',
    "createLocalMediaStream('vet-ai-remote-$callId')",
]:
    if marker not in call_text:
        raise SystemExit(f'V68 call verification missing: {marker}')

if app_delegate.exists():
    native = app_delegate.read_text(encoding='utf-8')
    for marker in [
        'configuration.ringtoneSound = "vet_ai_incoming_call.caf"',
        'try? audioSession.setActive(true)',
    ]:
        if marker not in native:
            raise SystemExit(f'V68 native verification missing: {marker}')

print('Vet AI V68 applied: explicit CallKit ringtone, active iOS call audio, and streamless remote-media fallback')
