from pathlib import Path

p = Path('lib/support/support_webrtc_call_page.dart')
s = p.read_text(encoding='utf-8')

# Audio/ringback support.
if "package:audioplayers/audioplayers.dart" not in s:
    anchor = "import 'dart:async';\n"
    if anchor not in s:
        raise SystemExit('V56: dart async import missing')
    s = s.replace(
        anchor,
        "import 'dart:async';\nimport 'dart:math' as math;\nimport 'dart:typed_data';\n\nimport 'package:audioplayers/audioplayers.dart';\n",
        1,
    )

anchor = "  final calls = VetSupportCallService.instance;\n"
if "final ringPlayer = AudioPlayer();" not in s:
    if anchor not in s:
        raise SystemExit('V56: call service field missing')
    s = s.replace(anchor, anchor + "  final ringPlayer = AudioPlayer();\n", 1)

anchor = "  bool ending = false;\n"
if "bool allowPop = false;" not in s:
    if anchor not in s:
        raise SystemExit('V56: ending field missing')
    s = s.replace(
        anchor,
        anchor + "  bool allowPop = false;\n  String callStatus = 'ringing';\n",
        1,
    )

# Capture the initial call state.
anchor = "      await remoteRenderer.initialize();\n"
if "callStatus = '${widget.call['status'] ?? 'ringing'}';" not in s:
    if anchor not in s:
        raise SystemExit('V56: renderer init anchor missing')
    s = s.replace(
        anchor,
        anchor + "      callStatus = '${widget.call['status'] ?? 'ringing'}';\n",
        1,
    )

# When remote media arrives, stop ringback and force the active audio route.
old = """      connection.onTrack = (event) {
        if (event.streams.isNotEmpty) {
          remoteRenderer.srcObject = event.streams.first;
        }
        if (mounted) setState(() => connectionLabel = 'Connected');
      };
"""
new = """      connection.onTrack = (event) {
        if (event.streams.isNotEmpty) {
          remoteRenderer.srcObject = event.streams.first;
        }
        unawaited(_activateRemoteAudio());
        if (mounted) setState(() => connectionLabel = 'Connected');
      };
"""
if old in s:
    s = s.replace(old, new, 1)
elif "unawaited(_activateRemoteAudio());" not in s:
    raise SystemExit('V56: onTrack anchor missing')

# Explicitly select speaker route once microphone/media permission has been granted.
old = """      for (final track in stream.getTracks()) {
        await connection.addTrack(track, stream);
      }

      signalSubscription = calls.signalsStream(callId).listen(_consumeSignals);
"""
new = """      for (final track in stream.getTracks()) {
        await connection.addTrack(track, stream);
      }
      try {
        await Helper.setSpeakerphoneOn(true);
      } catch (_) {}

      signalSubscription = calls.signalsStream(callId).listen(_consumeSignals);
"""
if old in s:
    s = s.replace(old, new, 1)
elif "await Helper.setSpeakerphoneOn(true);" not in s:
    raise SystemExit('V56: local media anchor missing')

# Keep live call status, stop ringback on answer, and close cleanly when the other side ends.
old = """      callSubscription = calls.callsStream(threadId).listen((rows) {
        final current = rows.where((row) => '${row['id']}' == callId);
        if (current.isEmpty) return;
        final status = '${current.first['status']}';
        if ((status == 'ended' || status == 'declined') && mounted && !ending) {
          Navigator.of(context).maybePop();
        }
      });
"""
new = """      callSubscription = calls.callsStream(threadId).listen((rows) {
        final current = rows.where((row) => '${row['id']}' == callId);
        if (current.isEmpty) return;
        final status = '${current.first['status']}';
        callStatus = status;
        if (status == 'accepted') {
          unawaited(_stopRingback());
        }
        if ((status == 'ended' || status == 'declined') && mounted && !ending) {
          unawaited(_finishRemoteEnd());
          return;
        }
        if (mounted) setState(() {});
      });
"""
if old in s:
    s = s.replace(old, new, 1)
elif "unawaited(_finishRemoteEnd());" not in s:
    raise SystemExit('V56: call subscription anchor missing')

# Start a real local ringback tone for outgoing calls.
old = """      if (mounted) setState(() => ready = true);
    } catch (error) {
"""
new = """      if (mounted) setState(() => ready = true);
      if (widget.isCaller && callStatus == 'ringing') {
        unawaited(_startRingback());
      }
    } catch (error) {
"""
if old in s:
    s = s.replace(old, new, 1)
elif "unawaited(_startRingback());" not in s:
    raise SystemExit('V56: ready anchor missing')

# Add audio lifecycle helpers before the microphone toggle.
anchor = "  Future<void> _toggleMicrophone() async {\n"
if "Future<void> _startRingback() async" not in s:
    if anchor not in s:
        raise SystemExit('V56: microphone method anchor missing')
    helpers = r'''  Future<void> _startRingback() async {
    try {
      await ringPlayer.stop();
      await ringPlayer.setReleaseMode(ReleaseMode.loop);
      await ringPlayer.play(BytesSource(_buildRingbackWav()), volume: .34);
    } catch (_) {
      // Browsers may initially block non-user-gesture audio; the actual WebRTC
      // stream is still attached below and becomes audible after the call is answered.
    }
  }

  Future<void> _stopRingback() async {
    try {
      await ringPlayer.stop();
    } catch (_) {}
  }

  Future<void> _activateRemoteAudio() async {
    await _stopRingback();
    try {
      await Helper.setSpeakerphoneOn(speakerEnabled);
    } catch (_) {}
  }

  Future<void> _finishRemoteEnd() async {
    if (ending) return;
    ending = true;
    await _stopRingback();
    if (!mounted) return;
    setState(() {
      allowPop = true;
      connectionLabel = 'Ended';
    });
    await Future<void>.delayed(const Duration(milliseconds: 20));
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

'''
    s = s.replace(anchor, helpers + anchor, 1)

