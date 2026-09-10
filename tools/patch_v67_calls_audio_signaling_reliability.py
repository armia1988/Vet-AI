from pathlib import Path
import math
import random
import struct
import wave


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    if old not in text:
        raise SystemExit(f'V67: {label} anchor missing')
    return text.replace(old, new, 1)


# ---------------------------------------------------------------------------
# 1) Package actual short WAV assets. AssetSource is considerably more reliable
#    than runtime BytesSource playback on iOS Safari / WKWebView for tiny cues.
#    These are original Vet AI sounds, not copied from another messenger.
# ---------------------------------------------------------------------------
audio_dir = Path('assets/audio')
audio_dir.mkdir(parents=True, exist_ok=True)


def write_pcm_wav(path: Path, duration: float, fn, sample_rate: int = 22050) -> None:
    count = max(1, int(duration * sample_rate))
    frames = bytearray()
    for i in range(count):
        t = i / sample_rate
        value = max(-1.0, min(1.0, float(fn(t, duration))))
        frames.extend(struct.pack('<h', int(value * 32767)))
    with wave.open(str(path), 'wb') as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sample_rate)
        wf.writeframes(frames)


def knock_send(t: float, d: float) -> float:
    # Dry one-shot tap: fast attack, very short wood-like decay.
    attack = min(1.0, t / 0.0025)
    env = attack * math.exp(-36.0 * t)
    body = 0.56 * math.sin(2 * math.pi * 720 * t) + 0.28 * math.sin(2 * math.pi * 1180 * t)
    thump = 0.16 * math.sin(2 * math.pi * 190 * t) * math.exp(-24.0 * t)
    return 0.52 * env * body + thump


def knock_receive(t: float, d: float) -> float:
    attack = min(1.0, t / 0.003)
    env = attack * math.exp(-31.0 * t)
    body = 0.52 * math.sin(2 * math.pi * 610 * t) + 0.26 * math.sin(2 * math.pi * 930 * t)
    thump = 0.18 * math.sin(2 * math.pi * 165 * t) * math.exp(-21.0 * t)
    return 0.48 * env * body + thump


def incoming_ring(t: float, d: float) -> float:
    cycle = t % 3.2
    active = (0 <= cycle < 0.55) or (0.72 <= cycle < 1.27)
    if not active:
        return 0.0
    local = cycle if cycle < 0.55 else cycle - 0.72
    edge = min(1.0, local / 0.015, max(0.0, (0.55 - local) / 0.03))
    mod = 0.78 + 0.22 * abs(math.sin(2 * math.pi * 9.0 * t))
    tone = 0.58 * math.sin(2 * math.pi * 620 * t) + 0.42 * math.sin(2 * math.pi * 790 * t)
    return 0.30 * edge * mod * tone


def outgoing_ring(t: float, d: float) -> float:
    cycle = t % 3.0
    if cycle >= 0.95:
        return 0.0
    edge = min(1.0, cycle / 0.018, max(0.0, (0.95 - cycle) / 0.035))
    tone = 0.72 * math.sin(2 * math.pi * 425 * t) + 0.28 * math.sin(2 * math.pi * 450 * t)
    return 0.20 * edge * tone


write_pcm_wav(audio_dir / 'vet_ai_chat_send.wav', 0.115, knock_send)
write_pcm_wav(audio_dir / 'vet_ai_chat_receive.wav', 0.135, knock_receive)
write_pcm_wav(audio_dir / 'vet_ai_call_incoming.wav', 3.2, incoming_ring)
write_pcm_wav(audio_dir / 'vet_ai_call_outgoing.wav', 3.0, outgoing_ring)

pubspec = Path('pubspec.yaml')
ps = pubspec.read_text(encoding='utf-8')
if '    - assets/audio/\n' not in ps:
    anchor = '    - assets/icons/\n'
    if anchor not in ps:
        raise SystemExit('V67: pubspec assets anchor missing')
    ps = ps.replace(anchor, anchor + '    - assets/audio/\n', 1)
pubspec.write_text(ps, encoding='utf-8')


