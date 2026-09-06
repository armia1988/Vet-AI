from pathlib import Path
from collections import deque
from PIL import Image, ImageEnhance, ImageFilter

APP = Path('lib/v5_app.dart')
PUBSPEC = Path('pubspec.yaml')
SRC = Path('assets/icons/animal_sprite_v26.webp')
OUT_SPRITE = Path('assets/icons/animal_sprite_v29.webp')
OUT_LIVESTOCK = Path('assets/icons/livestock_group_v29.webp')
OUT_BIRDS = Path('assets/icons/birds_group_v29.webp')
OUT_DOGS = Path('assets/icons/dogs_group_v29.webp')


def flood_remove_background(cell: Image.Image) -> Image.Image:
    im = cell.convert('RGBA')
    w, h = im.size
    px = im.load()
    visited = bytearray(w * h)
    q = deque()

    def is_bg(x: int, y: int) -> bool:
        r, g, b, a = px[x, y]
        if a <= 8:
            return True
        mx = max(r, g, b)
        mn = min(r, g, b)
        # The old artwork uses a white/very-pale square behind every animal.
        # Only flood pixels connected to the cell edge so white fur is preserved.
        return mn >= 226 and (mx - mn) <= 22

    for x in range(w):
        for y in (0, h - 1):
            if is_bg(x, y):
                q.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            if is_bg(x, y):
                q.append((x, y))

    while q:
        x, y = q.popleft()
        idx = y * w + x
        if visited[idx]:
            continue
        visited[idx] = 1
        if not is_bg(x, y):
            continue
        r, g, b, _ = px[x, y]
        px[x, y] = (r, g, b, 0)
        if x > 0:
            q.append((x - 1, y))
        if x + 1 < w:
            q.append((x + 1, y))
        if y > 0:
            q.append((x, y - 1))
        if y + 1 < h:
            q.append((x, y + 1))

    # Clean the pale anti-aliased halo touching transparency without erasing white fur.
    alpha = im.getchannel('A')
    edge = alpha.filter(ImageFilter.MinFilter(3))
    edge_px = edge.load()
    for y in range(h):
        for x in range(w):
            if px[x, y][3] == 0:
                continue
            r, g, b, a = px[x, y]
            if edge_px[x, y] == 0 and min(r, g, b) >= 238 and max(r, g, b) - min(r, g, b) <= 16:
                px[x, y] = (r, g, b, max(0, a - 190))

    # Slightly strengthen the artwork so it no longer looks washed out.
    rgb = Image.new('RGB', im.size, 'white')
    rgb.paste(im.convert('RGB'), mask=im.getchannel('A'))
    rgb = ImageEnhance.Contrast(rgb).enhance(1.12)
    rgb = ImageEnhance.Color(rgb).enhance(1.10)
    rgb = ImageEnhance.Sharpness(rgb).enhance(1.25)
    enhanced = rgb.convert('RGBA')
    enhanced.putalpha(im.getchannel('A'))
    return enhanced


def trim_subject(im: Image.Image, pad: int = 10) -> Image.Image:
    alpha = im.getchannel('A')
    bbox = alpha.getbbox()
    if not bbox:
        return im
    l, t, r, b = bbox
    l = max(0, l - pad)
    t = max(0, t - pad)
    r = min(im.width, r + pad)
    b = min(im.height, b + pad)
    return im.crop((l, t, r, b))


def fit_subject(subject: Image.Image, box_w: int, box_h: int) -> Image.Image:
    s = subject.copy()
    s.thumbnail((box_w, box_h), Image.Resampling.LANCZOS)
    return s


