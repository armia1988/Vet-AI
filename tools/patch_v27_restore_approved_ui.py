from pathlib import Path
import base64
import hashlib

ROOT = Path('.')
APP = ROOT / 'lib/v5_app.dart'
PUBSPEC = ROOT / 'pubspec.yaml'
SPRITE = ROOT / 'assets/icons/animal_sprite_v26.webp'
PARTS = ROOT / 'tools/v27_sprite_parts'


def replace_class(text: str, class_name: str, next_class: str | None, replacement: str) -> str:
    start_marker = f'class {class_name}'
    start = text.find(start_marker)
    if start < 0:
        raise SystemExit(f'Missing class marker: {start_marker}')
    if next_class is None:
        end = len(text)
    else:
        next_marker = f'class {next_class}'
        end = text.find(next_marker, start)
        if end < 0:
            raise SystemExit(f'Missing next class marker: {next_marker}')
    return text[:start] + replacement.rstrip() + '\n\n' + text[end:]


# Restore the approved second animal-artwork set as one valid packaged WEBP.
encoded = ''.join(p.read_text(encoding='utf-8').strip() for p in sorted(PARTS.glob('part*.txt')))
if not encoded:
    raise SystemExit('Approved artwork parts are missing')
data = base64.b64decode(encoded, validate=True)
if len(data) != 42714:
    raise SystemExit(f'Unexpected repaired sprite size: {len(data)}')
if data[:4] != b'RIFF' or data[8:12] != b'WEBP':
    raise SystemExit('Repaired approved sprite is not a valid WEBP container')
if hashlib.sha256(data).hexdigest() != '082c3fe780b86489e0a2fcd3d2fc6d61e73d3b3dae2a2e73fc299c1c9d2303c0':
    raise SystemExit('Approved sprite checksum mismatch')
SPRITE.write_bytes(data)

app = APP.read_text(encoding='utf-8')

# Make the main scan banner visibly image-led.
app = app.replace(
    '_AnimalSprite(index: spriteIndex, size: 132, radius: 14)',
    '_AnimalSprite(index: spriteIndex, size: 142, radius: 16)',
    1,
)

helpers = r'''class _ProfileHeroCard extends StatelessWidget {
  const _ProfileHeroCard({
    required this.name,
    required this.email,
    required this.farmName,
  });

  final String name;
  final String email;
  final String farmName;

  @override
  Widget build(BuildContext context) {
    final displayName = name.trim().isEmpty
        ? tr(context, 'My profile', 'ملفي الشخصي', 'Mijn profiel')
        : name.trim();
    final displayFarm = farmName.trim().isEmpty
        ? tr(context, 'Farm profile', 'ملف المزرعة', 'Boerderijprofiel')
        : farmName.trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [
            VetColors.surface3,
            VetColors.softBlue.withValues(alpha: .72),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: VetColors.primary.withValues(alpha: .22)),
      ),
      child: Row(
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .92),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: VetColors.primary.withValues(alpha: .20)),
            ),
            child: const Icon(
              Icons.account_circle_rounded,
              size: 53,
              color: VetColors.primary,
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  displayFarm,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: VetColors.primary,
                  ),
                ),
                if (email.trim().isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: VetColors.muted,
                      fontSize: 13.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Icon(Icons.edit_outlined, color: VetColors.muted, size: 24),
        ],
      ),
    );
  }
}

class _AnimalVisualTile extends StatelessWidget {
  const _AnimalVisualTile({
    required this.spriteIndex,
    required this.label,
    required this.selected,
    required this.onTap,
    this.enabled = true,
    this.imageSize = 86,
  });

  final int spriteIndex;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool enabled;
  final double imageSize;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: enabled ? 1 : .55,
    child: InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.fromLTRB(9, 10, 9, 11),
        decoration: BoxDecoration(
          color: selected
              ? VetColors.primary.withValues(alpha: .10)
              : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? VetColors.primary : VetColors.border,
            width: selected ? 2.2 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: VetColors.primary.withValues(alpha: .08),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : const [],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                _AnimalSprite(
                  index: spriteIndex,
                  size: imageSize,
                  radius: 13,
                ),
                PositionedDirectional(
                  top: -3,
                  end: -3,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 120),
                    opacity: selected ? 1 : 0,
                    child: Container(
                      width: 27,
                      height: 27,
                      decoration: const BoxDecoration(
                        color: VetColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        size: 19,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14.5,
                height: 1.15,
                fontWeight: selected ? FontWeight.w900 : FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _AnimalGroupVisualCard extends StatelessWidget {
  const _AnimalGroupVisualCard({
    required this.spriteIndex,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final int spriteIndex;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(20),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: selected
            ? VetColors.primary.withValues(alpha: .10)
            : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected ? VetColors.primary : VetColors.border,
          width: selected ? 2.2 : 1,
        ),
      ),
      child: Row(
        children: [
          _AnimalSprite(index: spriteIndex, size: 104, radius: 14),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: VetColors.muted,
                    fontSize: 12.5,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            selected ? Icons.check_circle_rounded : Icons.circle_outlined,
            size: 30,
            color: selected ? VetColors.primary : VetColors.muted,
          ),
        ],
      ),
    ),
  );
}

'''

