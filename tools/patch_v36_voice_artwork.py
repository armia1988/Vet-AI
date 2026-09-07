from pathlib import Path
import base64
import hashlib
import re

from PIL import Image

APP = Path('lib/v5_app.dart')
TAXONOMY = Path('lib/models/animal_taxonomy.dart')
PAYLOAD = Path('tools/approved_color_sprite_v34.b64')
SPRITE = Path('assets/icons/animal_sprite_approved_v34.webp')
LIVESTOCK_GROUP = Path('assets/icons/livestock_group_approved_v34.webp')
DOGS_GROUP = Path('assets/icons/dogs_group_approved_v34.webp')
BIRDS_GROUP = Path('assets/icons/birds_group_approved_v34.webp')
EXPECTED_SHA256 = '82adcb74c87122d424323713abf1ceb98b89c826b7d5d27b1a090a9bf7bef26a'

# Vet AI 0.6.29 — exact NEW colourful artwork approved by the user.
# This payload was made directly from the user's approved 5x5 colour sheet.
# A brand-new asset filename is used so iOS/Flutter cannot reuse the old cyan
# image from the asset cache.
if not PAYLOAD.exists():
    raise SystemExit(f'Approved colour payload missing: {PAYLOAD}')

try:
    sprite_bytes = base64.b64decode(PAYLOAD.read_text(encoding='utf-8').strip(), validate=True)
except Exception as exc:
    raise SystemExit(f'Approved colour payload is invalid: {exc}')

actual_sha = hashlib.sha256(sprite_bytes).hexdigest()
if actual_sha != EXPECTED_SHA256:
    raise SystemExit(
        f'Approved colour sprite checksum mismatch: expected {EXPECTED_SHA256}, got {actual_sha}'
    )

SPRITE.parent.mkdir(parents=True, exist_ok=True)
SPRITE.write_bytes(sprite_bytes)

with Image.open(SPRITE) as source_file:
    source = source_file.convert('RGB')
    width, height = source.size
    if (width, height) != (300, 300):
        raise SystemExit(f'Approved colour sprite must be 300x300, got {width}x{height}')

    # Strong colour guard: the NEW reference contains brown/yellow/red/black
    # animals, while the rejected artwork is almost entirely turquoise.
    sample = source.resize((100, 100), Image.Resampling.BILINEAR)
    warm = dark = yellow = 0
    for r, g, b in sample.getdata():
        if r > g * 1.08 and r > b * 1.10 and r > 95:
            warm += 1
        if max(r, g, b) < 95:
            dark += 1
        if r > 160 and g > 110 and b < 110:
            yellow += 1
    if warm < 70 or dark < 25 or yellow < 10:
        raise SystemExit(
            f'Wrong animal artwork detected (warm={warm}, dark={dark}, yellow={yellow})'
        )

    # First row in the approved sheet:
    # 0 livestock group, 1 dogs group, 2 poultry group.
    cell = width // 5
    for index, destination in {
        0: LIVESTOCK_GROUP,
        1: DOGS_GROUP,
        2: BIRDS_GROUP,
    }.items():
        col = index % 5
        row = index // 5
        crop = source.crop((col * cell, row * cell, (col + 1) * cell, (row + 1) * cell))
        crop = crop.resize((420, 420), Image.Resampling.LANCZOS)
        crop.save(destination, format='WEBP', quality=90, method=6)

app = APP.read_text(encoding='utf-8')

# Replace every historical animal-art path, including the previous v31 attempt,
# with the new v34 filenames. This is intentionally broad so the build cannot
# silently fall back to v26/v29/v30/v31 artwork anywhere in the app.
for old in (
    'assets/icons/animal_sprite_v26.webp',
    'assets/icons/animal_sprite_v29.webp',
    'assets/icons/animal_sprite_color_v30.webp',
    'assets/icons/animal_sprite_approved_v31.webp',
):
    app = app.replace(old, str(SPRITE))

for old in (
    'assets/icons/livestock_group_v29.webp',
    'assets/icons/livestock_group_transparent.webp',
    'assets/icons/livestock_group_color_v30.webp',
    'assets/icons/livestock_group_approved_v31.webp',
):
    app = app.replace(old, str(LIVESTOCK_GROUP))

for old in (
    'assets/icons/dogs_group_v29.webp',
    'assets/icons/dogs_group_transparent.webp',
    'assets/icons/dogs_group_color_v30.webp',
    'assets/icons/dogs_group_approved_v31.webp',
):
    app = app.replace(old, str(DOGS_GROUP))