# ---------------------------------------------------------------------------
# 2) Chat send / receive sounds use packaged assets and remain one-shot.
# ---------------------------------------------------------------------------
Path('lib/support/support_chat_sound.dart').write_text(r'''import 'package:audioplayers/audioplayers.dart';

/// Original Vet AI one-shot chat cues.
/// Packaged WAV assets are used instead of runtime byte audio so Safari,
/// WKWebView and native iOS all get the same reliable playback path.
class VetSupportChatSound {
  VetSupportChatSound._();

  static final AudioPlayer _sendPlayer = AudioPlayer();
  static final AudioPlayer _receivePlayer = AudioPlayer();
  static bool _unlocked = false;

  static Future<void> unlock() async {
    if (_unlocked) return;
    _unlocked = true;
    try {
      await _sendPlayer.setReleaseMode(ReleaseMode.stop);
      await _receivePlayer.setReleaseMode(ReleaseMode.stop);
      // This call happens from a user gesture in the composer. A zero-volume
      // asset play primes Safari's media permission without an audible click.
      await _sendPlayer.play(
        AssetSource('audio/vet_ai_chat_send.wav'),
        volume: 0.0,
      );
      await _sendPlayer.stop();
    } catch (_) {
      // The next explicit Send tap is still a valid playback gesture.
    }
  }

  static Future<void> playSend() async {
    try {
      _unlocked = true;
      await _sendPlayer.stop();
      await _sendPlayer.setReleaseMode(ReleaseMode.stop);
      await _sendPlayer.play(
        AssetSource('audio/vet_ai_chat_send.wav'),
        volume: 0.62,
      );
    } catch (_) {}
  }

  static Future<void> playReceive() async {
    try {
      await _receivePlayer.stop();
      await _receivePlayer.setReleaseMode(ReleaseMode.stop);
      await _receivePlayer.play(
        AssetSource('audio/vet_ai_chat_receive.wav'),
        volume: 0.54,
      );
    } catch (_) {}
  }
}
''', encoding='utf-8')


# ---------------------------------------------------------------------------
# 3) Foreground/web call tones also use packaged assets. Native iOS CallKit
#    still owns the true system incoming-call ringtone when PushKit wakes it.
# ---------------------------------------------------------------------------
Path('lib/support/support_call_tone.dart').write_text(r'''import 'package:audioplayers/audioplayers.dart';

class VetSupportCallTone {
  VetSupportCallTone._();

  static final AudioPlayer _incomingPlayer = AudioPlayer();
  static final AudioPlayer _outgoingPlayer = AudioPlayer();
  static String? _incomingCallId;
  static bool _incomingPlaying = false;
  static bool _outgoingPlaying = false;
  static bool _unlocked = false;

  static Future<void> unlock() async {
    if (_unlocked) return;
    _unlocked = true;
    try {
      await _incomingPlayer.setReleaseMode(ReleaseMode.loop);
      await _incomingPlayer.play(
        AssetSource('audio/vet_ai_call_incoming.wav'),
        volume: 0.0,
      );
      await _incomingPlayer.stop();
    } catch (_) {}
  }

  static Future<void> startIncoming(String callId) async {
    if (_incomingCallId == callId && _incomingPlaying) return;
    _incomingCallId = callId;
    _incomingPlaying = true;
    await stopOutgoing();
    try {
      await _incomingPlayer.stop();
      await _incomingPlayer.setReleaseMode(ReleaseMode.loop);
      await _incomingPlayer.play(
        AssetSource('audio/vet_ai_call_incoming.wav'),
        volume: 0.88,
      );
    } catch (_) {
      _incomingPlaying = false;
    }
  }

  static Future<void> stopIncoming([String? callId]) async {
    if (callId != null && _incomingCallId != null && _incomingCallId != callId) return;
    _incomingCallId = null;
    _incomingPlaying = false;
    try { await _incomingPlayer.stop(); } catch (_) {}
  }

  static Future<void> startOutgoing() async {
    if (_outgoingPlaying) return;
    _outgoingPlaying = true;
    try {
      await _outgoingPlayer.stop();
      await _outgoingPlayer.setReleaseMode(ReleaseMode.loop);
      await _outgoingPlayer.play(
        AssetSource('audio/vet_ai_call_outgoing.wav'),
        volume: 0.52,
      );
    } catch (_) {
      _outgoingPlaying = false;
    }
  }

  static Future<void> stopOutgoing() async {
    _outgoingPlaying = false;
    try { await _outgoingPlayer.stop(); } catch (_) {}
  }

  static Future<void> stopAll() async {
    await stopIncoming();
    await stopOutgoing();
  }
}
''', encoding='utf-8')


