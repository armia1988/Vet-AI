from pathlib import Path
import re

APP = Path('lib/v5_app.dart')
TAX = Path('lib/models/animal_taxonomy.dart')
PUB = Path('pubspec.yaml')

# -----------------------------------------------------------------------------
# Replace taxonomy with the approved species / breed artwork mapping.
# Sprite indices are cells in assets/icons/animal_sprite_v26.webp (5 columns).
# -----------------------------------------------------------------------------
TAX.write_text(r'''import 'package:flutter/material.dart';

class VetAnimalSpecies {
  const VetAnimalSpecies({
    required this.code,
    required this.group,
    required this.en,
    required this.ar,
    required this.nl,
    required this.icon,
    required this.emoji,
    required this.spriteIndex,
    this.diseaseScopeAliases = const [],
  });

  final String code;
  final String group;
  final String en;
  final String ar;
  final String nl;
  final IconData icon;
  final String emoji;
  final int spriteIndex;
  final List<String> diseaseScopeAliases;
}

class VetDogBreed {
  const VetDogBreed({
    required this.code,
    required this.en,
    required this.ar,
    required this.nl,
    required this.spriteIndex,
  });
  final String code;
  final String en;
  final String ar;
  final String nl;
  final int spriteIndex;
}

const vetLivestockSpecies = <VetAnimalSpecies>[
  VetAnimalSpecies(code: 'cattle', group: 'livestock', en: 'Cattle', ar: 'أبقار', nl: 'Runderen', icon: Icons.pets_rounded, emoji: '🐄', spriteIndex: 3, diseaseScopeAliases: ['cattle', 'cow', 'calf', 'bovine']),
  VetAnimalSpecies(code: 'buffalo', group: 'livestock', en: 'Buffalo', ar: 'جاموس', nl: 'Buffels', icon: Icons.pets_rounded, emoji: '🐃', spriteIndex: 4, diseaseScopeAliases: ['buffalo', 'water buffalo']),
  VetAnimalSpecies(code: 'sheep', group: 'livestock', en: 'Sheep', ar: 'أغنام / خراف', nl: 'Schapen', icon: Icons.pets_rounded, emoji: '🐑', spriteIndex: 5, diseaseScopeAliases: ['sheep', 'lamb', 'ovine']),
  VetAnimalSpecies(code: 'goat', group: 'livestock', en: 'Goats', ar: 'ماعز', nl: 'Geiten', icon: Icons.pets_rounded, emoji: '🐐', spriteIndex: 6, diseaseScopeAliases: ['goat', 'kid', 'caprine']),
  VetAnimalSpecies(code: 'horse', group: 'livestock', en: 'Horses', ar: 'خيول / أحصنة', nl: 'Paarden', icon: Icons.pets_rounded, emoji: '🐎', spriteIndex: 7, diseaseScopeAliases: ['horse', 'equine', 'foal']),
];

const vetBirdSpecies = <VetAnimalSpecies>[
  VetAnimalSpecies(code: 'chicken', group: 'poultry', en: 'Chickens', ar: 'دجاج', nl: 'Kippen', icon: Icons.flutter_dash_rounded, emoji: '🐔', spriteIndex: 8, diseaseScopeAliases: ['chicken', 'poultry', 'hen', 'rooster']),
  VetAnimalSpecies(code: 'chick', group: 'poultry', en: 'Chicks', ar: 'كتاكيت', nl: 'Kuikens', icon: Icons.flutter_dash_rounded, emoji: '🐣', spriteIndex: 9, diseaseScopeAliases: ['chick', 'chicken', 'poultry']),
  VetAnimalSpecies(code: 'duck', group: 'poultry', en: 'Ducks', ar: 'بط', nl: 'Eenden', icon: Icons.flutter_dash_rounded, emoji: '🦆', spriteIndex: 10, diseaseScopeAliases: ['duck', 'waterfowl']),
  VetAnimalSpecies(code: 'turkey', group: 'poultry', en: 'Turkeys', ar: 'ديك رومي', nl: 'Kalkoenen', icon: Icons.flutter_dash_rounded, emoji: '🦃', spriteIndex: 11, diseaseScopeAliases: ['turkey', 'poultry']),
  VetAnimalSpecies(code: 'goose', group: 'poultry', en: 'Geese', ar: 'أوز', nl: 'Ganzen', icon: Icons.flutter_dash_rounded, emoji: '🪿', spriteIndex: 12, diseaseScopeAliases: ['goose', 'geese', 'waterfowl']),
];

const vetDogSpecies = VetAnimalSpecies(
  code: 'dog',
  group: 'dogs',
  en: 'Dogs',
  ar: 'كلاب',
  nl: 'Honden',
  icon: Icons.pets_rounded,
  emoji: '🐕',
  spriteIndex: 1,
  diseaseScopeAliases: ['dog', 'canine'],
);

const vetDogBreeds = <VetDogBreed>[
  VetDogBreed(code: 'german_shepherd', en: 'German Shepherd', ar: 'جيرمن شيبرد', nl: 'Duitse herder', spriteIndex: 13),
  VetDogBreed(code: 'belgian_malinois', en: 'Belgian Malinois', ar: 'مالينوي بلجيكي', nl: 'Mechelse herder', spriteIndex: 14),
  VetDogBreed(code: 'rottweiler', en: 'Rottweiler', ar: 'روت وايلر', nl: 'Rottweiler', spriteIndex: 15),
  VetDogBreed(code: 'labrador', en: 'Labrador Retriever', ar: 'لابرادور', nl: 'Labrador retriever', spriteIndex: 16),
  VetDogBreed(code: 'golden_retriever', en: 'Golden Retriever', ar: 'جولدن ريتريفر', nl: 'Golden retriever', spriteIndex: 17),
  VetDogBreed(code: 'doberman', en: 'Doberman', ar: 'دوبرمان', nl: 'Dobermann', spriteIndex: 18),
  VetDogBreed(code: 'cane_corso', en: 'Cane Corso', ar: 'كاني كورسو', nl: 'Cane corso', spriteIndex: 19),
  VetDogBreed(code: 'pitbull_amstaff', en: 'Pit Bull / AmStaff', ar: 'بيتبول / أمستاف', nl: 'Pitbull / AmStaff', spriteIndex: 20),
  VetDogBreed(code: 'husky', en: 'Siberian Husky', ar: 'هاسكي', nl: 'Siberische husky', spriteIndex: 21),
  VetDogBreed(code: 'chihuahua', en: 'Chihuahua', ar: 'تشيواوا', nl: 'Chihuahua', spriteIndex: 22),
  VetDogBreed(code: 'mixed_other', en: 'Mixed / Other', ar: 'هجين / أخرى', nl: 'Kruising / anders', spriteIndex: 1),
];

List<VetAnimalSpecies> vetSpeciesForGroup(String group) => switch (group) {
  'livestock' => vetLivestockSpecies,
  'poultry' => vetBirdSpecies,
  'dogs' => const [vetDogSpecies],
  _ => const <VetAnimalSpecies>[],
};

VetAnimalSpecies? vetSpeciesByCode(String code) {
  final normalized = code.trim().toLowerCase();
  for (final s in [...vetLivestockSpecies, ...vetBirdSpecies, vetDogSpecies]) {
    if (s.code == normalized) return s;
  }
  return null;
}
''', encoding='utf-8')

