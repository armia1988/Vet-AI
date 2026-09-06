from pathlib import Path
import shutil
import zipfile

ROOT = Path('.')
BUNDLE = ROOT / 'tools/v29_transparent_art_bundle.zip'
ASSETS = ROOT / 'assets/icons'
APP = ROOT / 'lib/v5_app.dart'
PUBSPEC = ROOT / 'pubspec.yaml'
CODEMAGIC = ROOT / 'codemagic.yaml'
VERIFY = ROOT / 'tools/verify_v29_transparent_artwork.py'

if not BUNDLE.exists():
    raise SystemExit('Vet AI 0.6.29 artwork bundle is missing')

with zipfile.ZipFile(BUNDLE) as zf:
    zf.extractall(ROOT / 'tools/.v29_art')

temp = ROOT / 'tools/.v29_art'
files = {
    temp / 'animal_sprite_transparent_q.png': ASSETS / 'animal_sprite_transparent.png',
    temp / 'livestock_group_q.png': ASSETS / 'livestock_group_transparent.png',
    temp / 'birds_group_q.png': ASSETS / 'birds_group_transparent.png',
    temp / 'dogs_group_q.png': ASSETS / 'dogs_group_transparent.png',
}
for src, dst in files.items():
    if not src.exists():
        raise SystemExit(f'Missing transparent artwork file: {src}')
    shutil.copyfile(src, dst)
shutil.rmtree(temp)

app = APP.read_text(encoding='utf-8')
app = app.replace(
    "'assets/icons/animal_sprite_v26.webp'",
    "'assets/icons/animal_sprite_transparent.png'",
)
app = app.replace(
    "'assets/icons/livestock_group_transparent.webp'",
    "'assets/icons/livestock_group_transparent.png'",
)
app = app.replace(
    "'assets/icons/birds_group_transparent.webp'",
    "'assets/icons/birds_group_transparent.png'",
)
app = app.replace(
    "'assets/icons/dogs_group_transparent.webp'",
    "'assets/icons/dogs_group_transparent.png'",
)

old_error = "errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),"
new_error = """errorBuilder: (context, error, stackTrace) => _AnimalSprite(
        index: asset.contains('dogs') ? 1 : asset.contains('birds') ? 2 : 0,
        size: size,
        radius: 0,
      ),"""
if old_error in app:
    app = app.replace(old_error, new_error, 1)

required = [
    'animal_sprite_transparent.png',
    'livestock_group_transparent.png',
    'birds_group_transparent.png',
    'dogs_group_transparent.png',
]
for marker in required:
    if marker not in app:
        raise SystemExit(f'Artwork mapping missing from v5_app.dart: {marker}')
APP.write_text(app, encoding='utf-8')

pubspec = PUBSPEC.read_text(encoding='utf-8')
if 'version: 0.6.28+40' in pubspec:
    pubspec = pubspec.replace('version: 0.6.28+40', 'version: 0.6.29+41', 1)
elif 'version: 0.6.29+41' not in pubspec:
    raise SystemExit('Unexpected Vet AI version while applying 0.6.29 artwork fix')
PUBSPEC.write_text(pubspec, encoding='utf-8')

verify_text = r'''from pathlib import Path
from PIL import Image

FILES = [
    'assets/icons/animal_sprite_transparent.png',
    'assets/icons/livestock_group_transparent.png',
    'assets/icons/birds_group_transparent.png',
    'assets/icons/dogs_group_transparent.png',
]
for path in FILES:
    p = Path(path)
    if not p.exists() or p.stat().st_size < 20000:
        raise SystemExit(f'Transparent Vet AI artwork missing or too small: {path}')
    image = Image.open(p).convert('RGBA')
    amin, amax = image.getchannel('A').getextrema()
    if amin != 0 or amax != 255:
        raise SystemExit(f'Artwork is not truly transparent: {path}; alpha={amin, amax}')

app = Path('lib/v5_app.dart').read_text(encoding='utf-8')
for marker in (
    'animal_sprite_transparent.png',
    'livestock_group_transparent.png',
    'birds_group_transparent.png',
    'dogs_group_transparent.png',
):
    if marker not in app:
        raise SystemExit(f'Vet AI transparent artwork mapping missing: {marker}')

if "errorBuilder: (context, error, stackTrace) => const SizedBox.shrink()," in app:
    raise SystemExit('Blank-image fallback is still active in Vet AI group artwork')

pubspec = Path('pubspec.yaml').read_text(encoding='utf-8')
if 'version: 0.6.29+41' not in pubspec:
    raise SystemExit('Vet AI 0.6.29 version marker missing')
print('Vet AI 0.6.29 real transparent artwork verified')
'''
VERIFY.write_text(verify_text, encoding='utf-8')

codemagic = CODEMAGIC.read_text(encoding='utf-8')
needle = '          python3 tools/patch_v41_instant_voice_prewarm.py\n'
verify_line = '          python3 tools/verify_v29_transparent_artwork.py\n'
if verify_line not in codemagic:
    if needle not in codemagic:
        raise SystemExit('Codemagic hotfix marker missing')
    codemagic = codemagic.replace(needle, needle + verify_line, 1)
CODEMAGIC.write_text(codemagic, encoding='utf-8')

print('Vet AI 0.6.29 real transparent approved artwork patch applied')
