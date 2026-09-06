from pathlib import Path

from PIL import Image

REPORT = Path('lib/analysis/vet_analysis_report.dart')
APP = Path('lib/v5_app.dart')
WORKFLOW = Path('lib/services/vet_case_workflow.dart')

APP_VERSION = '0.6.24'


def crop_approved_artwork(source: str, destination: str) -> None:
    """Trim near-white/transparent margins without changing the approved artwork itself."""
    src = Path(source)
    dst = Path(destination)
    image = Image.open(src).convert('RGBA')
    width, height = image.size
    pixels = image.load()
    mask = Image.new('L', image.size, 0)
    mask_pixels = mask.load()

    for y in range(height):
        for x in range(width):
            r, g, b, a = pixels[x, y]
            # Keep anything visible that is not almost pure white.
            visible = a > 12 and (min(r, g, b) < 244 or max(r, g, b) - min(r, g, b) > 7)
            if visible:
                mask_pixels[x, y] = 255

    bbox = mask.getbbox()
    if bbox is None:
        cropped = image
    else:
        left, top, right, bottom = bbox
        pad_x = max(8, int((right - left) * 0.06))
        pad_y = max(8, int((bottom - top) * 0.06))
        left = max(0, left - pad_x)
        top = max(0, top - pad_y)
        right = min(width, right + pad_x)
        bottom = min(height, bottom + pad_y)
        cropped = image.crop((left, top, right, bottom))

    cropped.save(dst, format='PNG', optimize=True)


approved_artwork = {
    'livestock': ('assets/icons/livestock_final.png', 'assets/icons/livestock_display.png'),
    'poultry': ('assets/icons/poultry_final.png', 'assets/icons/poultry_display.png'),
    'dogs': ('assets/icons/dog_final.png', 'assets/icons/dog_display.png'),
}
for _, (source, destination) in approved_artwork.items():
    crop_approved_artwork(source, destination)

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
if old_play in report:
    report = report.replace(old_play, new_play, 1)
elif "DeviceFileSource(voiceFile.path)" not in report:
    raise SystemExit('0.6.24 voice patch: expected BytesSource playback block not found')

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
            appVersion: '0.6.24',
          );
        } catch (_) {}
        // Retry the natural voice once.
      }
"""
if old_catch in report:
    report = report.replace(old_catch, new_catch, 1)

# The previous report voice only spoke the FIRST immediate action. 0.6.24 must
# read the complete "What to do now" section when no server voice_summary exists.
old_actions = """      final actions = _strings(_result['immediate_actions']);
      if (actions.isNotEmpty) {
        parts.add(
          widget.translate(
            'What to do now: ${actions.first}',
            'تعمل إيه دلوقتي: ${actions.first}',
            'Wat nu te doen: ${actions.first}',
          ),
        );
      }
"""
new_actions = """      final actions = _strings(_result['immediate_actions']);
      if (actions.isNotEmpty) {
        final allActions = actions.join('. ');
        parts.add(
          widget.translate(
            'What to do now. $allActions',
            'تعمل إيه دلوقتي. $allActions',
            'Wat je nu moet doen. $allActions',
          ),
        );
      }
