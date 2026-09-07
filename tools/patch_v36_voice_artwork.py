from pathlib import Path
import hashlib
import re

from PIL import Image, ImageStat

APP = Path('lib/v5_app.dart')
TAXONOMY = Path('lib/models/animal_taxonomy.dart')
SPRITE = Path('assets/icons/animal_sprite_approved_v31.webp')
LIVESTOCK_GROUP = Path('assets/icons/livestock_group_approved_v31.webp')
DOGS_GROUP = Path('assets/icons/dogs_group_approved_v31.webp')
BIRDS_GROUP = Path('assets/icons/birds_group_approved_v31.webp')
EXPECTED_SHA256 = 'd07247f979f45fa704185681df86965fc81b11ed579bbcda186064275944308d'

# Vet AI 0.6.29 — EXACT user-approved FULL-COLOR animal artwork.
# This file is committed directly from the approved 5x5 reference sheet.
# Do NOT recreate it from v26/v29/v30 turquoise assets.
if not SPRITE.exists():
    raise SystemExit(f'Exact approved animal sprite is missing: {SPRITE}')

actual_sha = hashlib.sha256(SPRITE.read_bytes()).hexdigest()
if actual_sha != EXPECTED_SHA256:
    raise SystemExit(
        'Exact approved animal sprite checksum mismatch: '
        f'expected {EXPECTED_SHA256}, got {actual_sha}'
    )

with Image.open(SPRITE) as source_file:
    source = source_file.convert('RGB')
    width, height = source.size
    if (width, height) != (400, 400):
        raise SystemExit(
            f'Approved sprite must be the exact 400x400 5x5 sheet, got {width}x{height}'
        )
    if source.getbbox() is None:
        raise SystemExit('Exact approved animal sprite is blank')

    # The approved sheet contains warm natural animal colours (brown/yellow/red)
    # in addition to aqua washes. This prevents the old monochrome turquoise art
    # from ever passing the build guard again.
    warm_pixels = 0
    for r, g, b in source.resize((100, 100), Image.Resampling.BILINEAR).getdata():
        if (r > g * 1.08 and r > b * 1.10 and r > 100) or (r > 150 and g > 90 and b < 100):
            warm_pixels += 1
    if warm_pixels < 80:
        raise SystemExit(
            'Approved artwork colour guard failed; refusing old turquoise artwork'
        )

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
        if crop.getbbox() is None:
            raise SystemExit(f'Approved group crop {index} is blank')
        crop = crop.resize((400, 400), Image.Resampling.LANCZOS)
        crop.save(destination, format='WEBP', quality=95, method=6)

app = APP.read_text(encoding='utf-8')

# Replace EVERY historic/current path with the exact approved assets.
asset_replacements = {
    'assets/icons/animal_sprite_v26.webp': 'assets/icons/animal_sprite_approved_v31.webp',
    'assets/icons/animal_sprite_v29.webp': 'assets/icons/animal_sprite_approved_v31.webp',
    'assets/icons/animal_sprite_color_v30.webp': 'assets/icons/animal_sprite_approved_v31.webp',
    'assets/icons/livestock_group_v29.webp': 'assets/icons/livestock_group_approved_v31.webp',
    'assets/icons/livestock_group_transparent.webp': 'assets/icons/livestock_group_approved_v31.webp',
    'assets/icons/livestock_group_color_v30.webp': 'assets/icons/livestock_group_approved_v31.webp',
    'assets/icons/birds_group_v29.webp': 'assets/icons/birds_group_approved_v31.webp',
    'assets/icons/birds_group_transparent.webp': 'assets/icons/birds_group_approved_v31.webp',
    'assets/icons/birds_group_color_v30.webp': 'assets/icons/birds_group_approved_v31.webp',
    'assets/icons/dogs_group_v29.webp': 'assets/icons/dogs_group_approved_v31.webp',
    'assets/icons/dogs_group_transparent.webp': 'assets/icons/dogs_group_approved_v31.webp',
    'assets/icons/dogs_group_color_v30.webp': 'assets/icons/dogs_group_approved_v31.webp',
}
for old, new in asset_replacements.items():
    app = app.replace(old, new)
APP.write_text(app, encoding='utf-8')

# Exact approved 10-dog list and positions in the approved colour sheet.
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
    raise SystemExit(
        f'Could not install exact approved dog breed list; replacement count={count}'
    )
TAXONOMY.write_text(taxonomy, encoding='utf-8')

# Hard build guards: if old cyan artwork is referenced anywhere in the active
# app path, FAIL the build instead of shipping another wrong TestFlight build.
app_check = APP.read_text(encoding='utf-8')
taxonomy_check = TAXONOMY.read_text(encoding='utf-8')

required_app = (
    'assets/icons/animal_sprite_approved_v31.webp',
    'assets/icons/livestock_group_approved_v31.webp',
    'assets/icons/birds_group_approved_v31.webp',
    'assets/icons/dogs_group_approved_v31.webp',
)
for marker in required_app:
    if marker not in app_check:
        raise SystemExit(f'Exact approved artwork is not wired into app: {marker}')

for forbidden in (
    'assets/icons/animal_sprite_v26.webp',
    'assets/icons/animal_sprite_v29.webp',
    'assets/icons/animal_sprite_color_v30.webp',
    'assets/icons/livestock_group_v29.webp',
    'assets/icons/livestock_group_color_v30.webp',
    'assets/icons/birds_group_v29.webp',
    'assets/icons/birds_group_color_v30.webp',
    'assets/icons/dogs_group_v29.webp',
    'assets/icons/dogs_group_color_v30.webp',
):
    if forbidden in app_check:
        raise SystemExit(f'Old/turquoise artwork path is still active: {forbidden}')

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

# Validate files that Flutter will package.
if hashlib.sha256(SPRITE.read_bytes()).hexdigest() != EXPECTED_SHA256:
    raise SystemExit('Exact approved sprite changed before Flutter packaging')
for group_asset in (LIVESTOCK_GROUP, DOGS_GROUP, BIRDS_GROUP):
    with Image.open(group_asset) as group_image:
        rgb = group_image.convert('RGB')
        if rgb.size != (400, 400) or rgb.getbbox() is None:
            raise SystemExit(f'Generated approved group image is invalid: {group_asset}')
        stat = ImageStat.Stat(rgb)
        if max(stat.var) < 100:
            raise SystemExit(f'Generated approved group image has no usable detail: {group_asset}')

print(
    'Vet AI 0.6.29 EXACT APPROVED COLOR ARTWORK installed: '
    'livestock + birds + dogs group cards, species icons, and 10 dog breeds'
)
