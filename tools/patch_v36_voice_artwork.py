from pathlib import Path
from shutil import copyfile

from PIL import Image

APP = Path('lib/v5_app.dart')
TAXONOMY = Path('lib/models/animal_taxonomy.dart')
APPROVED_SPRITE = Path('assets/icons/animal_sprite_v26.webp')
RUNTIME_SPRITE = Path('assets/icons/animal_sprite_v29.webp')

# The user-approved artwork is the original v26 5x5 sprite.  Keep the exact
# approved illustrations and only derive the three group crops from that same
# source.  Do not recolor, redraw, flood-fill, sharpen, or replace them with
# emojis/network images.
GROUP_CROPS = {
    0: Path('assets/icons/livestock_group_v29.webp'),
    1: Path('assets/icons/dogs_group_v29.webp'),
    2: Path('assets/icons/birds_group_v29.webp'),
}

if not APPROVED_SPRITE.exists():
    raise SystemExit(f'Approved animal sprite is missing: {APPROVED_SPRITE}')

# Individual species and dog-breed cards use animal_sprite_v29.webp.  Make that
# runtime file a byte-for-byte copy of the approved source before every build.
copyfile(APPROVED_SPRITE, RUNTIME_SPRITE)

with Image.open(APPROVED_SPRITE) as source:
    source = source.convert('RGBA')
    width, height = source.size
    if width % 5 != 0 or height % 5 != 0:
        raise SystemExit(
            f'Approved sprite must be a 5x5 grid, got {width}x{height}'
        )
    cell_w = width // 5
    cell_h = height // 5

    for index, destination in GROUP_CROPS.items():
        col = index % 5
        row = index // 5
        crop = source.crop(
            (
                col * cell_w,
                row * cell_h,
                (col + 1) * cell_w,
                (row + 1) * cell_h,
            )
        )
        crop.save(
            destination,
            format='WEBP',
            lossless=True,
            quality=100,
            method=6,
            exact=True,
        )

app = APP.read_text(encoding='utf-8')
taxonomy = TAXONOMY.read_text(encoding='utf-8')

# Hard guards: if a future UI change stops using the approved local artwork,
# fail the build instead of silently shipping the wrong icons again.
required_app_markers = (
    'assets/icons/animal_sprite_v29.webp',
    'assets/icons/livestock_group_v29.webp',
    'assets/icons/birds_group_v29.webp',
    'assets/icons/dogs_group_v29.webp',
)
for marker in required_app_markers:
    if marker not in app:
        raise SystemExit(f'Approved artwork wiring missing from app: {marker}')

required_taxonomy_markers = (
    "code: 'cattle'",
    'spriteIndex: 3',
    "code: 'chicken'",
    'spriteIndex: 8',
    "code: 'german_shepherd'",
    'spriteIndex: 13',
    "code: 'chihuahua'",
    'spriteIndex: 22',
)
for marker in required_taxonomy_markers:
    if marker not in taxonomy:
        raise SystemExit(f'Approved animal mapping missing: {marker}')

if RUNTIME_SPRITE.read_bytes() != APPROVED_SPRITE.read_bytes():
    raise SystemExit('Runtime animal sprite is not the exact approved sprite')

for destination in GROUP_CROPS.values():
    if not destination.exists() or destination.stat().st_size < 1000:
        raise SystemExit(f'Approved group artwork was not generated: {destination}')

print(
    'Vet AI approved animal artwork locked: exact v26 sprite + livestock, birds, and dogs group crops installed'
)