text = APP.read_text(encoding='utf-8')

def replace_once(old: str, new: str, label: str):
    global text
    if old not in text:
        raise SystemExit(f'Missing expected block: {label}')
    text = text.replace(old, new, 1)

# State: track the selected dog breed separately from the species (species remains dog).
replace_once(
    "  late String group;\n  late String speciesCode;",
    "  late String group;\n  late String speciesCode;\n  late String dogBreedCode;",
    'scan state fields',
)

old_species_codes = r'''  List<String> _speciesCodesForGroup(String g) {
    if (g == 'dogs') return const ['dog'];
    final key = g == 'poultry' ? 'bird_species' : 'livestock_species';
    final configured = ((widget.farm[key] as List?) ?? const [])
        .map((e) => e.toString())
        .where((e) => e.isNotEmpty)
        .toList();
    if (configured.isNotEmpty) return configured;
    return vetSpeciesForGroup(g).map((e) => e.code).toList();
  }
'''
new_species_codes = r'''  List<String> _speciesCodesForGroup(String g) {
    if (g == 'dogs') return const ['dog'];
    final supported = vetSpeciesForGroup(g).map((e) => e.code).toSet();
    final key = g == 'poultry' ? 'bird_species' : 'livestock_species';
    final configured = ((widget.farm[key] as List?) ?? const [])
        .map((e) => e.toString())
        .where((e) => e.isNotEmpty && supported.contains(e))
        .toList();
    if (configured.isNotEmpty) return configured;
    return supported.toList();
  }

  List<VetDogBreed> get _availableDogBreeds {
    final configured = ((widget.farm['dog_breeds'] as List?) ?? const [])
        .map((e) => e.toString())
        .where((e) => e.isNotEmpty)
        .toSet();
    if (configured.isEmpty) return vetDogBreeds;
    final filtered = vetDogBreeds
        .where((breed) => configured.contains(breed.code))
        .toList();
    return filtered.isEmpty ? vetDogBreeds : filtered;
  }
'''
replace_once(old_species_codes, new_species_codes, 'supported species filtering')

