import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

/// Small original Vet AI chat cues generated in memory.
///
/// They intentionally avoid shipping/copying any third-party messenger sound.
/// The cues are short enough to feel immediate while a support conversation is
/// open, and fall back to the platform click if an audio backend is unavailable.
class VetSupportChatSound {
  VetSupportChatSound._();

  static final AudioPlayer _sendPlayer = AudioPlayer();
  static final AudioPlayer _receivePlayer = AudioPlayer();

  static final Uint8List _sendBytes = _wav(
    durationMs: 72,
    frequencies: const [1080.0, 1480.0],
    secondWeight: .34,
    amplitude: .22,
  );

  static final Uint8List _receiveBytes = _wav(
    durationMs: 118,
    frequencies: const [760.0, 1040.0],
    secondWeight: .42,
    amplitude: .20,
  );

  static Future<void> playSend() => _play(_sendPlayer, _sendBytes, .42);

  static Future<void> playReceive() =>
      _play(_receivePlayer, _receiveBytes, .36);

  static Future<void> _play(
    AudioPlayer player,
    Uint8List bytes,
    double volume,
  ) async {
    try {
      await player.stop();
      await player.play(BytesSource(bytes), volume: volume);
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
      final attack = math.min(1.0, i / (sampleRate * .003));
      final decay = math.pow(1.0 - progress, 2.4).toDouble();
      final wave =
          math.sin(2 * math.pi * first * t) * (1 - secondWeight) +
              math.sin(2 * math.pi * second * t) * secondWeight;
      final sample = (32767 * amplitude * attack * decay * wave)
          .round()
          .clamp(-32767, 32767)
          .toInt();
      data.setInt16(44 + i * 2, sample, Endian.little);
    }
    return data.buffer.asUint8List();
  }
}