for old in (
    'assets/icons/birds_group_v29.webp',
    'assets/icons/birds_group_transparent.webp',
    'assets/icons/birds_group_color_v30.webp',
    'assets/icons/birds_group_approved_v31.webp',
):
    app = app.replace(old, str(BIRDS_GROUP))

APP.write_text(app, encoding='utf-8')

taxonomy = TAXONOMY.read_text(encoding='utf-8')
approved_dogs = r"""const vetDogBreeds = <VetDogBreed>[
  VetDogBreed(code: 'pitbull_amstaff', en: 'Pit Bull / AmStaff', ar: 'بيتبول / أمستاف', nl: 'Pitbull / AmStaff', spriteIndex: 20),
  VetDogBreed(code: 'rottweiler', en: 'Rottweiler', ar: 'روت وايلر', nl: 'Rottweiler', spriteIndex: 15),
  VetDogBreed(code: 'labrador', en: 'Labrador Retriever', ar: 'لابرادور', nl: 'Labrador retriever', spriteIndex: 16),
  VetDogBreed(code: 'golden_retriever', en: 'Golden Retriever', ar: 'جولدن ريتريفر', nl: 'Golden retriever', spriteIndex: 17),
  VetDogBreed(code: 'german_shepherd', en: 'German Shepherd', ar: 'جيرمن شيبرد', nl: 'Duitse herder', spriteIndex: 13),
  VetDogBreed(code: 'husky', en: 'Siberian Husky', ar: 'هاسكي', nl: 'Siberische husky', spriteIndex: 21),
  VetDogBreed(code: 'doberman', en: 'Dobermann', ar: 'دوبرمان', nl: 'Dobermann', spriteIndex: 18),
  VetDogBreed(code: 'belgian_malinois', en: 'Belgian Malinois', ar: 'مالينوي بلجيكي', nl: 'Mechelse herder', spriteIndex: 14),
  VetDogBreed(code: 'chihuahua', en: 'Chihuahua', ar: 'تشيواوا', nl: 'Chihuahua', spriteIndex: 22),
  VetDogBreed(code: 'mastiff', en: 'Mastiff', ar: 'ماستيف', nl: 'Mastiff', spriteIndex: 19),
];"""

pattern = re.compile(r"const vetDogBreeds = <VetDogBreed>\[.*?\n\];", re.S)
taxonomy, count = pattern.subn(approved_dogs, taxonomy, count=1)
if count != 1:
    raise SystemExit(f'Could not install approved dog list; replacement count={count}')
TAXONOMY.write_text(taxonomy, encoding='utf-8')

# Final guards: a successful Codemagic build is not allowed to contain any
# reference to the rejected cyan artwork.
app_check = APP.read_text(encoding='utf-8')
taxonomy_check = TAXONOMY.read_text(encoding='utf-8')
required = (
    str(SPRITE),
    str(LIVESTOCK_GROUP),
    str(DOGS_GROUP),
    str(BIRDS_GROUP),
)
for marker in required:
    if marker not in app_check:
        raise SystemExit(f'New approved colour asset is not wired into app: {marker}')

for forbidden in (
    'animal_sprite_v26.webp',
    'animal_sprite_v29.webp',
    'animal_sprite_color_v30.webp',
    'animal_sprite_approved_v31.webp',
    'livestock_group_v29.webp',
    'dogs_group_v29.webp',
    'birds_group_v29.webp',
    'group_color_v30.webp',
    'group_approved_v31.webp',
):
    if forbidden in app_check:
        raise SystemExit(f'Rejected old animal artwork is still referenced: {forbidden}')

for breed in (
    'pitbull_amstaff', 'rottweiler', 'labrador', 'golden_retriever',
    'german_shepherd', 'husky', 'doberman', 'belgian_malinois',
    'chihuahua', 'mastiff',
):
    if f"code: '{breed}'" not in taxonomy_check:
        raise SystemExit(f'Approved dog breed missing: {breed}')

for forbidden_breed in ('cane_corso', 'mixed_other'):
    if f"code: '{forbidden_breed}'" in taxonomy_check:
        raise SystemExit(f'Old dog breed still selectable: {forbidden_breed}')

print('Vet AI artwork lock V34 OK — NEW colourful user-approved animals only')