# Fix the hang-up bug: PopScope(canPop:false) was preventing maybePop from ever closing.
old = """  Future<void> _hangUp() async {
    if (ending) return;
    ending = true;
    try {
      await calls.end(callId);
    } catch (_) {}
    if (mounted) Navigator.of(context).maybePop();
  }
"""
new = """  Future<void> _hangUp() async {
    if (ending) return;
    ending = true;
    await _stopRingback();
    try {
      await calls.end(callId);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      allowPop = true;
      connectionLabel = 'Ended';
    });
    await Future<void>.delayed(const Duration(milliseconds: 20));
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }
"""
if old in s:
    s = s.replace(old, new, 1)
elif "allowPop = true;" not in s:
    raise SystemExit('V56: hangup anchor missing')

# Dispose ring player too.
anchor = "  void dispose() {\n"
if "ringPlayer.dispose();" not in s:
    idx = s.find(anchor)
    if idx < 0:
        raise SystemExit('V56: dispose anchor missing')
    target = "    signalSubscription?.cancel();\n"
    if target not in s[idx:]:
        raise SystemExit('V56: dispose subscription anchor missing')
    s = s.replace(target, "    unawaited(ringPlayer.dispose());\n" + target, 1)

# PopScope now blocks accidental back navigation only until the call has been ended.
s = s.replace("      canPop: false,\n", "      canPop: allowPop,\n", 1)

# Voice calls need a mounted remote WebRTC media element on web/iOS Safari.
anchor = "              if (isVideo && localRenderer.srcObject != null)\n"
if "V56 remote audio renderer" not in s:
    if anchor not in s:
        raise SystemExit('V56: video preview anchor missing')
    widget = """              // V56 remote audio renderer: audio-only WebRTC must still have a
              // mounted media element on Flutter Web/Safari or the remote track can be silent.
              if (!isVideo)
                Positioned(
                  left: 0,
                  top: 0,
                  width: 2,
                  height: 2,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: .01,
                      child: RTCVideoView(remoteRenderer),
                    ),
                  ),
                ),
"""
    s = s.replace(anchor, widget + anchor, 1)

# Ringing state is clearer than generic Connecting/STUN while waiting for the other side.
old = """    final translated = switch (connectionLabel) {
      'Connected' => _ct(context, 'Connected', 'متصل', 'Verbonden'),
"""
new = """    if (callStatus == 'ringing' && connectionLabel != 'Connected') {
      final ringing = _ct(context, 'Ringing…', 'بيرن…', 'Gaat over…');
      return turnConfigured ? '$ringing • TURN/WebRTC' : '$ringing • STUN';
    }
    final translated = switch (connectionLabel) {
      'Connected' => _ct(context, 'Connected', 'متصل', 'Verbonden'),
"""
if old in s:
    s = s.replace(old, new, 1)
elif "final ringing = _ct(context, 'Ringing…'" not in s:
    raise SystemExit('V56: status text anchor missing')

# Generate a short European-style ringback WAV in memory, so no binary asset is required.
anchor = "class _WaitingView extends StatelessWidget {\n"
if "Uint8List _buildRingbackWav()" not in s:
    if anchor not in s:
        raise SystemExit('V56: waiting view anchor missing')
    helper = r'''Uint8List _buildRingbackWav() {
  const sampleRate = 8000;
  const seconds = 3;
  const channels = 1;
  const bitsPerSample = 16;
  final sampleCount = sampleRate * seconds;
  final dataSize = sampleCount * 2;
  final bytes = ByteData(44 + dataSize);

  void ascii(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      bytes.setUint8(offset + i, value.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  bytes.setUint32(4, 36 + dataSize, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, channels, Endian.little);
  bytes.setUint32(24, sampleRate, Endian.little);
  bytes.setUint32(28, sampleRate * channels * bitsPerSample ~/ 8, Endian.little);
  bytes.setUint16(32, channels * bitsPerSample ~/ 8, Endian.little);
  bytes.setUint16(34, bitsPerSample, Endian.little);
  ascii(36, 'data');
  bytes.setUint32(40, dataSize, Endian.little);

  for (var i = 0; i < sampleCount; i++) {
    final time = i / sampleRate;
    final cycle = time % seconds;
    final active = cycle < 1.0;
    final sample = active
        ? ((math.sin(2 * math.pi * 425 * time) * 0.72 +
                    math.sin(2 * math.pi * 450 * time) * 0.28) *
                4200)
            .round()
        : 0;
    bytes.setInt16(44 + i * 2, sample, Endian.little);
  }
  return bytes.buffer.asUint8List();
}

'''
    s = s.replace(anchor, helper + anchor, 1)

p.write_text(s, encoding='utf-8')
print('Vet AI V56 applied: audible remote voice media, ringback tone, speaker route, and reliable hang-up navigation')
