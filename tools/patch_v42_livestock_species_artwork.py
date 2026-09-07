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
    if (index >= 3 && index <= 7) {
      const livestockColumns = 5;
      final livestockCol = index - 3;
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox.square(
          dimension: size,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                left: -livestockCol * size,
                top: 0,
                width: size * livestockColumns,
                height: size,
                child: Image.asset(
                  'assets/icons/livestock_species_v32.webp',
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

if old not in text:
    raise SystemExit('Vet AI livestock artwork patch could not find the expected _AnimalSprite block')

path.write_text(text.replace(old, new, 1), encoding='utf-8')
print('Vet AI livestock species artwork v32 applied: cattle, buffalo, sheep, goat, horse')