"""
if old_actions in report:
    report = report.replace(old_actions, new_actions, 1)
elif "final allActions = actions.join('. ');" not in report:
    raise SystemExit('0.6.24 voice patch: complete immediate-actions block not found')

report = report.replace("appVersion: '0.6.23'", "appVersion: '0.6.24'")
REPORT.write_text(report, encoding='utf-8')

# --- Allow one complete spoken report instead of clipping it at 1200 chars. ---
workflow = WORKFLOW.read_text(encoding='utf-8')
old_limit = "'text': clean.length > 1200 ? clean.substring(0, 1200) : clean,"
new_limit = "'text': clean.length > 3600 ? clean.substring(0, 3600) : clean,"
if old_limit in workflow:
    workflow = workflow.replace(old_limit, new_limit, 1)
elif new_limit not in workflow:
    raise SystemExit('0.6.24 voice patch: 1200-character client limit not found')
workflow = workflow.replace("appVersion: '0.6.21'", "appVersion: '0.6.24'")
WORKFLOW.write_text(workflow, encoding='utf-8')

# --- Use cropped DISPLAY copies of the exact approved source artwork. ---
app = APP.read_text(encoding='utf-8')
section_assets = {
    'assets/icons/livestock_section.webp': 'assets/icons/livestock_display.png',
    'assets/icons/poultry_section.webp': 'assets/icons/poultry_display.png',
    'assets/icons/dog_section.webp': 'assets/icons/dog_display.png',
    'assets/icons/livestock_final.png': 'assets/icons/livestock_display.png',
    'assets/icons/poultry_final.png': 'assets/icons/poultry_display.png',
    'assets/icons/dog_final.png': 'assets/icons/dog_display.png',
}
for old_asset, display_asset in section_assets.items():
    app = app.replace(old_asset, display_asset)

# Make the group artwork physically larger in the places the user marked.
app = app.replace(
    """              child: Transform.scale(
                scale: 1.25,
                child: Image.asset(
                  asset,
                  fit: BoxFit.contain,""",
    """              child: Transform.scale(
                scale: 1.55,
                child: Image.asset(
                  asset,
                  fit: BoxFit.contain,""",
    1,
)
app = app.replace(
    """                child: Transform.scale(
                  scale: 1.0,
                  child: Image.asset(
                    asset,
                    width: 300,
                    height: 168,""",
    """                child: Transform.scale(
                  scale: 1.18,
                  child: Image.asset(
                    asset,
                    width: 300,
                    height: 168,""",
    1,
)
app = app.replace("width: 56,\n                      height: 42,", "width: 70,\n                      height: 52,", 1)

# --- Real dog-breed thumbnails instead of one repeated dog emoji. ---
old_avatar = "avatar: const Text('🐕', style: TextStyle(fontSize: 21)),"
if old_avatar in app:
    app = app.replace(old_avatar, "avatar: _DogBreedAvatar(code: breed.code),", 1)
elif "_DogBreedAvatar(code: breed.code)" not in app:
    raise SystemExit('0.6.24 breed patch: repeated dog emoji avatar not found')

helper_marker = "class _SpeciesSingleSelect extends StatelessWidget {"
if "class _DogBreedAvatar extends StatelessWidget" not in app:
    if helper_marker not in app:
        raise SystemExit('0.6.24 breed patch: insertion marker not found')
    dog_helper = r'''const _dogBreedImageUrls = <String, String>{
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
          'assets/icons/dog_display.png',
          width: 36,
          height: 36,
          fit: BoxFit.cover,
        ),
      );
    }
    return ClipOval(
      child: Image.network(
        url,
        width: 36,
        height: 36,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => Image.asset(
          'assets/icons/dog_display.png',
          width: 36,
          height: 36,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

'''
    app = app.replace(helper_marker, dog_helper + helper_marker, 1)

# --- Large, clear species artwork in livestock/bird selectors. ---
if "class _SpeciesChipAvatar extends StatelessWidget" not in app:
    if helper_marker not in app:
        raise SystemExit('0.6.24 species artwork patch: insertion marker not found')
    species_helper = r'''class _SpeciesChipAvatar extends StatelessWidget {
  const _SpeciesChipAvatar({required this.code, required this.emoji, this.size = 40});
  final String code;
  final String emoji;
  final double size;

  @override
  Widget build(BuildContext context) {
    String? svg;
    if (code == 'cattle') svg = 'assets/icons/cow.svg';
    if (code == 'buffalo') svg = 'assets/icons/buffalo.svg';
    if (code == 'chicken') svg = 'assets/icons/chicken.svg';
    if (code == 'chick') svg = 'assets/icons/chick.svg';

    if (svg != null) {
      return SizedBox(
        width: size,
        height: size,
        child: SvgPicture.asset(svg, fit: BoxFit.contain),
      );
    }
    if (code == 'dog') {
      return ClipOval(
        child: Image.asset(
          'assets/icons/dog_display.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      );
    }
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Text(emoji, style: TextStyle(fontSize: size * .82, height: 1)),
      ),
    );
  }
}

'''
    app = app.replace(helper_marker, species_helper + helper_marker, 1)

app = app.replace(
    "avatar: Text(item.emoji, style: const TextStyle(fontSize: 23)),",
    "avatar: _SpeciesChipAvatar(code: item.code, emoji: item.emoji, size: 40),",
)
app = app.replace(
    """return ChoiceChip(
              avatar: _SpeciesChipAvatar(code: item.code, emoji: item.emoji, size: 40),
              label: Text(label, style: TextStyle(fontWeight: active ? FontWeight.w900 : FontWeight.w700)),""",
    """return ChoiceChip(
              avatar: _SpeciesChipAvatar(code: item.code, emoji: item.emoji, size: 42),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              labelPadding: const EdgeInsetsDirectional.only(start: 7, end: 11),
              label: Text(label, style: TextStyle(fontSize: 16.5, fontWeight: active ? FontWeight.w900 : FontWeight.w700)),""",
    1,
)

APP.write_text(app, encoding='utf-8')

# Hard assertions: fail the build instead of silently shipping old behavior.
report_check = REPORT.read_text(encoding='utf-8')
workflow_check = WORKFLOW.read_text(encoding='utf-8')
app_check = APP.read_text(encoding='utf-8')
required_report = [
    "DeviceFileSource(voiceFile.path)",
    "getTemporaryDirectory()",
    "stage: 'audio_player_error'",
    "appVersion: '0.6.24'",
    "final allActions = actions.join('. ');",
]
for marker in required_report:
    if marker not in report_check:
        raise SystemExit(f'0.6.24 voice verification missing: {marker}')
if "BytesSource(natural)" in report_check:
    raise SystemExit('0.6.24 voice verification: old BytesSource playback is still present')
if "clean.length > 3600" not in workflow_check:
    raise SystemExit('0.6.24 voice verification: client still clips long spoken reports')
if "_DogBreedAvatar(code: breed.code)" not in app_check:
    raise SystemExit('0.6.24 breed verification: real breed avatar wiring is missing')
if "avatar: const Text('🐕'" in app_check:
    raise SystemExit('0.6.24 breed verification: repeated dog emoji still present')
if "_SpeciesChipAvatar(code: item.code" not in app_check:
    raise SystemExit('0.6.24 species verification: large species artwork is not wired')
for display in ('livestock_display.png', 'poultry_display.png', 'dog_display.png'):
    path = Path('assets/icons') / display
    data = path.read_bytes()
    if not data.startswith(b'\x89PNG\r\n\x1a\n'):
        raise SystemExit(f'0.6.24 display artwork is not a valid PNG: {path}')
    if str(path) not in app_check:
        raise SystemExit(f'0.6.24 app is not wired to visible approved artwork: {path}')

print('Vet AI 0.6.24 hotfix applied: full voice actions, visible approved animal artwork, larger species icons, real dog breed photos')
