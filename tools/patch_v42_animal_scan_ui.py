from pathlib import Path
import re

APP = Path('lib/v5_app.dart')
PUBSPEC = Path('pubspec.yaml')

text = APP.read_text(encoding='utf-8')

old_asset = """  String asset(String g) => g == 'poultry'\n      ? 'assets/icons/poultry_section.webp'\n      : g == 'dogs'\n      ? 'assets/icons/dog_section.webp'\n      : 'assets/icons/livestock_section.webp';"""
new_asset = """  String asset(String g) => g == 'poultry'\n      ? 'assets/icons/poultry_final.png'\n      : g == 'dogs'\n      ? 'assets/icons/dog_final.png'\n      : 'assets/icons/livestock_final.png';"""
if old_asset not in text:
    raise SystemExit('Expected scan asset mapping was not found')
text = text.replace(old_asset, new_asset, 1)

banner_pattern = re.compile(
    r"class _AnimalGroupBanner extends StatelessWidget \{.*?\n\}\n\nclass _AnimalChoice",
    re.S,
)
new_banner = r'''class _AnimalGroupBanner extends StatelessWidget {
  const _AnimalGroupBanner({
    required this.asset,
    required this.title,
    required this.text,
  });
  final String asset;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    decoration: BoxDecoration(
      color: VetColors.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: VetColors.border),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 172,
          height: 126,
          child: Image.asset(
            asset,
            fit: BoxFit.contain,
            alignment: Alignment.center,
            filterQuality: FilterQuality.high,
            isAntiAlias: true,
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) => Center(
              child: asset.contains('livestock')
                  ? SvgPicture.asset(
                      'assets/icons/cow.svg',
                      width: 100,
                      height: 100,
                      fit: BoxFit.contain,
                    )
                  : Icon(
                      asset.contains('poultry')
                          ? Icons.flutter_dash_rounded
                          : Icons.pets_rounded,
                      size: 76,
                      color: VetColors.primary,
                    ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                text,
                style: const TextStyle(
                  color: VetColors.muted,
                  height: 1.4,
                  fontSize: 13.5,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _AnimalChoice'''
text, count = banner_pattern.subn(new_banner, text, count=1)
if count != 1:
    raise SystemExit(f'Animal group banner replacement count was {count}')

species_pattern = re.compile(r"class _SpeciesSingleSelect extends StatelessWidget \{.*\}\s*\Z", re.S)
new_species = r'''class _SpeciesSingleSelect extends StatelessWidget {
  const _SpeciesSingleSelect({
    required this.title,
    required this.options,
    required this.selectedCode,
    required this.enabled,
    required this.onChanged,
  });
  final String title;
  final List<VetAnimalSpecies> options;
  final String selectedCode;
  final bool enabled;
  final ValueChanged<String> onChanged;

  Widget _speciesArtwork(VetAnimalSpecies item) {
    Widget child;
    switch (item.code) {
      case 'cattle':
        child = SvgPicture.asset(
          'assets/icons/cow.svg',
          fit: BoxFit.contain,
        );
        break;
      case 'buffalo':
        child = SvgPicture.asset(
          'assets/icons/buffalo.svg',
          fit: BoxFit.contain,
        );
        break;
      case 'chicken':
        child = SvgPicture.asset(
          'assets/icons/chicken.svg',
          fit: BoxFit.contain,
        );
        break;
      case 'chick':
        child = SvgPicture.asset(
          'assets/icons/chick.svg',
          fit: BoxFit.contain,
        );
        break;
      default:
        child = Center(
          child: Text(item.emoji, style: const TextStyle(fontSize: 34)),
        );
    }
    return SizedBox(width: 42, height: 42, child: child);
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: VetColors.softBlue,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: VetColors.blue.withValues(alpha: .2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.pets_outlined, color: VetColors.blue, size: 31),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          Wrap(
            spacing: 9,
            runSpacing: 9,
            children: options.map((item) {
              final label = locale == 'ar'
                  ? item.ar
                  : locale == 'nl'
                  ? item.nl
                  : item.en;
              final active = selectedCode == item.code;
              return ChoiceChip(
                labelPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _speciesArtwork(item),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: active ? FontWeight.w900 : FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                selected: active,
                selectedColor: VetColors.primary.withValues(alpha: .22),
                backgroundColor: Colors.white,
                side: BorderSide(
                  color: active ? VetColors.primary : VetColors.border,
                  width: active ? 2.2 : 1,
                ),
                onSelected: enabled ? (_) => onChanged(item.code) : null,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
'''
text, count = species_pattern.subn(new_species, text, count=1)
if count != 1:
    raise SystemExit(f'Species selector replacement count was {count}')

APP.write_text(text, encoding='utf-8')

pubspec = PUBSPEC.read_text(encoding='utf-8')
if 'version: 0.6.24+36' not in pubspec:
    raise SystemExit('Expected 0.6.24+36 version marker was not found')
pubspec = pubspec.replace('version: 0.6.24+36', 'version: 0.6.25+37', 1)
PUBSPEC.write_text(pubspec, encoding='utf-8')

print('Vet AI 0.6.25 animal scan artwork patch applied')
