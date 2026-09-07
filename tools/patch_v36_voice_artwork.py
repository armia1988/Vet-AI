from pathlib import Path
import base64
import re

from PIL import Image, ImageEnhance, ImageFilter

APP = Path('lib/v5_app.dart')
TAXONOMY = Path('lib/models/animal_taxonomy.dart')
CHUNK_DIR = Path('tools/approved_highres_animals_v36')
SPRITE = Path('assets/icons/animal_sprite_approved_v36.webp')
LIVESTOCK_GROUP = Path('assets/icons/livestock_group_approved_v36.webp')
DOGS_GROUP = Path('assets/icons/dogs_group_approved_v36.webp')
BIRDS_GROUP = Path('assets/icons/birds_group_approved_v36.webp')

# Vet AI 0.6.29 — V36 high-resolution artwork fix.
# The previous V34 source was only 300x300, meaning each 5x5 sprite tile was
# effectively 60x60 and then enlarged by Flutter. That is why the animals
# looked washed out / soft. V36 rebuilds the approved artwork from the
# high-resolution payload stored in the repository and never upscales V34.
chunks = sorted(CHUNK_DIR.glob('sprite.b64.*'))
if not chunks:
    raise SystemExit('V36 high-resolution approved animal payload is missing')

encoded = ''.join(p.read_text(encoding='utf-8').strip() for p in chunks)
try:
    sprite_bytes = base64.b64decode(encoded, validate=True)
except Exception as exc:
    raise SystemExit(f'V36 high-resolution animal payload could not decode: {exc}')

SPRITE.parent.mkdir(parents=True, exist_ok=True)
SPRITE.write_bytes(sprite_bytes)

with Image.open(SPRITE) as raw:
    source = raw.convert('RGBA')
    width, height = source.size

    # Do not ever ship another tiny source. Each tile must be at least 240px.
    if width != height or width % 5 != 0 or height % 5 != 0:
        raise SystemExit(f'V36 sprite must be a square 5x5 grid, got {width}x{height}')
    cell = width // 5
    if cell < 240:
        raise SystemExit(
            f'V36 artwork source is still too small: {width}x{height}, tile={cell}px. '
            'Refusing to build a blurry TestFlight version.'
        )

    # Improve perceived clarity without changing the approved illustration:
    # slight contrast / saturation restoration + a very light unsharp mask.
    # This is applied to the high-resolution source only; it is NOT an upscale.
    restored_rgb = source.convert('RGB')
    restored_rgb = ImageEnhance.Color(restored_rgb).enhance(1.08)
    restored_rgb = ImageEnhance.Contrast(restored_rgb).enhance(1.04)
    restored_rgb = restored_rgb.filter(
        ImageFilter.UnsharpMask(radius=0.8, percent=115, threshold=3)
    )
    restored = restored_rgb.convert('RGBA')

    # Save a clean high-resolution master for every individual animal tile.
    restored.save(SPRITE, format='WEBP', quality=96, method=6, exact=True)

    # First row of the approved master:
    # 0 = livestock group, 1 = dogs group, 2 = poultry group.
    # Crop directly from the high-resolution master; do not enlarge a 60px icon.
    for index, destination in {
        0: LIVESTOCK_GROUP,
        1: DOGS_GROUP,
        2: BIRDS_GROUP,
    }.items():
        col = index % 5
        row = index // 5
        crop = restored.crop((
            col * cell,
            row * cell,
            (col + 1) * cell,
            (row + 1) * cell,
        ))
        # Keep native detail. Only resize downward when the source is larger
        # than needed, never upward.
        if crop.width > 700:
            crop.thumbnail((700, 700), Image.Resampling.LANCZOS)
        crop.save(destination, format='WEBP', quality=96, method=6, exact=True)

app = APP.read_text(encoding='utf-8')

# Replace all historical artwork references with the cache-busted V36 assets.
old_sprites = (
    'assets/icons/animal_sprite_v26.webp',
    'assets/icons/animal_sprite_v29.webp',
    'assets/icons/animal_sprite_color_v30.webp',
    'assets/icons/animal_sprite_approved_v31.webp',
    'assets/icons/animal_sprite_approved_v34.webp',
)
for old in old_sprites:
    app = app.replace(old, str(SPRITE))

for old in (
    'assets/icons/livestock_group_v29.webp',
    'assets/icons/livestock_group_transparent.webp',
    'assets/icons/livestock_group_color_v30.webp',
    'assets/icons/livestock_group_approved_v31.webp',
    'assets/icons/livestock_group_approved_v34.webp',
):
    app = app.replace(old, str(LIVESTOCK_GROUP))

for old in (
    'assets/icons/dogs_group_v29.webp',
    'assets/icons/dogs_group_transparent.webp',
    'assets/icons/dogs_group_color_v30.webp',
    'assets/icons/dogs_group_approved_v31.webp',
    'assets/icons/dogs_group_approved_v34.webp',
):
    app = app.replace(old, str(DOGS_GROUP))

for old in (
    'assets/icons/birds_group_v29.webp',
    'assets/icons/birds_group_transparent.webp',
    'assets/icons/birds_group_color_v30.webp',
    'assets/icons/birds_group_approved_v31.webp',
    'assets/icons/birds_group_approved_v34.webp',
):
    app = app.replace(old, str(BIRDS_GROUP))

APP.write_text(app, encoding='utf-8')

# Keep exactly the 10 user-approved dog breeds and their approved sprite cells.
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
    raise SystemExit(f'Could not install approved dog breed list; count={count}')
TAXONOMY.write_text(taxonomy, encoding='utf-8')

# Hard guards: a successful build must use only V36 artwork.
app_check = APP.read_text(encoding='utf-8')
for required in (
    str(SPRITE),
    str(LIVESTOCK_GROUP),
    str(DOGS_GROUP),
    str(BIRDS_GROUP),
):
    if required not in app_check:
        raise SystemExit(f'V36 asset is not wired into the app: {required}')

for forbidden in (
    'animal_sprite_v26.webp',
    'animal_sprite_v29.webp',
    'animal_sprite_color_v30.webp',
    'animal_sprite_approved_v31.webp',
    'animal_sprite_approved_v34.webp',
    'group_v29.webp',
    'group_color_v30.webp',
    'group_approved_v31.webp',
    'group_approved_v34.webp',
):
    if forbidden in app_check:
        raise SystemExit(f'Old/blurry animal artwork still referenced: {forbidden}')

# Verify generated output itself, not just Dart paths.
with Image.open(SPRITE) as check:
    if check.width // 5 < 240:
        raise SystemExit('Generated V36 sprite unexpectedly lost resolution')
for group in (LIVESTOCK_GROUP, DOGS_GROUP, BIRDS_GROUP):
    with Image.open(group) as check:
        if min(check.size) < 240:
            raise SystemExit(f'Generated group artwork is too small: {group} {check.size}')

print(
    f'Vet AI V36 high-resolution animal artwork verified: '
    f'{width}x{height} master, {cell}x{cell} native tiles; no V34 60px upscale.'
)
