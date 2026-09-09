import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

/// Vet AI's own lightweight call tones.
///
/// These are generated locally so the app does not copy any third-party
/// messenger/phone ringtone. Incoming ringing is deliberately stronger and
/// more phone-like; outgoing ringback is softer.
class VetSupportCallTone {
  VetSupportCallTone._();

  static final AudioPlayer _incomingPlayer = AudioPlayer();
  static final AudioPlayer _outgoingPlayer = AudioPlayer();

  static String? _incomingCallId;
  static bool _incomingPlaying = false;
  static bool _outgoingPlaying = false;

  static final Uint8List _incomingBytes = _buildTone(
    cycleMs: 3200,
    activeWindowsMs: const [
      [0, 520],
      [650, 1170],
    ],
    frequencyA: 620,
    frequencyB: 790,
    modulationHz: 11,
    amplitude: .34,
  );

  static final Uint8List _outgoingBytes = _buildTone(
    cycleMs: 3000,
    activeWindowsMs: const [
      [0, 950],
    ],
    frequencyA: 425,
    frequencyB: 450,
    modulationHz: 0,
    amplitude: .22,
  );

  static Future<void> startIncoming(String callId) async {
    if (_incomingCallId == callId && _incomingPlaying) return;
    _incomingCallId = callId;
    _incomingPlaying = true;
    await stopOutgoing();
    try {
      await _incomingPlayer.stop();
      await _incomingPlayer.setReleaseMode(ReleaseMode.loop);
      await _incomingPlayer.play(BytesSource(_incomingBytes), volume: .82);
    } catch (_) {
      _incomingPlaying = false;
    }
  }

  static Future<void> stopIncoming([String? callId]) async {
    if (callId != null && _incomingCallId != null && _incomingCallId != callId) {
      return;
    }
    _incomingCallId = null;
    _incomingPlaying = false;
    try {
      await _incomingPlayer.stop();
    } catch (_) {}
  }

  static Future<void> startOutgoing() async {
    if (_outgoingPlaying) return;
    _outgoingPlaying = true;
    try {
      await _outgoingPlayer.stop();
      await _outgoingPlayer.setReleaseMode(ReleaseMode.loop);
      await _outgoingPlayer.play(BytesSource(_outgoingBytes), volume: .43);
    } catch (_) {
      _outgoingPlaying = false;
    }
  }

  static Future<void> stopOutgoing() async {
    _outgoingPlaying = false;
    try {
      await _outgoingPlayer.stop();
    } catch (_) {}
  }

  static Future<void> stopAll() async {
    await stopIncoming();
    await stopOutgoing();
  }

  static Uint8List _buildTone({
    required int cycleMs,
    required List<List<int>> activeWindowsMs,
    required double frequencyA,
    required double frequencyB,
    required double modulationHz,
    required double amplitude,
  }) {
    const sampleRate = 22050;
    const bytesPerSample = 2;
    final sampleCount = (sampleRate * cycleMs / 1000).round();
    final dataLength = sampleCount * bytesPerSample;
    final data = ByteData(44 + dataLength);

    void ascii(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        data.setUint8(offset + i, value.codeUnitAt(i));
      }
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

    for (var i = 0; i < sampleCount; i++) {
      final t = i / sampleRate;
      final ms = t * 1000;
      final window = activeWindowsMs.where((w) => ms >= w[0] && ms < w[1]);
      if (window.isEmpty) {
        data.setInt16(44 + i * 2, 0, Endian.little);
        continue;
      }
      final w = window.first;
      final localMs = ms - w[0];
      final durationMs = (w[1] - w[0]).toDouble();
      final edge = math.min(1.0, math.min(localMs / 18, (durationMs - localMs) / 28));
      final modulation = modulationHz <= 0
          ? 1.0
          : .72 + .28 * math.sin(2 * math.pi * modulationHz * t).abs();
      final wave = math.sin(2 * math.pi * frequencyA * t) * .62 +
          math.sin(2 * math.pi * frequencyB * t) * .38;
      final sample = (32767 * amplitude * edge.clamp(0.0, 1.0) * modulation * wave)
          .round()
          .clamp(-32767, 32767)
          .toInt();
      data.setInt16(44 + i * 2, sample, Endian.little);
    }

    return data.buffer.asUint8List();
  }
}