old_init_tail = r'''    speciesCode = initialSpecies.isEmpty
        ? (group == 'dogs'
              ? 'dog'
              : group == 'poultry'
              ? 'chicken'
              : 'cattle')
        : initialSpecies.first;
  }
'''
new_init_tail = r'''    speciesCode = initialSpecies.isEmpty
        ? (group == 'dogs'
              ? 'dog'
              : group == 'poultry'
              ? 'chicken'
              : 'cattle')
        : initialSpecies.first;
    dogBreedCode = _availableDogBreeds.first.code;
  }
'''
replace_once(old_init_tail, new_init_tail, 'dog breed initialization')

replace_once(
    "      '|$group|$speciesCode|$language|${notes.text.trim().toLowerCase()}',",
    "      '|$group|$speciesCode|$dogBreedCode|$language|${notes.text.trim().toLowerCase()}',",
    'scan cache breed key',
)

replace_once(
    "        symptomNotes: notes.text,\n        animalGroup: group,",
    "        symptomNotes: group == 'dogs'\n            ? '[Dog breed: $dogBreedCode]\\n${notes.text}'\n            : notes.text,\n        animalGroup: group,",
    'breed context for analysis',
)

old_asset_fn = r'''  String asset(String g) => g == 'poultry'
      ? 'assets/icons/poultry_final.png'
      : g == 'dogs'
      ? 'assets/icons/dog_final.png'
      : 'assets/icons/livestock_final.png';
'''
new_asset_fn = r'''  int groupSpriteIndex(String g) => g == 'poultry'
      ? 2
      : g == 'dogs'
      ? 1
      : 0;
'''
replace_once(old_asset_fn, new_asset_fn, 'group sprite mapping')

# Group chips: use the approved multi-animal artwork.
replace_once(
    "                    avatar: SizedBox(\n                      width: 56,\n                      height: 42,\n                      child: Image.asset(asset(g), fit: BoxFit.contain),\n                    ),",
    "                    avatar: _AnimalSprite(\n                      index: groupSpriteIndex(g),\n                      size: 46,\n                      radius: 8,\n                    ),",
    'group choice artwork',
)