# ---------------------------------------------------------------------------
# 4) WebRTC signaling: do not identify a peer only by auth user id. Admin web
#    and the customer app may deliberately be tested with the same account,
#    and multiple devices/tabs can share one login. Every call page now gets a
#    unique endpoint id; it ignores only its own endpoint's signals.
# ---------------------------------------------------------------------------
p = Path('lib/support/support_call_service.dart')
s = p.read_text(encoding='utf-8')
old_sig = """  Future<void> sendSignal({
    required String callId,
    required String type,
    required Map<String, dynamic> payload,
  }) async {
"""
new_sig = """  Future<void> sendSignal({
    required String callId,
    required String senderRole,
    required String senderClientId,
    required String type,
    required Map<String, dynamic> payload,
  }) async {
"""
s = replace_once(s, old_sig, new_sig, 'sendSignal signature')
old_insert = """      'call_id': callId,
      'sender_id': user.id,
      'signal_type': type,
      'payload': payload,
"""
new_insert = """      'call_id': callId,
      'sender_id': user.id,
      'sender_role': senderRole,
      'sender_client_id': senderClientId,
      'signal_type': type,
      'payload': payload,
"""
s = replace_once(s, old_insert, new_insert, 'sendSignal endpoint columns')
p.write_text(s, encoding='utf-8')

p = Path('lib/support/support_webrtc_call_page.dart')
s = p.read_text(encoding='utf-8')
if '  late final String endpointId;\n' not in s:
    anchor = '  final List<RTCIceCandidate> pendingCandidates = <RTCIceCandidate>[];\n'
    if anchor not in s:
        raise SystemExit('V67: endpoint field anchor missing')
    s = s.replace(anchor, anchor + '  late final String endpointId;\n', 1)

old_init = """  void initState() {
    super.initState();
    unawaited(_initialize());
  }
"""
new_init = """  void initState() {
    super.initState();
    endpointId = '${widget.role}-${DateTime.now().microsecondsSinceEpoch}-${math.Random().nextInt(0x7fffffff)}';
    unawaited(_initialize());
  }
"""
s = replace_once(s, old_init, new_init, 'endpoint init')

# All three signaling calls (candidate / offer / answer) have this argument pair.
s = s.replace(
    "          callId: callId,\n          type:",
    "          callId: callId,\n          senderRole: widget.role,\n          senderClientId: endpointId,\n          type:",
)
s = s.replace(
    "        callId: callId,\n        type:",
    "        callId: callId,\n        senderRole: widget.role,\n        senderClientId: endpointId,\n        type:",
)

old_skip = """      if ('${row['sender_id']}' == userId) continue;

      final type = '${row['signal_type']}';
"""
new_skip = """      final sourceClientId = '${row['sender_client_id'] ?? ''}';
      final sourceRole = '${row['sender_role'] ?? ''}';
      // Ignore only this exact WebRTC endpoint. Falling back to user+role keeps
      // compatibility with transitional rows while allowing the same auth user
      // on a second device/role to complete offer/answer/ICE exchange.
      if (sourceClientId.isNotEmpty && sourceClientId == endpointId) continue;
      if (sourceClientId.isEmpty &&
          '${row['sender_id']}' == userId &&
          sourceRole == widget.role) {
        continue;
      }

      final type = '${row['signal_type']}';
"""
s = replace_once(s, old_skip, new_skip, 'endpoint-aware signal filter')

