from pathlib import Path

REPORT = Path('lib/analysis/vet_analysis_report.dart')
APP = Path('lib/v5_app.dart')

# --- iOS natural cloud voice: persist provider bytes to a real local file first. ---
report = REPORT.read_text(encoding='utf-8')
if "import 'dart:io';" not in report:
    report = report.replace("import 'dart:async';\n", "import 'dart:async';\nimport 'dart:io';\n")
if "package:path_provider/path_provider.dart" not in report:
    report = report.replace(
        "import 'package:flutter_tts/flutter_tts.dart';\n",
        "import 'package:flutter_tts/flutter_tts.dart';\nimport 'package:path_provider/path_provider.dart';\n",
    )

old_play = """          await VetBackend.instance.logVoiceClientEvent(stage: 'audio_player_start', route: 'audioplayers', detail: 'audio_bytes=${natural.length}', appVersion: '0.6.21');
          await _audio.play(BytesSource(natural));
          await VetBackend.instance.logVoiceClientEvent(stage: 'audio_player_started', route: 'audioplayers', appVersion: '0.6.21');
          return;
"""
new_play = """          final isWav = natural.length >= 12 &&
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
            appVersion: '0.6.23',
          );
          await _audio.setPlayerMode(PlayerMode.mediaPlayer);
          await _audio.setReleaseMode(ReleaseMode.stop);
          await _audio.play(DeviceFileSource(voiceFile.path));
          await VetBackend.instance.logVoiceClientEvent(
            stage: 'audio_player_started',
            route: 'device_file_source',
            detail: 'audio_bytes=${natural.length}',
            appVersion: '0.6.23',
          );
          return;
"""
if old_play in report:
    report = report.replace(old_play, new_play, 1)
elif "DeviceFileSource(voiceFile.path)" not in report:
    raise SystemExit('0.6.23 voice patch: expected BytesSource playback block not found')

old_catch = """      } catch (_) {
        // Retry the natural voice once.
      }
"""
new_catch = """      } catch (e) {
        try {
          await VetBackend.instance.logVoiceClientEvent(
            stage: 'audio_player_error',
            route: 'device_file_source',
            detail: e.toString(),
            appVersion: '0.6.23',
          );
        } catch (_) {}
        // Retry the natural voice once.
      }
"""
if old_catch in report:
    report = report.replace(old_catch, new_catch, 1)
REPORT.write_text(report, encoding='utf-8')

# --- Real dog-breed thumbnails instead of one repeated dog emoji. ---
app = APP.read_text(encoding='utf-8')
old_avatar = "avatar: const Text('🐕', style: TextStyle(fontSize: 21)),"
if old_avatar in app:
    app = app.replace(old_avatar, "avatar: _DogBreedAvatar(code: breed.code),", 1)
elif "_DogBreedAvatar(code: breed.code)" not in app:
    raise SystemExit('0.6.23 breed patch: repeated dog emoji avatar not found')