# Keep the selected group banner visible even when the farm has multiple groups.
old_banner = r'''        if (groups.length == 1)
          _AnimalGroupBanner(
            asset: asset(groups.first),
            title: label(groups.first),
            text: tr(
              context,
              'This is the animal group enabled for this farm.',
              'ده نوع الحيوان المفعّل للمزرعة دي.',
              'Dit is de diergroep die voor deze boerderij is ingeschakeld.',
            ),
          ),
        const SizedBox(height: 12),
        _SpeciesSingleSelect(
          title: group == 'livestock'
              ? tr(
                  context,
                  'Choose livestock type',
                  'اختار نوع المواشي',
                  'Kies veetype',
                )
              : group == 'poultry'
              ? tr(
                  context,
                  'Choose bird type',
                  'اختار نوع الطير',
                  'Kies vogeltype',
                )
              : tr(context, 'Animal type', 'نوع الحيوان', 'Diertype'),
          options: _currentSpeciesOptions,
          selectedCode: speciesCode,
          enabled: !busy,
          onChanged: (code) => setState(() {
            speciesCode = code;
            result = null;
          }),
        ),
'''
new_banner = r'''        if (groups.length > 1) const SizedBox(height: 12),
        _AnimalGroupBanner(
          spriteIndex: groupSpriteIndex(group),
          title: label(group),
          text: tr(
            context,
            'This is the animal group selected for this scan.',
            'ده قسم الحيوان المختار للفحص ده.',
            'Dit is de diergroep die voor deze scan is geselecteerd.',
          ),
        ),
        const SizedBox(height: 12),
        if (group == 'dogs')
          _DogBreedSingleSelect(
            title: tr(
              context,
              'Choose dog breed',
              'اختار نوع الكلب',
              'Kies hondenras',
            ),
            options: _availableDogBreeds,
            selectedCode: dogBreedCode,
            enabled: !busy,
            onChanged: (code) => setState(() {
              dogBreedCode = code;
              result = null;
            }),
          )
        else
          _SpeciesSingleSelect(
            title: group == 'livestock'
                ? tr(
                    context,
                    'Choose livestock type',
                    'اختار نوع المواشي',
                    'Kies veetype',
                  )
                : tr(
                    context,
                    'Choose bird type',
                    'اختار نوع الطير',
                    'Kies vogeltype',
                  ),
            options: _currentSpeciesOptions,
            selectedCode: speciesCode,
            enabled: !busy,
            onChanged: (code) => setState(() {
              speciesCode = code;
              result = null;
            }),
          ),
'''
replace_once(old_banner, new_banner, 'scan banner and subtype selector')

# When switching group, keep a valid approved dog breed.
replace_once(
    "                            result = null;\n                          }),",
    "                            if (g == 'dogs' &&\n                                !_availableDogBreeds.any(\n                                  (breed) => breed.code == dogBreedCode,\n                                )) {\n                              dogBreedCode = _availableDogBreeds.first.code;\n                            }\n                            result = null;\n                          }),",
    'group switch dog breed guard',
)

# Inject reusable sprite crop widget immediately before the group banner.
marker = 'class _AnimalGroupBanner extends StatelessWidget {'
if marker not in text:
    raise SystemExit('Animal group banner marker not found')
sprite_widget = r'''class _AnimalSprite extends StatelessWidget {
  const _AnimalSprite({
    required this.index,
    required this.size,
    this.radius = 10,
  });

  final int index;
  final double size;
  final double radius;

  @override
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
                'assets/icons/animal_sprite_v26.webp',
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
}

'''
text = text.replace(marker, sprite_widget + marker, 1)