if 'class _AnimalVisualTile extends StatelessWidget' not in app:
    marker = 'class _SpeciesMultiSelect extends StatelessWidget {'
    pos = app.find(marker)
    if pos < 0:
        raise SystemExit('Species selector insertion marker missing')
    app = app[:pos] + helpers + app[pos:]

species_multi = r'''class _SpeciesMultiSelect extends StatelessWidget {
  const _SpeciesMultiSelect({
    required this.title,
    required this.options,
    required this.selected,
    required this.onChanged,
  });
  final String title;
  final List<VetAnimalSpecies> options;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: VetColors.surface2,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: VetColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16.5),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 560 ? 3 : 2;
              const gap = 10.0;
              final width =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: options.map((item) {
                  final active = selected.contains(item.code);
                  final label = locale == 'ar'
                      ? item.ar
                      : locale == 'nl'
                      ? item.nl
                      : item.en;
                  return SizedBox(
                    width: width,
                    child: _AnimalVisualTile(
                      spriteIndex: item.spriteIndex,
                      label: label,
                      selected: active,
                      onTap: () {
                        final next = Set<String>.from(selected);
                        if (active) {
                          if (next.length > 1) next.remove(item.code);
                        } else {
                          next.add(item.code);
                        }
                        onChanged(next);
                      },
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}'''

group_multi = r'''class _AnimalGroupMultiSelect extends StatelessWidget {
  const _AnimalGroupMultiSelect({
    required this.selected,
    required this.onToggle,
  });
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final groups = <(String, String, String, String, int, String, String, String)>[
      (
        'livestock',
        'Livestock',
        'المواشي',
        'Vee',
        0,
        'Cattle, buffalo, sheep, goats and horses',
        'أبقار وجاموس وأغنام وماعز وأحصنة',
        'Runderen, buffels, schapen, geiten en paarden',
      ),
      (
        'poultry',
        'Birds',
        'الطيور',
        'Vogels',
        2,
        'Chickens, chicks, ducks, turkeys and geese',
        'فراخ وكتاكيت وبط وديك رومي وأوز',
        'Kippen, kuikens, eenden, kalkoenen en ganzen',
      ),
      (
        'dogs',
        'Dogs',
        'الكلاب',
        'Honden',
        1,
        'Dog breeds used by the farm',
        'سلالات الكلاب الموجودة بالمزرعة',
        'Hondenrassen op de boerderij',
      ),
    ];
    final locale = Localizations.localeOf(context).languageCode;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: VetColors.softBlue,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: VetColors.blue.withValues(alpha: .28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(context, 'Animal sections', 'أقسام الحيوانات', 'Diercategorieën'),
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < groups.length; i++) ...[
            _AnimalGroupVisualCard(
              spriteIndex: groups[i].$5,
              title: locale == 'ar'
                  ? groups[i].$3
                  : locale == 'nl'
                  ? groups[i].$4
                  : groups[i].$2,
              subtitle: locale == 'ar'
                  ? groups[i].$7
                  : locale == 'nl'
                  ? groups[i].$8
                  : groups[i].$6,
              selected: selected.contains(groups[i].$1),
              onTap: () => onToggle(groups[i].$1),
            ),
            if (i != groups.length - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}'''

dog_multi = r'''class _DogBreedMultiSelect extends StatelessWidget {
  const _DogBreedMultiSelect({
    required this.title,
    required this.selected,
    required this.onChanged,
  });
  final String title;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: VetColors.surface2,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: VetColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16.5),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 560 ? 3 : 2;
              const gap = 10.0;
              final width =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: vetDogBreeds.map((breed) {
                  final active = selected.contains(breed.code);
                  final label = locale == 'ar'
                      ? breed.ar
                      : locale == 'nl'
                      ? breed.nl
                      : breed.en;
                  return SizedBox(
                    width: width,
                    child: _AnimalVisualTile(
                      spriteIndex: breed.spriteIndex,
                      label: label,
                      selected: active,
                      imageSize: 88,
                      onTap: () {
                        final next = Set<String>.from(selected);
                        active ? next.remove(breed.code) : next.add(breed.code);
                        onChanged(next);
                      },
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}'''

