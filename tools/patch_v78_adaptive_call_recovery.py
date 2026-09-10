from pathlib import Path

p = Path('lib/support/support_webrtc_call_page.dart')
s = p.read_text(encoding='utf-8')

# V78: make support calls recover automatically from short 5G/Wi-Fi/NAT path
# failures without tearing down microphone/camera or forcing the user to redial.
# TURN is still used automatically when configured; this improves the free
# direct/STUN path as far as WebRTC can reasonably go without a relay.

field_anchor = "  String connectionLabel = 'Connecting';\n"
field_insert = """  String connectionLabel = 'Connecting';
  Timer? recoveryTimer;
  Timer? connectionWatchdog;
  int recoveryAttempt = 0;
  bool recoveryInFlight = false;
  bool adaptiveVideoPaused = false;
"""
if 'Timer? recoveryTimer;' not in s:
    if field_anchor not in s:
        raise SystemExit('V78: connection field anchor missing')
    s = s.replace(field_anchor, field_insert, 1)

old_guard = "if (connection == null || sdp == null || sdp.isEmpty || remoteDescriptionSet)"
if old_guard in s:
    s = s.replace(old_guard, "if (connection == null || sdp == null || sdp.isEmpty)")

connected_audio = """        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          unawaited(_activateRemoteAudio());
        }
"""
if '_handleAdaptivePeerState(state);' not in s:
    if connected_audio in s:
        s = s.replace(connected_audio, connected_audio + "        _handleAdaptivePeerState(state);\n", 1)
    else:
        raise SystemExit('V78: peer-state hook anchor missing')

method_anchor = "  Future<void> _consumeSignals(List<Map<String, dynamic>> rows) async {\n"
if 'Future<void> _restartIceNegotiation() async {' not in s:
    methods = r'''  void _handleAdaptivePeerState(RTCPeerConnectionState state) {
    if (ending) return;
    switch (state) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        recoveryTimer?.cancel();
        recoveryTimer = null;
        connectionWatchdog?.cancel();
        recoveryAttempt = 0;
        recoveryInFlight = false;
        if (adaptiveVideoPaused) {
          adaptiveVideoPaused = false;
          if (cameraEnabled) {
            for (final track in localStream?.getVideoTracks() ?? const <MediaStreamTrack>[]) {
              track.enabled = true;
            }
          }
        }
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        _scheduleRecovery(const Duration(milliseconds: 1400));
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        _scheduleRecovery(const Duration(milliseconds: 250));
        break;
      default:
        break;
    }
  }

  void _scheduleRecovery(Duration initialDelay) {
    if (ending || !widget.isCaller || recoveryInFlight || recoveryTimer?.isActive == true) {
      return;
    }
    final delays = <Duration>[
      initialDelay,
      const Duration(seconds: 2),
      const Duration(seconds: 4),
      const Duration(seconds: 7),
      const Duration(seconds: 10),
    ];
    final index = recoveryAttempt < delays.length ? recoveryAttempt : delays.length - 1;
    recoveryTimer = Timer(delays[index], () {
      recoveryTimer = null;
      unawaited(_restartIceNegotiation());
    });
  }

  Future<void> _restartIceNegotiation() async {
    final connection = peer;
    if (ending || !widget.isCaller || connection == null || recoveryInFlight) return;
    recoveryInFlight = true;
    recoveryAttempt += 1;

    if (isVideo && recoveryAttempt >= 3 && !adaptiveVideoPaused) {
      adaptiveVideoPaused = true;
      for (final track in localStream?.getVideoTracks() ?? const <MediaStreamTrack>[]) {
        track.enabled = false;
      }
    }

    if (mounted) setState(() => connectionLabel = 'Reconnecting');

    try {
      final offer = await connection.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': isVideo,
        'iceRestart': true,
      });
      await connection.setLocalDescription(offer);
      await calls.sendSignal(
        callId: callId,
        senderRole: widget.role,
        senderClientId: endpointId,
        type: 'offer',
        payload: {
          'sdp': offer.sdp,
          'type': offer.type,
          'iceRestart': true,
          'attempt': recoveryAttempt,
        },
      );

      connectionWatchdog?.cancel();
      connectionWatchdog = Timer(const Duration(seconds: 6), () {
        recoveryInFlight = false;
        if (!ending && widget.isCaller) {
          _scheduleRecovery(const Duration(seconds: 1));
        }
      });
    } catch (_) {
      recoveryInFlight = false;
      _scheduleRecovery(const Duration(seconds: 1));
    }
  }

'''
    if method_anchor not in s:
        raise SystemExit('V78: consume-signals anchor missing')
    s = s.replace(method_anchor, methods + method_anchor, 1)

old_answer_gate = """    if (!widget.isCaller) {
      final answer = await connection.createAnswer({
"""
new_answer_gate = """    {
      final answer = await connection.createAnswer({
"""
if old_answer_gate in s:
    s = s.replace(old_answer_gate, new_answer_gate, 1)

answer_tail = """    remoteDescriptionSet = true;
    await _flushCandidates();
  }

  Future<void> _handleCandidate"""
answer_tail_new = """    remoteDescriptionSet = true;
    recoveryInFlight = false;
    connectionWatchdog?.cancel();
    await _flushCandidates();
  }

  Future<void> _handleCandidate"""
if answer_tail in s:
    s = s.replace(answer_tail, answer_tail_new, 1)

# Generated versions differ in which subscription is cancelled first. Hook the
# method declaration itself instead of depending on the next line.
if '    recoveryTimer?.cancel();\n    connectionWatchdog?.cancel();\n' not in s:
    dispose_decl = "  void dispose() {\n"
    if dispose_decl not in s:
        raise SystemExit('V78: dispose declaration missing')
    s = s.replace(
        dispose_decl,
        dispose_decl + "    recoveryTimer?.cancel();\n    connectionWatchdog?.cancel();\n",
        1,
    )

for required in [
    'Timer? recoveryTimer;',
    '_handleAdaptivePeerState(state);',
    "'iceRestart': true",
    'Future<void> _restartIceNegotiation() async {',
    'adaptiveVideoPaused = true;',
    'recoveryTimer?.cancel();',
    'connectionWatchdog?.cancel();',
]:
    if required not in s:
        raise SystemExit(f'V78 verification missing: {required}')

p.write_text(s, encoding='utf-8')
print('Vet AI V78 applied: adaptive ICE restart, reconnect backoff, audio-first fallback, timer-safe recovery')
