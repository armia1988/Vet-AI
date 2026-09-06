from pathlib import Path

APP = Path('lib/v5_app.dart')
text = APP.read_text(encoding='utf-8')

helper = r'''String _animalGroupAssetFromSpriteIndex(int spriteIndex) => switch (spriteIndex) {
  1 => 'assets/icons/dogs_group_transparent.webp',
  2 => 'assets/icons/birds_group_transparent.webp',
  _ => 'assets/icons/livestock_group_transparent.webp',
};

String _animalGroupAssetFromGroup(String group) => switch (group) {
  'dogs' => 'assets/icons/dogs_group_transparent.webp',
  'poultry' => 'assets/icons/birds_group_transparent.webp',
  _ => 'assets/icons/livestock_group_transparent.webp',
};

String _animalGroupAssetFromLegacyAsset(String asset) {
  if (asset.contains('poultry')) return 'assets/icons/birds_group_transparent.webp';
  if (asset.contains('dog')) return 'assets/icons/dogs_group_transparent.webp';
  return 'assets/icons/livestock_group_transparent.webp';
}

class _AnimalGroupImage extends StatelessWidget {
  const _AnimalGroupImage({required this.asset, required this.size});

  final String asset;
  final double size;

  @override
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
}
'''

marker = 'class _AnimalGroupBanner extends StatelessWidget {'
if '_animalGroupAssetFromSpriteIndex' not in text:
    if marker not in text:
        raise SystemExit('Animal group banner marker not found')
    text = text.replace(marker, helper + '\n\n' + marker, 1)

old_banner = '_AnimalSprite(index: spriteIndex, size: 142, radius: 16),'
new_banner = '''_AnimalGroupImage(
          asset: _animalGroupAssetFromSpriteIndex(spriteIndex),
          size: 156,
        ),'''
if old_banner not in text:
    raise SystemExit('Old group banner artwork call not found')
text = text.replace(old_banner, new_banner, 1)

old_choice = '''_AnimalSprite(
            index: group == 'poultry'
                ? 2
                : group == 'dogs'
                ? 1
                : 0,
            size: 86,
            radius: 12,
          ),'''
new_choice = '''_AnimalGroupImage(
            asset: _animalGroupAssetFromGroup(group),
            size: 96,
          ),'''
if old_choice not in text:
    raise SystemExit('Old group choice artwork call not found')
text = text.replace(old_choice, new_choice, 1)

old_count = '''_AnimalSprite(
              index: asset.contains('poultry')
                  ? 2
                  : asset.contains('dog')
                  ? 1
                  : 0,
              size: 164,
              radius: 14,
            ),'''
new_count = '''_AnimalGroupImage(
              asset: _animalGroupAssetFromLegacyAsset(asset),
              size: 176,
            ),'''
if old_count not in text:
    raise SystemExit('Old animal count artwork call not found')
text = text.replace(old_count, new_count, 1)

old_profile_group = '_AnimalSprite(index: spriteIndex, size: 104, radius: 14),'
new_profile_group = '''_AnimalGroupImage(
            asset: _animalGroupAssetFromSpriteIndex(spriteIndex),
            size: 112,
          ),'''
if old_profile_group not in text:
    raise SystemExit('Old profile group artwork call not found')
text = text.replace(old_profile_group, new_profile_group, 1)

# The group art must never be tinted, faded, clipped into a square or given a background.
for asset in (
    'livestock_group_transparent.webp',
    'birds_group_transparent.webp',
    'dogs_group_transparent.webp',
):
    if asset not in text:
        raise SystemExit(f'Missing group asset reference: {asset}')

APP.write_text(text, encoding='utf-8')
print('Vet AI transparent group artwork patch applied')
