import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

/// Short original Vet AI chat cues.
///
/// The send cue is intentionally started synchronously from the Send tap, so
/// iOS Safari treats it as user-initiated audio. The receive cue is distinct
/// and can be primed by [unlock] when the composer is first touched.
class VetSupportChatSound {
  VetSupportChatSound._();

  static final AudioPlayer _sendPlayer = AudioPlayer();
  static final AudioPlayer _receivePlayer = AudioPlayer();
  static bool _unlocked = false;

  static final Uint8List _sendBytes = _wav(
    durationMs: 86,
    frequencies: const [1030.0, 1510.0],
    secondWeight: .29,
    amplitude: .30,
    tailPower: 3.1,
  );

  static final Uint8List _receiveBytes = _wav(
    durationMs: 148,
    frequencies: const [690.0, 1120.0],
    secondWeight: .46,
    amplitude: .24,
    tailPower: 2.35,
  );

  static final Uint8List _silentUnlock = _wav(
    durationMs: 18,
    frequencies: const [800.0, 1000.0],
    secondWeight: .3,
    amplitude: 0,
    tailPower: 2,
  );

  /// Prime browser audio during an explicit user gesture. This is silent.
  static Future<void> unlock() async {
    if (_unlocked) return;
    _unlocked = true;
    try {
      // Start both players while the tap gesture is still active. Awaiting is
      // deliberately avoided until both play calls have already been issued.
      final first = _sendPlayer.play(BytesSource(_silentUnlock), volume: .001);
      final second = _receivePlayer.play(BytesSource(_silentUnlock), volume: .001);
      await Future.wait([first, second]);
    } catch (_) {
      // A later explicit Send tap gets another chance to unlock playback.
      _unlocked = false;
    }
  }

  static Future<void> playSend() async {
    try {
      // No preliminary await/stop here: on Safari the actual play request must
      // happen inside the user's Send gesture.
      await _sendPlayer.play(BytesSource(_sendBytes), volume: .58);
      _unlocked = true;
    } catch (_) {
      try {
        await SystemSound.play(SystemSoundType.click);
      } catch (_) {}
    }
  }

  static Future<void> playReceive() async {
    try {
      await _receivePlayer.play(BytesSource(_receiveBytes), volume: .46);
    } catch (_) {
      try {
        await SystemSound.play(SystemSoundType.click);
      } catch (_) {}
    }
  }

  static Uint8List _wav({
    required int durationMs,
    required List<double> frequencies,
    required double secondWeight,
    required double amplitude,
    required double tailPower,
  }) {
    const sampleRate = 22050;
    const bytesPerSample = 2;
    final sampleCount = (sampleRate * durationMs / 1000).round();
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

    final first = frequencies.isEmpty ? 900.0 : frequencies.first;
    final second = frequencies.length < 2 ? first * 1.22 : frequencies[1];
    for (var i = 0; i < sampleCount; i++) {
      final t = i / sampleRate;
      final progress = i / sampleCount;
      final attack = math.min(1.0, i / (sampleRate * .0025));
      final decay = math.pow(1.0 - progress, tailPower).toDouble();
      // A tiny upward movement keeps the cue crisp without copying any
      // third-party messenger sound file.
      final drift = 1.0 + (.055 * progress);
      final wave =
          math.sin(2 * math.pi * first * drift * t) * (1 - secondWeight) +
              math.sin(2 * math.pi * second * drift * t) * secondWeight;
      final sample = (32767 * amplitude * attack * decay * wave)
          .round()
          .clamp(-32767, 32767)
          .toInt();
      data.setInt16(44 + i * 2, sample, Endian.little);
    }
    return data.buffer.asUint8List();
  }
}
