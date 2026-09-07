from pathlib import Path

path = Path('lib/v5_app.dart')
text = path.read_text(encoding='utf-8')

marker = "assets/icons/livestock_species_v32.webp"
if marker in text:
    print('Vet AI livestock species artwork v32 already applied')
    raise SystemExit(0)

old = '''  @override
  Widget build(BuildContext context) {
    const columns = 5;
    const rows = 5;
    final col = index % columns;
    final row = index ~/ columns;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              left: -col * size,
              top: -row * size,
              width: size * columns,
              height: size * rows,
              child: Image.asset(
                'assets/icons/animal_sprite_v29.webp',
                fit: BoxFit.fill,
                filterQuality: FilterQuality.high,
                isAntiAlias: true,
                gaplessPlayback: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
'''

new = '''  @override
  Widget build(BuildContext context) {
    // The approved v32 livestock artwork is a single cattle image, not a
    // five-column sprite sheet. Show it as a complete contained image for
    // cattle instead of slicing it into five cropped strips.
    if (index == 3) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox.square(
          dimension: size,
          child: Padding(
            padding: EdgeInsets.all(size * 0.10),
            child: Image.asset(
              'assets/icons/livestock_species_v32.webp',
              fit: BoxFit.contain,
              alignment: Alignment.center,
              filterQuality: FilterQuality.high,
              isAntiAlias: true,
              gaplessPlayback: true,
            ),
          ),
        ),
      );
    }

    const columns = 5;
    const rows = 5;
    final col = index % columns;
    final row = index ~/ columns;

    // Keep the other livestock species mapped to their correct cells in the
    // existing animal sprite, but render those cells slightly smaller so the
    // complete animal stays visible inside the rounded icon tile.
    if (index >= 4 && index <= 7) {
      final fittedSize = size * 0.84;
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox.square(
          dimension: size,
          child: Center(
            child: SizedBox.square(
              dimension: fittedSize,
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  Positioned(
                    left: -col * fittedSize,
                    top: -row * fittedSize,
                    width: fittedSize * columns,
                    height: fittedSize * rows,
                    child: Image.asset(
                      'assets/icons/animal_sprite_v29.webp',
                      fit: BoxFit.fill,
                      filterQuality: FilterQuality.high,
                      isAntiAlias: true,
                      gaplessPlayback: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              left: -col * size,
              top: -row * size,
              width: size * columns,
              height: size * rows,
              child: Image.asset(
                'assets/icons/animal_sprite_v29.webp',
                fit: BoxFit.fill,
                filterQuality: FilterQuality.high,
                isAntiAlias: true,
                gaplessPlayback: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
'''

if old not in text:
    raise SystemExit('Vet AI livestock artwork patch could not find the expected _AnimalSprite block')

path.write_text(text.replace(old, new, 1), encoding='utf-8')
print('Vet AI livestock icon fit applied: full cattle image + correctly mapped fitted livestock cells')
