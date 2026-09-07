from pathlib import Path
import base64
import hashlib

ROOT = Path('.')
APP = ROOT / 'lib/v5_app.dart'
TAX = ROOT / 'lib/models/animal_taxonomy.dart'
PUBSPEC = ROOT / 'pubspec.yaml'
PARTS = ROOT / 'tools/v30_final_sprite_parts'
OUT = ROOT / 'assets/icons/animal_sprite_v30.webp'

EXPECTED_SIZE = 140582
EXPECTED_SHA256 = '814df5b49ec3d37ef540fcf5527e1fca47876f62a4a6bfea462ca6961c271df4'

encoded = ''.join(p.read_text(encoding='utf-8').strip() for p in sorted(PARTS.glob('part*.txt')))
if not encoded:
    raise SystemExit('v30 approved artwork payload is missing')
raw = base64.b64decode(encoded, validate=True)
if len(raw) != EXPECTED_SIZE:
    raise SystemExit(f'Unexpected v30 sprite size: {len(raw)}')
if hashlib.sha256(raw).hexdigest() != EXPECTED_SHA256:
    raise SystemExit('v30 sprite checksum mismatch')
if raw[:4] != b'RIFF' or raw[8:12] != b'WEBP':
    raise SystemExit('v30 artwork is not a WEBP file')
OUT.write_bytes(raw)

app = APP.read_text(encoding='utf-8')
app = app.replace("'assets/icons/animal_sprite_v29.webp'", "'assets/icons/animal_sprite_v30.webp'")

old_group = """  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: Image.asset(
      asset,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      isAntiAlias: true,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
    ),
  );
}"""
new_group = """  @override
  Widget build(BuildContext context) {
    final spriteIndex = asset.contains('dogs')
        ? 1
        : asset.contains('birds') || asset.contains('poultry')
        ? 2
        : 0;
    return _AnimalSprite(index: spriteIndex, size: size, radius: 16);
  }
}"""
if old_group not in app:
    raise SystemExit('Animal group image widget did not match expected v29 code')
app = app.replace(old_group, new_group, 1)

# Keep the approved artwork at or below its native 160px cell size so it stays crisp.
app = app.replace('size: 190,', 'size: 160,')
app = app.replace('size: 170,', 'size: 160,')
APP.write_text(app, encoding='utf-8')

tax = TAX.read_text(encoding='utf-8')
start = tax.index('const vetDogBreeds = <VetDogBreed>[')
end = tax.index('\n\nList<VetAnimalSpecies> vetSpeciesForGroup', start)
new_breeds = """const vetDogBreeds = <VetDogBreed>[
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
    en: 'Doberman',
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
    // Keep the historic code for saved-profile compatibility; display is Mastiff.
    code: 'cane_corso',
    en: 'Mastiff',
    ar: 'ماستيف',
    nl: 'Mastiff',
    spriteIndex: 19,
  ),
];"""
tax = tax[:start] + new_breeds + tax[end:]
TAX.write_text(tax, encoding='utf-8')

pubspec = PUBSPEC.read_text(encoding='utf-8')
if 'version: 0.6.29+41' not in pubspec:
    raise SystemExit('Expected 0.6.29+41 version marker missing')
pubspec = pubspec.replace('version: 0.6.29+41', 'version: 0.6.30+42', 1)
PUBSPEC.write_text(pubspec, encoding='utf-8')

print('Vet AI 0.6.30 final approved animal artwork installed with exact taxonomy mapping')