# Helper.switchCamera on native iOS can return false even after the physical
# lens has already switched. Treat an exception as failure, not that unreliable
# boolean return value, so successful flips never show the red false alarm.
old_camera = """        final switched = await Helper.switchCamera(oldTracks.first);
        if (!switched) throw StateError('Camera switch was not completed.');
        usingFrontCamera = !usingFrontCamera;
"""
new_camera = """        await Helper.switchCamera(oldTracks.first);
        usingFrontCamera = !usingFrontCamera;
"""
s = replace_once(s, old_camera, new_camera, 'native camera false-positive error')

# A remote track alone is not proof that media is usable. Mark connected from
# PeerConnection state; onTrack only attaches the stream and activates audio.
old_track = """      connection.onTrack = (event) {
        if (event.streams.isNotEmpty) {
          remoteRenderer.srcObject = event.streams.first;
        }
        unawaited(_activateRemoteAudio());
        if (mounted) setState(() => connectionLabel = 'Connected');
      };
"""
new_track = """      connection.onTrack = (event) {
        if (event.streams.isNotEmpty) {
          remoteRenderer.srcObject = event.streams.first;
        }
        unawaited(_activateRemoteAudio());
        if (mounted) setState(() {});
      };
"""
s = replace_once(s, old_track, new_track, 'connected state truthfulness')

# On iOS, route active call audio after the peer connection actually connects.
old_connected = """            RTCPeerConnectionState.RTCPeerConnectionStateConnected => 'Connected',
"""
new_connected = """            RTCPeerConnectionState.RTCPeerConnectionStateConnected => 'Connected',
"""
if old_connected not in s:
    raise SystemExit('V67: peer connected state anchor missing')
# Keep switch expression unchanged, then independently activate the route.
state_tail = """        });
      };

      final constraints = <String, dynamic>{
"""
state_tail_new = """        });
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          unawaited(_activateRemoteAudio());
        }
      };

      final constraints = <String, dynamic>{
"""
s = replace_once(s, state_tail, state_tail_new, 'activate audio on connected')

# Verify every signaling call now carries endpoint identity.
if s.count('senderClientId: endpointId') < 3:
    raise SystemExit(f'V67: expected 3 endpoint-aware signal calls, found {s.count("senderClientId: endpointId")}')
for marker in [
    'late final String endpointId;',
    "sourceClientId == endpointId",
    'await Helper.switchCamera(oldTracks.first);',
    'unawaited(_activateRemoteAudio());',
]:
    if marker not in s:
        raise SystemExit(f'V67 call verification missing: {marker}')
p.write_text(s, encoding='utf-8')


# ---------------------------------------------------------------------------
# 5) Prime foreground browser call audio after any deliberate interaction with
#    the support-call layer. A background Safari tab still cannot emulate iOS
#    CallKit; native iOS uses PushKit/CallKit for that.
# ---------------------------------------------------------------------------
p = Path('lib/support/support_incoming_call_overlay.dart')
s = p.read_text(encoding='utf-8')
if "import 'support_chat_sound.dart';" not in s:
    anchor = "import 'support_call_tone.dart';\n"
    if anchor not in s:
        raise SystemExit('V67: incoming layer tone import anchor missing')
    s = s.replace(anchor, anchor + "import 'support_chat_sound.dart';\n", 1)
old_return = """    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: calls.accessibleCallsStream(),
"""
new_return = """    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        unawaited(VetSupportCallTone.unlock());
        unawaited(VetSupportChatSound.unlock());
      },
      child: StreamBuilder<List<Map<String, dynamic>>>(
        stream: calls.accessibleCallsStream(),
"""
if new_return not in s:
    if old_return not in s:
        raise SystemExit('V67: incoming layer StreamBuilder anchor missing')
    s = s.replace(old_return, new_return, 1)
    # Close Listener after the StreamBuilder.
    old_end = """      },
    );
  }
}

class _CallChoice"""
    new_end = """        },
      ),
    );
  }
}

class _CallChoice"""
    if old_end not in s:
        raise SystemExit('V67: incoming layer closing anchor missing')
    s = s.replace(old_end, new_end, 1)
p.write_text(s, encoding='utf-8')

print('Vet AI V67 applied: false camera error removed, endpoint-safe WebRTC signaling, truthful media state, packaged chat knocks and reliable foreground call tones')