# Group banner: large approved group picture.
banner_pattern = re.compile(r'class _AnimalGroupBanner extends StatelessWidget \{.*?\n\}\n\nclass _AnimalChoice', re.S)
new_group_banner = r'''class _AnimalGroupBanner extends StatelessWidget {
  const _AnimalGroupBanner({
    required this.spriteIndex,
    required this.title,
    required this.text,
  });
  final int spriteIndex;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(
      color: VetColors.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: VetColors.border),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _AnimalSprite(index: spriteIndex, size: 132, radius: 14),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 7),
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
text, n = banner_pattern.subn(new_group_banner, text, count=1)
if n != 1:
    raise SystemExit(f'Group banner replacement count: {n}')

# Onboarding animal group cards: use the approved group images rather than old section assets.
old_choice_image = r'''          SizedBox(
            width: 112,
            height: 82,
            child: ClipRect(
              child: Center(
                child: Transform.scale(
                  scale: 1.2,
                  child: Image.asset(
                    asset,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    isAntiAlias: true,
                  ),
                ),
              ),
            ),
          ),'''
new_choice_image = r'''          _AnimalSprite(
            index: group == 'poultry'
                ? 2
                : group == 'dogs'
                ? 1
                : 0,
            size: 86,
            radius: 12,
          ),'''
replace_once(old_choice_image, new_choice_image, 'onboarding group artwork')

# Dashboard animal count cards: derive approved group picture from the old asset string.
old_count_image = r'''          SizedBox(
            width: double.infinity,
            height: 174,
            child: ClipRect(
              child: Center(
                child: Transform.scale(
                  scale: 1.0,
                  child: Image.asset(
                    asset,
                    width: 300,
                    height: 168,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    isAntiAlias: true,
                  ),
                ),
              ),
            ),
          ),'''
new_count_image = r'''          Center(
            child: _AnimalSprite(
              index: asset.contains('poultry')
                  ? 2
                  : asset.contains('dog')
                  ? 1
                  : 0,
              size: 164,
              radius: 14,
            ),
          ),'''
replace_once(old_count_image, new_count_image, 'dashboard group artwork')

# Multi-select species: use each animal's real approved artwork.
replace_once(
    "              avatar: Text(item.emoji, style: const TextStyle(fontSize: 23)),",
    "              avatar: _AnimalSprite(\n                index: item.spriteIndex,\n                size: 34,\n                radius: 7,\n              ),",
    'species multiselect artwork',
)

# Group multiselect tuple uses sprite indices instead of emoji.
replace_once(
    "    final groups = <(String, String, String, String, String)>[\n      ('livestock', 'Livestock', 'المواشي', 'Vee', '🐄'),\n      ('poultry', 'Birds', 'الطيور', 'Vogels', '🐔'),\n      ('dogs', 'Dogs', 'الكلاب', 'Honden', '🐕'),\n    ];",
    "    final groups = <(String, String, String, String, int)>[\n      ('livestock', 'Livestock', 'المواشي', 'Vee', 0),\n      ('poultry', 'Birds', 'الطيور', 'Vogels', 2),\n      ('dogs', 'Dogs', 'الكلاب', 'Honden', 1),\n    ];",
    'group multiselect data',
)
replace_once(
    "                avatar: Text(g.$5, style: const TextStyle(fontSize: 24)),",
    "                avatar: _AnimalSprite(index: g.$5, size: 34, radius: 7),",
    'group multiselect artwork',
)

# Dog breed multiselect: each breed now has its own approved image.
replace_once(
    "                avatar: const Text('🐕', style: TextStyle(fontSize: 21)),",
    "                avatar: _AnimalSprite(\n                  index: breed.spriteIndex,\n                  size: 34,\n                  radius: 7,\n                ),",
    'dog breed multiselect artwork',
)

# Replace the species single selector at the end with sprite-driven selector + dog breed selector.
species_pattern = re.compile(r'class _SpeciesSingleSelect extends StatelessWidget \{.*\}\s*\Z', re.S)
new_selectors = r'''class _SpeciesSingleSelect extends StatelessWidget {
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
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
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
                labelPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                avatar: _AnimalSprite(index: item.spriteIndex, size: 48, radius: 9),
                label: Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: active ? FontWeight.w900 : FontWeight.w700,
                  ),
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

class _DogBreedSingleSelect extends StatelessWidget {
  const _DogBreedSingleSelect({
    required this.title,
    required this.options,
    required this.selectedCode,
    required this.enabled,
    required this.onChanged,
  });

  final String title;
  final List<VetDogBreed> options;
  final String selectedCode;
  final bool enabled;
  final ValueChanged<String> onChanged;

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
              const Icon(Icons.pets_rounded, color: VetColors.blue, size: 31),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          Wrap(
            spacing: 9,
            runSpacing: 9,
            children: options.map((breed) {
              final label = locale == 'ar'
                  ? breed.ar
                  : locale == 'nl'
                  ? breed.nl
                  : breed.en;
              final active = selectedCode == breed.code;
              return ChoiceChip(
                labelPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                avatar: _AnimalSprite(index: breed.spriteIndex, size: 48, radius: 9),
                label: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: active ? FontWeight.w900 : FontWeight.w700,
                  ),
                ),
                selected: active,
                selectedColor: VetColors.primary.withValues(alpha: .22),
                backgroundColor: Colors.white,
                side: BorderSide(
                  color: active ? VetColors.primary : VetColors.border,
                  width: active ? 2.2 : 1,
                ),
                onSelected: enabled ? (_) => onChanged(breed.code) : null,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
'''
text, n = species_pattern.subn(new_selectors, text, count=1)
if n != 1:
    raise SystemExit(f'Species selector replacement count: {n}')

APP.write_text(text, encoding='utf-8')

pub = PUB.read_text(encoding='utf-8')
if 'version: 0.6.25+37' not in pub:
    raise SystemExit('Expected version 0.6.25+37 was not found')
pub = pub.replace('version: 0.6.25+37', 'version: 0.6.26+38', 1)
PUB.write_text(pub, encoding='utf-8')

print('Vet AI 0.6.26 approved animal artwork patch applied')