def make_group(cells, indices, placements, destination):
    canvas = Image.new('RGBA', (900, 650), (0, 0, 0, 0))
    for index, (x, y, bw, bh) in zip(indices, placements):
        subject = fit_subject(trim_subject(cells[index], 8), bw, bh)
        px = x + (bw - subject.width) // 2
        py = y + (bh - subject.height)
        canvas.alpha_composite(subject, (px, py))
    bbox = canvas.getchannel('A').getbbox()
    if bbox:
        l, t, r, b = bbox
        pad = 18
        crop = canvas.crop((max(0, l-pad), max(0, t-pad), min(900, r+pad), min(650, b+pad)))
        out = Image.new('RGBA', (900, 650), (0, 0, 0, 0))
        crop.thumbnail((860, 610), Image.Resampling.LANCZOS)
        out.alpha_composite(crop, ((900-crop.width)//2, (650-crop.height)//2))
    else:
        out = canvas
    out.save(destination, 'WEBP', quality=96, method=6, exact=True)


src = Image.open(SRC).convert('RGBA')
if src.width % 5 or src.height % 5:
    raise SystemExit(f'Unexpected sprite dimensions: {src.size}')
cell_w = src.width // 5
cell_h = src.height // 5
cells = []
for idx in range(25):
    col = idx % 5
    row = idx // 5
    cell = src.crop((col*cell_w, row*cell_h, (col+1)*cell_w, (row+1)*cell_h))
    cells.append(flood_remove_background(cell))

sprite = Image.new('RGBA', src.size, (0, 0, 0, 0))
for idx, cell in enumerate(cells):
    col = idx % 5
    row = idx // 5
    sprite.alpha_composite(cell, (col*cell_w, row*cell_h))
sprite.save(OUT_SPRITE, 'WEBP', quality=96, method=6, exact=True)

# Same animal set the user approved: cattle, buffalo, sheep, goat, horse.
make_group(
    cells,
    [4, 3, 7, 5, 6],
    [(25, 70, 265, 410), (225, 25, 315, 500), (555, 45, 285, 450), (80, 300, 245, 290), (585, 305, 220, 270)],
    OUT_LIVESTOCK,
)
# Chicken, chick, duck, turkey and goose. No quail.
make_group(
    cells,
    [8, 11, 10, 12, 9],
    [(25, 130, 245, 390), (270, 40, 310, 480), (545, 185, 235, 335), (675, 65, 190, 420), (225, 365, 155, 180)],
    OUT_BIRDS,
)
# Approved dog-group composition: Rottweiler, German Shepherd and Pit Bull/AmStaff.
make_group(
    cells,
    [15, 13, 20],
    [(55, 80, 280, 470), (305, 20, 320, 540), (585, 90, 265, 460)],
    OUT_DOGS,
)

app = APP.read_text(encoding='utf-8')
app = app.replace("assets/icons/animal_sprite_v26.webp", "assets/icons/animal_sprite_v29.webp")
for old, new in {
    'assets/icons/livestock_group_transparent.webp': 'assets/icons/livestock_group_v29.webp',
    'assets/icons/birds_group_transparent.webp': 'assets/icons/birds_group_v29.webp',
    'assets/icons/dogs_group_transparent.webp': 'assets/icons/dogs_group_v29.webp',
}.items():
    app = app.replace(old, new)

# Make the image itself transparent over the card instead of looking like a white square.
app = app.replace(
    "color: selected\n              ? VetColors.primary.withValues(alpha: .10)\n              : Colors.white,",
    "color: selected\n              ? VetColors.primary.withValues(alpha: .10)\n              : Colors.transparent,",
)
# A little larger and clearer without changing the surrounding layout.
app = app.replace('this.imageSize = 86,', 'this.imageSize = 102,')
app = app.replace('imageSize: 88,', 'imageSize: 102,')
app = app.replace('imageSize: options.length == 1 ? 102 : 88,', 'imageSize: options.length == 1 ? 116 : 102,')
app = app.replace('size: 112,', 'size: 128,')
app = app.replace('size: 156,', 'size: 170,')
app = app.replace('size: 176,', 'size: 190,')
APP.write_text(app, encoding='utf-8')

pubspec = PUBSPEC.read_text(encoding='utf-8')
if 'version: 0.6.28+40' not in pubspec:
    raise SystemExit('Expected Vet AI 0.6.28+40 before v29 patch')
pubspec = pubspec.replace('version: 0.6.28+40', 'version: 0.6.29+41', 1)
PUBSPEC.write_text(pubspec, encoding='utf-8')

print('Vet AI 0.6.29: transparent individual animal art + visible group images generated')
