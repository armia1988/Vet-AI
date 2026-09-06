from pathlib import Path
from collections import deque
from PIL import Image

ROOT = Path('.')
ASSETS = ROOT / 'assets/icons'
SOURCE = ASSETS / 'animal_sprite_v26.webp'
SPRITE_OUT = ASSETS / 'animal_sprite_transparent.png'
APP = ROOT / 'lib/v5_app.dart'
PUBSPEC = ROOT / 'pubspec.yaml'
CODEMAGIC = ROOT / 'codemagic.yaml'
VERIFY = ROOT / 'tools/verify_v29_transparent_artwork.py'

if not SOURCE.exists():
    raise SystemExit('Approved Vet AI animal sprite source is missing')


def remove_edge_background(image: Image.Image) -> Image.Image:
    """Remove only pale background connected to the cell edge.

    This preserves white fur/feathers inside the animal while removing the
    white/grey square that was visible in the app.
    """
    im = image.convert('RGBA')
    w, h = im.size
    px = im.load()
    seen = bytearray(w * h)
    q = deque()

    def candidate(x: int, y: int) -> bool:
        r, g, b, a = px[x, y]
        if a <= 8:
            return True
        hi, lo = max(r, g, b), min(r, g, b)
        # The approved artwork background is neutral and very light.
        return lo >= 198 and (hi - lo) <= 48

    def push(x: int, y: int) -> None:
        i = y * w + x
        if not seen[i] and candidate(x, y):
            seen[i] = 1
            q.append((x, y))

    for x in range(w):
        push(x, 0)
        push(x, h - 1)
    for y in range(h):
        push(0, y)
        push(w - 1, y)

    while q:
        x, y = q.popleft()
        r, g, b, _ = px[x, y]
        px[x, y] = (r, g, b, 0)
        if x:
            push(x - 1, y)
        if x + 1 < w:
            push(x + 1, y)
        if y:
            push(x, y - 1)
        if y + 1 < h:
            push(x, y + 1)

    # Clean the pale anti-aliased rim next to transparency, without touching
    # enclosed white parts of the animal.
    original = im.copy()
    opx = original.load()
    for _ in range(2):
        alpha = im.getchannel('A')
        ap = alpha.load()
        changes = []
        for y in range(1, h - 1):
            for x in range(1, w - 1):
                if ap[x, y] == 0:
                    continue
                if not (ap[x - 1, y] == 0 or ap[x + 1, y] == 0 or ap[x, y - 1] == 0 or ap[x, y + 1] == 0):
                    continue
                r, g, b, a = opx[x, y]
                hi, lo = max(r, g, b), min(r, g, b)
                if lo >= 208 and (hi - lo) <= 52:
                    changes.append((x, y))
        for x, y in changes:
            r, g, b, _ = px[x, y]
            px[x, y] = (r, g, b, 0)
    return im


source = Image.open(SOURCE).convert('RGBA')
w, h = source.size
if w % 5 or h % 5:
    raise SystemExit(f'Unexpected approved sprite dimensions: {source.size}')
cw, ch = w // 5, h // 5
cells = []
for index in range(25):
    col, row = index % 5, index // 5
    box = (col * cw, row * ch, (col + 1) * cw, (row + 1) * ch)
    cells.append(remove_edge_background(source.crop(box)))

transparent_sprite = Image.new('RGBA', source.size, (0, 0, 0, 0))
for index, cell in enumerate(cells):
    col, row = index % 5, index // 5
    transparent_sprite.alpha_composite(cell, (col * cw, row * ch))
transparent_sprite.save(SPRITE_OUT, format='PNG', optimize=True)


def trimmed(index: int) -> Image.Image:
    im = cells[index]
    alpha = im.getchannel('A')
    bbox = alpha.getbbox()
    if bbox is None:
        raise SystemExit(f'Approved animal sprite cell {index} became empty')
    l, t, r, b = bbox
    pad_x = max(2, int((r - l) * .035))
    pad_y = max(2, int((b - t) * .035))
    return im.crop((max(0, l - pad_x), max(0, t - pad_y), min(cw, r + pad_x), min(ch, b + pad_y)))