species_single = r'''class _SpeciesSingleSelect extends StatelessWidget {
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
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: VetColors.blue.withValues(alpha: .24)),
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
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = options.length == 1
                  ? 1
                  : constraints.maxWidth >= 560
                  ? 3
                  : 2;
              const gap = 10.0;
              final width =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: options.map((item) {
                  final label = locale == 'ar'
                      ? item.ar
                      : locale == 'nl'
                      ? item.nl
                      : item.en;
                  return SizedBox(
                    width: width,
                    child: _AnimalVisualTile(
                      spriteIndex: item.spriteIndex,
                      label: label,
                      selected: selectedCode == item.code,
                      enabled: enabled,
                      imageSize: options.length == 1 ? 102 : 88,
                      onTap: () => onChanged(item.code),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}'''

dog_single = r'''class _DogBreedSingleSelect extends StatelessWidget {
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
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: VetColors.blue.withValues(alpha: .24)),
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
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = options.length == 1
                  ? 1
                  : constraints.maxWidth >= 560
                  ? 3
                  : 2;
              const gap = 10.0;
              final width =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: options.map((breed) {
                  final label = locale == 'ar'
                      ? breed.ar
                      : locale == 'nl'
                      ? breed.nl
                      : breed.en;
                  return SizedBox(
                    width: width,
                    child: _AnimalVisualTile(
                      spriteIndex: breed.spriteIndex,
                      label: label,
                      selected: selectedCode == breed.code,
                      enabled: enabled,
                      imageSize: options.length == 1 ? 102 : 88,
                      onTap: () => onChanged(breed.code),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}'''

app = replace_class(app, '_SpeciesMultiSelect extends StatelessWidget {', '_AnimalGroupMultiSelect extends StatelessWidget {', species_multi)
app = replace_class(app, '_AnimalGroupMultiSelect extends StatelessWidget {', '_DogBreedMultiSelect extends StatelessWidget {', group_multi)
app = replace_class(app, '_DogBreedMultiSelect extends StatelessWidget {', '_SpeciesSingleSelect extends StatelessWidget {', dog_multi)
app = replace_class(app, '_SpeciesSingleSelect extends StatelessWidget {', '_DogBreedSingleSelect extends StatelessWidget {', species_single)
app = replace_class(app, '_DogBreedSingleSelect extends StatelessWidget {', None, dog_single)

# Restore a proper profile header without changing any saving/business logic.
profile_start = app.find('class V5ProfileScreen extends StatefulWidget')
if profile_start < 0:
    raise SystemExit('Profile screen marker missing')
profile_prefix = '''        children: [\n          _StepTitle(\n            icon: Icons.account_circle_outlined,'''
pos = app.find(profile_prefix, profile_start)
if pos < 0:
    raise SystemExit('Profile personal-details marker missing')
replacement_prefix = '''        children: [\n          _ProfileHeroCard(\n            name: c['full_name']!.text,\n            email: VetBackend.instance.currentUser?.email ?? '',\n            farmName: c['farm_name']!.text,\n          ),\n          const SizedBox(height: 18),\n          _StepTitle(\n            icon: Icons.account_circle_outlined,'''
app = app[:pos] + replacement_prefix + app[pos + len(profile_prefix):]

# Guard against accidentally reverting to the old tiny-chip visual selectors.
for marker in (
    'class _AnimalVisualTile extends StatelessWidget',
    'class _AnimalGroupVisualCard extends StatelessWidget',
    '_ProfileHeroCard(',
    "'assets/icons/animal_sprite_v26.webp'",
):
    if marker not in app:
        raise SystemExit(f'UI restoration marker missing: {marker}')

APP.write_text(app, encoding='utf-8')

pubspec = PUBSPEC.read_text(encoding='utf-8')
if 'version: 0.6.26+38' not in pubspec:
    raise SystemExit('Expected 0.6.26 version marker missing')
pubspec = pubspec.replace('version: 0.6.26+38', 'version: 0.6.27+39', 1)
PUBSPEC.write_text(pubspec, encoding='utf-8')

print('Vet AI 0.6.27 approved animal images + image-led selectors + profile header restored')
