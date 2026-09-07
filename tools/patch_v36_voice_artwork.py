from pathlib import Path
import base64
import hashlib
import re

from PIL import Image

APP = Path('lib/v5_app.dart')
TAXONOMY = Path('lib/models/animal_taxonomy.dart')
EMBEDDED_DIR = Path('tools/embedded_animals_v32')
SPRITE = Path('assets/icons/animal_sprite_color_v30.webp')
LIVESTOCK_GROUP = Path('assets/icons/livestock_group_color_v30.webp')
DOGS_GROUP = Path('assets/icons/dogs_group_color_v30.webp')
BIRDS_GROUP = Path('assets/icons/birds_group_color_v30.webp')
EXPECTED_SHA256 = '4d08d1eadcf6c77d065db483a2fa9a98a923c2ff6620b9a40955f9f91d25530b'

# -----------------------------------------------------------------------------
# Vet AI 0.6.29 — rebuild the EXACT approved full-colour animal sprite first.
# The previous v30 binary placeholders could decode but rendered as blank images
# in Flutter. The approved sprite is therefore embedded as verified base64 text
# and reconstructed on every Codemagic build before Flutter bundles assets.
# -----------------------------------------------------------------------------
chunks = sorted(EMBEDDED_DIR.glob('sprite.b64.*'))
if not chunks:
    raise SystemExit('Approved full-colour sprite payload chunks are missing')

encoded = ''.join(path.read_text(encoding='utf-8').strip() for path in chunks)
try:
    sprite_bytes = base64.b64decode(encoded, validate=True)
except Exception as exc:
    raise SystemExit(f'Approved sprite base64 could not be decoded: {exc}')

actual_sha = hashlib.sha256(sprite_bytes).hexdigest()
if actual_sha != EXPECTED_SHA256:
    raise SystemExit(
        'Approved sprite checksum mismatch: '
        f'expected {EXPECTED_SHA256}, got {actual_sha}'
    )

SPRITE.parent.mkdir(parents=True, exist_ok=True)
SPRITE.write_bytes(sprite_bytes)

with Image.open(SPRITE) as source_file:
    source = source_file.convert('RGBA')
    width, height = source.size
    if width != 400 or height != 400 or width % 5 != 0 or height % 5 != 0:
        raise SystemExit(f'Approved sprite must be the verified 400x400 5x5 grid, got {width}x{height}')

    alpha = source.getchannel('A')
    if alpha.getbbox() is None:
        raise SystemExit('Approved sprite has no visible pixels')

    cell_w = width // 5
    cell_h = height // 5
    group_outputs = {
        0: LIVESTOCK_GROUP,
        1: DOGS_GROUP,
        2: BIRDS_GROUP,
    }
    for index, destination in group_outputs.items():
        col = index % 5
        row = index // 5
        crop = source.crop((
            col * cell_w,
            row * cell_h,
            (col + 1) * cell_w,
            (row + 1) * cell_h,
        ))
        if crop.getchannel('A').getbbox() is None:
            raise SystemExit(f'Approved group crop {index} is blank')
        # Upscale the group tile before bundling so it stays crisp in the large
        # farm/profile cards while preserving the exact approved illustration.
        crop = crop.resize((320, 320), Image.Resampling.LANCZOS)
        crop.save(destination, format='WEBP', quality=90, method=6, exact=True)

# -----------------------------------------------------------------------------
# Wire every animal UI path to the verified colour assets. No old cyan sprite,
# transparent placeholder, emoji/network fallback, or v26/v29 file is allowed.
# -----------------------------------------------------------------------------
app = APP.read_text(encoding='utf-8')
asset_replacements = {
    'assets/icons/animal_sprite_v29.webp': 'assets/icons/animal_sprite_color_v30.webp',
    'assets/icons/animal_sprite_v26.webp': 'assets/icons/animal_sprite_color_v30.webp',
    'assets/icons/livestock_group_v29.webp': 'assets/icons/livestock_group_color_v30.webp',
    'assets/icons/birds_group_v29.webp': 'assets/icons/birds_group_color_v30.webp',
    'assets/icons/dogs_group_v29.webp': 'assets/icons/dogs_group_color_v30.webp',
    'assets/icons/livestock_group_transparent.webp': 'assets/icons/livestock_group_color_v30.webp',
    'assets/icons/birds_group_transparent.webp': 'assets/icons/birds_group_color_v30.webp',
    'assets/icons/dogs_group_transparent.webp': 'assets/icons/dogs_group_color_v30.webp',
}
for old, new in asset_replacements.items():
    app = app.replace(old, new)
APP.write_text(app, encoding='utf-8')