helper_marker = "class _SpeciesSingleSelect extends StatelessWidget {"
if "class _DogBreedAvatar extends StatelessWidget" not in app:
    if helper_marker not in app:
        raise SystemExit('0.6.23 breed patch: insertion marker not found')
    helper = r'''const _dogBreedImageUrls = <String, String>{
  'german_shepherd': 'https://commons.wikimedia.org/wiki/Special:FilePath/Pastor%20aleman%20a.jpg',
  'belgian_malinois': 'https://commons.wikimedia.org/wiki/Special:FilePath/04%20-%20Belgian%20shepherd%20dog%20varieties%20-%20Groenendael%2CTervuren%2C%20Malinois%2C%20Laekenois.jpg',
  'rottweiler': 'https://commons.wikimedia.org/wiki/Special:FilePath/Rottweiler%20Moletai%20May%202014.2.jpg',
  'labrador': 'https://commons.wikimedia.org/wiki/Special:FilePath/Yellow%20Labrador%20Retriever%202.jpg',
  'golden_retriever': 'https://commons.wikimedia.org/wiki/Special:FilePath/Golden%20Retriever%20Dukedestiny01%20drvd.jpg',
  'doberman': 'https://commons.wikimedia.org/wiki/Special:FilePath/Dobermann%20Father-and-son.jpg',
  'cane_corso': 'https://commons.wikimedia.org/wiki/Special:FilePath/Anita%20Cane%20Corso%20Italiano%20allevato%20in%20Italia.jpg',
  'pitbull_amstaff': 'https://commons.wikimedia.org/wiki/Special:FilePath/American%20Pit%20Bull%20Terrier.jpg',
  'husky': 'https://commons.wikimedia.org/wiki/Special:FilePath/Siberian%20Husky%20-%20Mika.jpg',
  'border_collie': 'https://commons.wikimedia.org/wiki/Special:FilePath/Border%20Collie%20600.jpg',
  'boxer': 'https://commons.wikimedia.org/wiki/Special:FilePath/Boxer%20female%20brown.jpg',
  'great_dane': 'https://commons.wikimedia.org/wiki/Special:FilePath/8675eds%20win.jpg',
  'mastiff': 'https://commons.wikimedia.org/wiki/Special:FilePath/Mastif%20angielski%20pregowany%20nn.jpg',
  'beagle': 'https://commons.wikimedia.org/wiki/Special:FilePath/MiloSmet.JPG',
  'poodle': 'https://commons.wikimedia.org/wiki/Special:FilePath/AKC%20Helena%20Fall%20Dog%20Show%202011%20%286187041897%29.jpg',
  'cocker_spaniel': 'https://commons.wikimedia.org/wiki/Special:FilePath/%22Bill%22%20-%20Cocker%20spaniel%20anglais%201.jpg',
  'shih_tzu': 'https://commons.wikimedia.org/wiki/Special:FilePath/Shih%20Tzu%20portrait%20show%20dog.jpg',
  'pomeranian': 'https://commons.wikimedia.org/wiki/Special:FilePath/Pomeranian%20dog.jpg',
  'chihuahua': 'https://commons.wikimedia.org/wiki/Special:FilePath/Chihuahua%20dog.jpg',
};

class _DogBreedAvatar extends StatelessWidget {
  const _DogBreedAvatar({required this.code});
  final String code;

  @override
  Widget build(BuildContext context) {
    final url = _dogBreedImageUrls[code];
    if (url == null) {
      return ClipOval(
        child: Image.asset(
          'assets/icons/dog_section.webp',
          width: 34,
          height: 34,
          fit: BoxFit.cover,
        ),
      );
    }
    return ClipOval(
      child: Image.network(
        url,
        width: 34,
        height: 34,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => Image.asset(
          'assets/icons/dog_section.webp',
          width: 34,
          height: 34,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

'''
    app = app.replace(helper_marker, helper + helper_marker, 1)
APP.write_text(app, encoding='utf-8')

# Hard assertions: fail the build instead of silently shipping the old behavior.
report_check = REPORT.read_text(encoding='utf-8')
app_check = APP.read_text(encoding='utf-8')
required_report = [
    "DeviceFileSource(voiceFile.path)",
    "getTemporaryDirectory()",
    "stage: 'audio_player_error'",
    "appVersion: '0.6.23'",
]
for marker in required_report:
    if marker not in report_check:
        raise SystemExit(f'0.6.23 voice verification missing: {marker}')
if "BytesSource(natural)" in report_check:
    raise SystemExit('0.6.23 voice verification: old BytesSource playback is still present')
if "_DogBreedAvatar(code: breed.code)" not in app_check:
    raise SystemExit('0.6.23 breed verification: real breed avatar wiring is missing')
if "avatar: const Text('🐕'" in app_check:
    raise SystemExit('0.6.23 breed verification: repeated dog emoji still present')

print('Vet AI 0.6.23 iOS file voice playback + breed thumbnails applied')
