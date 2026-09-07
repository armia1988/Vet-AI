from pathlib import Path
import re

APP = Path('lib/v5_app.dart')
TAXONOMY = Path('lib/models/animal_taxonomy.dart')

# Vet AI 0.6.29 — approved FULL-COLOR animal artwork.
# These are local assets committed to the repository from the user's approved
# color references. Do not rebuild them from the old turquoise v26/v29 sprite.
ASSETS = (
    Path('assets/icons/animal_sprite_color_v30.webp'),
    Path('assets/icons/livestock_group_color_v30.webp'),
    Path('assets/icons/birds_group_color_v30.webp'),
    Path('assets/icons/dogs_group_color_v30.webp'),
)

for path in ASSETS:
    if not path.exists() or path.stat().st_size < 10000:
        raise SystemExit(f'Approved full-color animal asset is missing or invalid: {path}')

app = APP.read_text(encoding='utf-8')

asset_replacements = {
    'assets/icons/animal_sprite_v29.webp':
        'assets/icons/animal_sprite_color_v30.webp',
    'assets/icons/animal_sprite_v26.webp':
        'assets/icons/animal_sprite_color_v30.webp',
    'assets/icons/livestock_group_v29.webp':
        'assets/icons/livestock_group_color_v30.webp',
    'assets/icons/birds_group_v29.webp':
        'assets/icons/birds_group_color_v30.webp',
    'assets/icons/dogs_group_v29.webp':
        'assets/icons/dogs_group_color_v30.webp',
    'assets/icons/livestock_group_transparent.webp':
        'assets/icons/livestock_group_color_v30.webp',
    'assets/icons/birds_group_transparent.webp':
        'assets/icons/birds_group_color_v30.webp',
    'assets/icons/dogs_group_transparent.webp':
        'assets/icons/dogs_group_color_v30.webp',
}

for old, new in asset_replacements.items():
    app = app.replace(old, new)

APP.write_text(app, encoding='utf-8')

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

pattern = re.compile(
    r"const vetDogBreeds = <VetDogBreed>\[.*?\n\];",
    re.S,
)
taxonomy, count = pattern.subn(approved_dogs, taxonomy, count=1)
if count != 1:
    raise SystemExit(
        f'Could not install approved dog breed list; replacement count={count}'
    )

TAXONOMY.write_text(taxonomy, encoding='utf-8')

# Hard build guards. A future change must never silently bring the old art back.
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
        raise SystemExit(f'Full-color animal artwork is not wired into app: {marker}')

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
        raise SystemExit(f'Old dog breed is still in the selectable list: {forbidden}')

print(
    'Vet AI 0.6.29 full-color animal artwork installed: '
    'approved livestock, birds, dogs, species icons, and 10 approved dog breeds'
)