# -----------------------------------------------------------------------------
# Install exactly the 10 approved dog breeds. The sprite indices correspond to
# the approved full-colour sheet; Cane Corso and Mixed / Other are removed.
# -----------------------------------------------------------------------------
taxonomy = TAXONOMY.read_text(encoding='utf-8')
approved_dogs = r"""const vetDogBreeds = <VetDogBreed>[
  VetDogBreed(
    code: 'pitbull_amstaff',
    en: 'Pit Bull / AmStaff',
    ar: 'بيتبول / أمستاف',
    nl: 'Pitbull / AmStaff',
    spriteIndex: 20,
  ),
  VetDogBreed(
    code: 'rottweiler',
    en: 'Rottweiler',
    ar: 'روت وايلر',
    nl: 'Rottweiler',
    spriteIndex: 15,
  ),
  VetDogBreed(
    code: 'labrador',
    en: 'Labrador Retriever',
    ar: 'لابرادور',
    nl: 'Labrador retriever',
    spriteIndex: 16,
  ),
  VetDogBreed(
    code: 'golden_retriever',
    en: 'Golden Retriever',
    ar: 'جولدن ريتريفر',
    nl: 'Golden retriever',
    spriteIndex: 17,
  ),
  VetDogBreed(
    code: 'german_shepherd',
    en: 'German Shepherd',
    ar: 'جيرمن شيبرد',
    nl: 'Duitse herder',
    spriteIndex: 13,
  ),
  VetDogBreed(
    code: 'husky',
    en: 'Siberian Husky',
    ar: 'هاسكي',
    nl: 'Siberische husky',
    spriteIndex: 21,
  ),
  VetDogBreed(
    code: 'doberman',
    en: 'Dobermann',
    ar: 'دوبرمان',
    nl: 'Dobermann',
    spriteIndex: 18,
  ),
  VetDogBreed(
    code: 'belgian_malinois',
    en: 'Belgian Malinois',
    ar: 'مالينوي بلجيكي',
    nl: 'Mechelse herder',
    spriteIndex: 14,
  ),
  VetDogBreed(
    code: 'chihuahua',
    en: 'Chihuahua',
    ar: 'تشيواوا',
    nl: 'Chihuahua',
    spriteIndex: 22,
  ),
  VetDogBreed(
    code: 'mastiff',
    en: 'Mastiff',
    ar: 'ماستيف',
    nl: 'Mastiff',
    spriteIndex: 19,
  ),
];"""

pattern = re.compile(r"const vetDogBreeds = <VetDogBreed>\[.*?\n\];", re.S)
taxonomy, count = pattern.subn(approved_dogs, taxonomy, count=1)
if count != 1:
    raise SystemExit(f'Could not install approved dog breed list; replacement count={count}')
TAXONOMY.write_text(taxonomy, encoding='utf-8')

# -----------------------------------------------------------------------------
# Hard build guards. Fail the build rather than ever shipping blank/old icons.
# -----------------------------------------------------------------------------
app_check = APP.read_text(encoding='utf-8')
taxonomy_check = TAXONOMY.read_text(encoding='utf-8')

required_app = (
    'assets/icons/animal_sprite_color_v30.webp',
    'assets/icons/livestock_group_color_v30.webp',
    'assets/icons/birds_group_color_v30.webp',
    'assets/icons/dogs_group_color_v30.webp',
)
for marker in required_app:
    if marker not in app_check:
        raise SystemExit(f'Full-colour animal artwork is not wired into app: {marker}')

for forbidden in (
    'assets/icons/animal_sprite_v26.webp',
    'assets/icons/animal_sprite_v29.webp',
    'assets/icons/livestock_group_v29.webp',
    'assets/icons/birds_group_v29.webp',
    'assets/icons/dogs_group_v29.webp',
):
    if forbidden in app_check:
        raise SystemExit(f'Old animal artwork path is still active: {forbidden}')

required_breeds = (
    "code: 'pitbull_amstaff'",
    "code: 'rottweiler'",
    "code: 'labrador'",
    "code: 'golden_retriever'",
    "code: 'german_shepherd'",
    "code: 'husky'",
    "code: 'doberman'",
    "code: 'belgian_malinois'",
    "code: 'chihuahua'",
    "code: 'mastiff'",
)
for marker in required_breeds:
    if marker not in taxonomy_check:
        raise SystemExit(f'Approved dog breed is missing: {marker}')
for forbidden in ("code: 'cane_corso'", "code: 'mixed_other'"):
    if forbidden in taxonomy_check:
        raise SystemExit(f'Old dog breed is still selectable: {forbidden}')

# Verify the actual files the Flutter bundle will consume, not only their paths.
if hashlib.sha256(SPRITE.read_bytes()).hexdigest() != EXPECTED_SHA256:
    raise SystemExit('Bundled full-colour sprite changed after reconstruction')
for group_asset in (LIVESTOCK_GROUP, DOGS_GROUP, BIRDS_GROUP):
    with Image.open(group_asset) as group_image:
        rgba = group_image.convert('RGBA')
        if rgba.width < 300 or rgba.height < 300 or rgba.getchannel('A').getbbox() is None:
            raise SystemExit(f'Bundled group image is invalid or blank: {group_asset}')

print(
    'Vet AI 0.6.29 verified FULL-COLOUR artwork rebuilt successfully: '
    'group cards + livestock/bird species + 10 approved dog breeds'
)