def paste_scaled(canvas: Image.Image, index: int, x: int, y: int, target_h: int) -> None:
    animal = trimmed(index)
    ratio = target_h / animal.height
    target_w = max(1, int(animal.width * ratio))
    animal = animal.resize((target_w, target_h), Image.Resampling.LANCZOS)
    canvas.alpha_composite(animal, (x, y))


def save_group(path: Path, placements: list[tuple[int, int, int, int]]) -> None:
    canvas = Image.new('RGBA', (900, 400), (0, 0, 0, 0))
    for index, x, y, target_h in placements:
        paste_scaled(canvas, index, x, y, target_h)
    bbox = canvas.getchannel('A').getbbox()
    if bbox is None:
        raise SystemExit(f'Generated group image is empty: {path}')
    l, t, r, b = bbox
    pad = 18
    canvas = canvas.crop((max(0, l - pad), max(0, t - pad), min(canvas.width, r + pad), min(canvas.height, b + pad)))
    canvas.save(path, format='PNG', optimize=True)


# Exact animal sets requested for each section, built from the already-approved
# individual artwork: livestock = cattle/buffalo/sheep/goat/horse; birds =
# chicken/chick/duck/turkey/goose; dogs = the approved three-dog hero.
save_group(
    ASSETS / 'livestock_group_transparent.png',
    [
        (4, 25, 88, 245),       # buffalo
        (3, 235, 28, 315),      # cattle
        (7, 565, 48, 300),      # horse
        (5, 140, 205, 175),     # sheep
        (6, 650, 215, 165),     # goat
    ],
)
save_group(
    ASSETS / 'birds_group_transparent.png',
    [
        (8, 35, 72, 265),       # chicken
        (11, 280, 42, 305),     # turkey
        (12, 605, 50, 285),     # goose
        (10, 505, 205, 165),    # duck
        (9, 190, 250, 110),     # chick
    ],
)
save_group(
    ASSETS / 'dogs_group_transparent.png',
    [
        (15, 35, 58, 300),      # Rottweiler
        (13, 305, 25, 340),     # German Shepherd
        (20, 605, 60, 295),     # Pit Bull / AmStaff
    ],
)

app = APP.read_text(encoding='utf-8')
app = app.replace("'assets/icons/animal_sprite_v26.webp'", "'assets/icons/animal_sprite_transparent.png'")
app = app.replace("'assets/icons/livestock_group_transparent.webp'", "'assets/icons/livestock_group_transparent.png'")
app = app.replace("'assets/icons/birds_group_transparent.webp'", "'assets/icons/birds_group_transparent.png'")
app = app.replace("'assets/icons/dogs_group_transparent.webp'", "'assets/icons/dogs_group_transparent.png'")

# Never silently hide a group image again. If an asset ever fails, show the
# corresponding transparent sprite cell instead of an empty box.
old_error = "errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),"
new_error = """errorBuilder: (context, error, stackTrace) => _AnimalSprite(
        index: asset.contains('dogs') ? 1 : asset.contains('birds') ? 2 : 0,
        size: size,
        radius: 0,
      ),"""
if old_error in app:
    app = app.replace(old_error, new_error, 1)

for marker in (
    'animal_sprite_transparent.png',
    'livestock_group_transparent.png',
    'birds_group_transparent.png',
    'dogs_group_transparent.png',
):
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
    if not p.exists() or p.stat().st_size < 8000:
        raise SystemExit(f'Transparent Vet AI artwork missing or too small: {path}')
    image = Image.open(p).convert('RGBA')
    alpha = image.getchannel('A')
    amin, amax = alpha.getextrema()
    if amin != 0 or amax != 255:
        raise SystemExit(f'Artwork is not truly transparent: {path}; alpha={amin, amax}')
    histogram = alpha.histogram()
    transparent = histogram[0]
    if transparent < image.width * image.height * .10:
        raise SystemExit(f'Artwork still contains an opaque background: {path}')

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

print('Vet AI 0.6.29 transparent approved artwork generated and applied')
