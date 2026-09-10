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
  DateTime lastConnectedAt = DateTime.now();
"""
if 'Timer? recoveryTimer;' not in s:
    if field_anchor not in s:
        raise SystemExit('V78: connection field anchor missing')
    s = s.replace(field_anchor, field_insert, 1)

# A new ICE-restart offer/answer is a legitimate new remote description. The
# old one-shot guard prevented recovery negotiation after the initial call.
old_guard = "if (connection == null || sdp == null || sdp.isEmpty || remoteDescriptionSet)"
if old_guard in s:
    s = s.replace(old_guard, "if (connection == null || sdp == null || sdp.isEmpty)")

# Feed PeerConnection state into the recovery controller. V67 already routes
# audio here when connected; hook immediately after that block when available.
connected_audio = """        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          unawaited(_activateRemoteAudio());
        }
"""
if '_handleAdaptivePeerState(state);' not in s:
    if connected_audio in s:
        s = s.replace(
            connected_audio,
            connected_audio + "        _handleAdaptivePeerState(state);\n",
            1,
        )
    else:
        # Compatibility fallback for generated variants that do not contain
        # the audio-routing hook.
        marker = """      final constraints = <String, dynamic>{
"""
        if marker not in s:
            raise SystemExit('V78: peer-state insertion anchor missing')
        # Find the final callback close directly before media constraints.
        prefix = s[:s.index(marker)]
        idx = prefix.rfind('      };\n')
        if idx < 0:
            raise SystemExit('V78: connection callback close missing')
        idx += len('      };\n')
        s = s[:idx] + "        _handleAdaptivePeerState(state);\n" + s[idx:]

# Insert the adaptive recovery implementation before signal consumption.
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
        lastConnectedAt = DateTime.now();
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
    final delay = delays[recoveryAttempt.clamp(0, delays.length - 1)];
    recoveryTimer = Timer(delay, () {
      recoveryTimer = null;
      unawaited(_restartIceNegotiation());
    });
  }

  Future<void> _restartIceNegotiation() async {
    final connection = peer;
    if (ending || !widget.isCaller || connection == null || recoveryInFlight) return;
    recoveryInFlight = true;
    recoveryAttempt += 1;

    // If repeated retries fail, temporarily stop transmitting video so audio
    // gets the available bandwidth. Video resumes automatically on connection.
    if (isVideo && recoveryAttempt >= 3 && !adaptiveVideoPaused) {
      adaptiveVideoPaused = true;
      for (final track in localStream?.getVideoTracks() ?? const <MediaStreamTrack>[]) {
        track.enabled = false;
      }
    }

    if (mounted) {
      setState(() => connectionLabel = 'Reconnecting');
    }

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

# When a recovery offer arrives, answer it even if this endpoint was the
# original caller in an unusual role/device topology. The original callee path
# remains unchanged; caller glare is avoided because only isCaller initiates
# automatic restarts.
old_answer_gate = """    if (!widget.isCaller) {
      final answer = await connection.createAnswer({
"""
new_answer_gate = """    {
      final answer = await connection.createAnswer({
"""
if old_answer_gate in s:
    s = s.replace(old_answer_gate, new_answer_gate, 1)

# Avoid ending a valid call because the watchdog from an older restart fires.
# Any successfully applied remote answer releases the restart lock.
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

# Cancel all timers before disposing the peer; otherwise a delayed retry can
# run against an already closed RTCPeerConnection.
dispose_anchor = """  void dispose() {
    signalSubscription?.cancel();
"""
dispose_new = """  void dispose() {
    recoveryTimer?.cancel();
    connectionWatchdog?.cancel();
    signalSubscription?.cancel();
"""
if dispose_new not in s:
    if dispose_anchor not in s:
        raise SystemExit('V78: dispose anchor missing')
    s = s.replace(dispose_anchor, dispose_new, 1)

for required in [
    'Timer? recoveryTimer;',
    '_handleAdaptivePeerState(state);',
    "'iceRestart': true",
    'Future<void> _restartIceNegotiation() async {',
    'adaptiveVideoPaused = true;',
    'connectionWatchdog?.cancel();',
]:
    if required not in s:
        raise SystemExit(f'V78 verification missing: {required}')

p.write_text(s, encoding='utf-8')
print('Vet AI V78 applied: adaptive ICE restart, reconnect backoff, audio-first fallback, timer-safe recovery')
