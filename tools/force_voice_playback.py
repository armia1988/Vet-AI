from pathlib import Path

path = Path('lib/analysis/vet_analysis_report.dart')
text = path.read_text(encoding='utf-8')

if "import 'dart:io';" not in text:
    text = text.replace("import 'dart:async';\n", "import 'dart:async';\nimport 'dart:io';\n", 1)
if "package:path_provider/path_provider.dart" not in text:
    text = text.replace(
        "import 'package:flutter_tts/flutter_tts.dart';\n",
        "import 'package:flutter_tts/flutter_tts.dart';\nimport 'package:path_provider/path_provider.dart';\n",
        1,
    )

old = """          await VetBackend.instance.logVoiceClientEvent(stage: 'audio_player_start', route: 'audioplayers', detail: 'audio_bytes=${natural.length}', appVersion: '0.6.21');
          await _audio.play(BytesSource(natural));
          await VetBackend.instance.logVoiceClientEvent(stage: 'audio_player_started', route: 'audioplayers', appVersion: '0.6.21');
          return;
"""
new = """          final isWav = natural.length >= 12 &&
              natural[0] == 0x52 && natural[1] == 0x49 &&
              natural[2] == 0x46 && natural[3] == 0x46;
          final tempDir = await getTemporaryDirectory();
          final voiceFile = File(
            '${tempDir.path}/vet_ai_voice_${DateTime.now().microsecondsSinceEpoch}.${isWav ? 'wav' : 'mp3'}',
          );
          await voiceFile.writeAsBytes(natural, flush: true);
          await VetBackend.instance.logVoiceClientEvent(
            stage: 'audio_player_start',
            route: 'device_file_source',
            detail: 'audio_bytes=${natural.length}; file=${voiceFile.path}',
            appVersion: '0.6.24',
          );
          await _audio.setPlayerMode(PlayerMode.mediaPlayer);
          await _audio.setReleaseMode(ReleaseMode.stop);
          await _audio.play(DeviceFileSource(voiceFile.path));
          await VetBackend.instance.logVoiceClientEvent(
            stage: 'audio_player_started',
            route: 'device_file_source',
            detail: 'audio_bytes=${natural.length}',
            appVersion: '0.6.24',
          );
          return;
"""

if 'BytesSource(natural)' in text:
    if old not in text:
        raise SystemExit('Old iOS BytesSource block exists but did not match the expected source')
    text = text.replace(old, new, 1)

path.write_text(text, encoding='utf-8')
check = path.read_text(encoding='utf-8')
if 'BytesSource(natural)' in check:
    raise SystemExit('STOP: old iOS BytesSource playback is still present')
if 'DeviceFileSource(voiceFile.path)' not in check:
    raise SystemExit('STOP: device-file iOS voice playback was not installed')
if "route: 'device_file_source'" not in check:
    raise SystemExit('STOP: device-file voice telemetry is missing')

print('Vet AI 0.6.24 iOS voice player LOCKED to DeviceFileSource before compilation')
