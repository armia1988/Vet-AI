from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected 1 match, found {count}')
    return text.replace(old, new, 1)

v5_path = Path('lib/v5_app.dart')
v5 = v5_path.read_text(encoding='utf-8')

v5 = replace_once(v5, "import 'dart:convert';\n", "import 'dart:async';\nimport 'dart:convert';\n", 'dart async import')
v5 = replace_once(v5, "import 'services/vet_operations.dart';\n", "import 'services/vet_operations.dart';\nimport 'services/alert_notification_service.dart';\n", 'notification import')

v5 = replace_once(
    v5,
    "  final selectedBirdSpecies = <String>{'chicken'};\n",
    "  final selectedBirdSpecies = <String>{'chicken'};\n  final selectedDogBreeds = <String>{};\n",
    'onboarding dog breeds state',
)

v5 = replace_once(
    v5,
    "        dogEnabled: selectedGroups.contains('dogs'),\n      );",
    "        dogEnabled: selectedGroups.contains('dogs'),\n        dogBreeds: selectedGroups.contains('dogs') ? selectedDogBreeds : <String>{},\n      );",
    'onboarding save dog breeds',
)

onboard_bird = """      if (selectedGroups.contains('poultry')) ...[
        _SpeciesMultiSelect(
          title: tr(context, 'Bird types', 'أنواع الطيور', 'Vogeltypen'),
          options: vetBirdSpecies,
          selected: selectedBirdSpecies,
          onChanged: (next) => setState(() { selectedBirdSpecies..clear()..addAll(next); }),
        ),
        const SizedBox(height: 12),
      ],
      const SizedBox(height: 6),
"""
onboard_dogs = onboard_bird.replace(
    "      const SizedBox(height: 6),\n",
    """      if (selectedGroups.contains('dogs')) ...[
        _DogBreedMultiSelect(
          title: tr(context, 'Dog breeds', 'سلالات الكلاب', 'Hondenrassen'),
          selected: selectedDogBreeds,
          onChanged: (next) => setState(() { selectedDogBreeds..clear()..addAll(next); }),
        ),
        const SizedBox(height: 12),
      ],
      const SizedBox(height: 6),
""",
)
v5 = replace_once(v5, onboard_bird, onboard_dogs, 'onboarding dog breed selector')

# Dashboard: listen to real alert rows and surface a native phone notification with sound.
dash_old = """class _V5DashboardState extends State<V5Dashboard> {
  int index = 0;
  late Map<String, dynamic> farm;

  @override
  void initState() {
    super.initState();
    farm = Map<String, dynamic>.from(widget.initialFarm);
  }
"""
dash_new = """class _V5DashboardState extends State<V5Dashboard> {
  int index = 0;
  late Map<String, dynamic> farm;
  StreamSubscription<List<Map<String, dynamic>>>? _alertSubscription;
  late final DateTime _alertListeningSince;
  String? _lastNotifiedAlertId;

  @override
  void initState() {
    super.initState();
    farm = Map<String, dynamic>.from(widget.initialFarm);
    _alertListeningSince = DateTime.now().toUtc();
    final farmId = farm['id']?.toString();
    if (farmId != null && farmId.isNotEmpty) {
      _alertSubscription = VetBackend.instance.alertsStream(farmId).listen(_handleAlertRows);
    }
  }

  void _handleAlertRows(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return;
    final row = rows.first;
    final id = row['id']?.toString();
    if (id == null || id.isEmpty || id == _lastNotifiedAlertId) return;
    final created = DateTime.tryParse(row['created_at']?.toString() ?? '');
    if (created == null || created.toUtc().isBefore(_alertListeningSince)) {
      _lastNotifiedAlertId = id;
      return;
    }
    _lastNotifiedAlertId = id;
    final title = row['title']?.toString().trim();
    final details = row['details']?.toString().trim();
    final threshold = row['threshold_text']?.toString().trim();
    VetAlertNotificationService.instance.showSensorAlert(
      alertId: id,
      title: (title == null || title.isEmpty) ? 'Vet AI sensor alert' : title,
      body: (details != null && details.isNotEmpty)
          ? details
          : ((threshold != null && threshold.isNotEmpty) ? threshold : 'A real sensor threshold was crossed.'),
      payload: id,
    );
  }

  @override
  void dispose() {
    _alertSubscription?.cancel();
    super.dispose();
  }
"""
v5 = replace_once(v5, dash_old, dash_new, 'dashboard notification subscription')

# Profile state: animal groups and dog breeds are real, editable state.
profile_state_old = """  late final Map<String, TextEditingController> c;
  late final Set<String> profileLivestockSpecies;
  late final Set<String> profileBirdSpecies;

  @override
  void initState() {
    super.initState();
    final f = widget.farm;
    profileLivestockSpecies = ((f['livestock_species'] as List?) ?? const []).map((e) => e.toString()).where((e) => e.isNotEmpty).toSet();
    profileBirdSpecies = ((f['bird_species'] as List?) ?? const []).map((e) => e.toString()).where((e) => e.isNotEmpty).toSet();
    if (profileLivestockSpecies.isEmpty && ((f['livestock_count'] as num?)?.toInt() ?? 0) > 0) profileLivestockSpecies.add('cattle');
    if (profileBirdSpecies.isEmpty && ((f['poultry_count'] as num?)?.toInt() ?? 0) > 0) profileBirdSpecies.add('chicken');
"""
profile_state_new = """  late final Map<String, TextEditingController> c;
  late final Set<String> profileSelectedGroups;
  late final Set<String> profileLivestockSpecies;
  late final Set<String> profileBirdSpecies;
  late final Set<String> profileDogBreeds;

  @override
  void initState() {
    super.initState();
    final f = widget.farm;
    profileLivestockSpecies = ((f['livestock_species'] as List?) ?? const []).map((e) => e.toString()).where((e) => e.isNotEmpty).toSet();
    profileBirdSpecies = ((f['bird_species'] as List?) ?? const []).map((e) => e.toString()).where((e) => e.isNotEmpty).toSet();
    profileDogBreeds = ((f['dog_breeds'] as List?) ?? const []).map((e) => e.toString()).where((e) => e.isNotEmpty).toSet();
    final livestockCount = ((f['livestock_count'] as num?)?.toInt() ?? 0);
    final birdCount = ((f['poultry_count'] as num?)?.toInt() ?? 0);
    final dogCount = ((f['dog_count'] as num?)?.toInt() ?? 0);
    profileSelectedGroups = <String>{
      if (livestockCount > 0 || profileLivestockSpecies.isNotEmpty) 'livestock',
      if (birdCount > 0 || profileBirdSpecies.isNotEmpty) 'poultry',
      if (dogCount > 0 || f['dog_enabled'] == true) 'dogs',
    };
    if (profileSelectedGroups.isEmpty) profileSelectedGroups.add('livestock');
    if (profileLivestockSpecies.isEmpty && livestockCount > 0) profileLivestockSpecies.add('cattle');
    if (profileBirdSpecies.isEmpty && birdCount > 0) profileBirdSpecies.add('chicken');
"""
v5 = replace_once(v5, profile_state_old, profile_state_new, 'profile group state')

# Helper toggles profile groups and keeps counts real.
helper_anchor = """  double _d(String key) =>
      double.tryParse(c[key]!.text.trim().replaceAll(',', '.')) ?? 0;

  Future<void> save() async {
"""
helper_new = """  double _d(String key) =>
      double.tryParse(c[key]!.text.trim().replaceAll(',', '.')) ?? 0;

  void _toggleProfileGroup(String group) {
    setState(() {
      if (profileSelectedGroups.contains(group)) {
        if (profileSelectedGroups.length <= 1) return;
        profileSelectedGroups.remove(group);
        if (group == 'livestock') {
          c['livestock_count']!.text = '0';
          profileLivestockSpecies.clear();
        } else if (group == 'poultry') {
          c['poultry_count']!.text = '0';
          profileBirdSpecies.clear();
        } else if (group == 'dogs') {
          c['dog_count']!.text = '0';
          profileDogBreeds.clear();
        }
      } else {
        profileSelectedGroups.add(group);
        if (group == 'livestock') {
          if (_i('livestock_count') == 0) c['livestock_count']!.text = '1';
          if (profileLivestockSpecies.isEmpty) profileLivestockSpecies.add('cattle');
        } else if (group == 'poultry') {
          if (_i('poultry_count') == 0) c['poultry_count']!.text = '1';
          if (profileBirdSpecies.isEmpty) profileBirdSpecies.add('chicken');
        } else if (group == 'dogs') {
          if (_i('dog_count') == 0) c['dog_count']!.text = '1';
        }
      }
    });
  }

  Future<void> save() async {
"""
v5 = replace_once(v5, helper_anchor, helper_new, 'profile group toggle')

save_old = """      await VetBackend.instance.updateFarm(
        widget.farm['id'] as String,
        companyName: c['company_name']!.text,
        farmName: c['farm_name']!.text,
        country: c['country']!.text,
        region: c['region']!.text,
        workerCount: _i('worker_count'),
        veterinarianCount: _i('veterinarian_count'),
        barnCount: _i('barn_count', 1),
        totalIndoorAreaM2: _d('area'),
        livestockCount: _i('livestock_count'),
        poultryCount: _i('poultry_count'),
        dogCount: _i('dog_count'),
        breeds: c['breeds']!.text,
        ageRange: c['age_range']!.text,
        productionPurpose: c['production_purpose']!.text,
        ventilationSystem: c['ventilation_system']!.text,
        vaccinationNotes: c['vaccination_notes']!.text,
        diseaseHistory: c['disease_history']!.text,
      );
      await VetBackend.instance.saveFarmAnimalProfile(
        widget.farm['id'] as String,
        livestockSpecies: _i('livestock_count') > 0 ? profileLivestockSpecies : <String>{},
        birdSpecies: _i('poultry_count') > 0 ? profileBirdSpecies : <String>{},
        dogEnabled: _i('dog_count') > 0,
      );
"""
save_new = """      final updatedFarm = await VetBackend.instance.updateFarm(
        widget.farm['id'] as String,
        companyName: c['company_name']!.text,
        farmName: c['farm_name']!.text,
        country: c['country']!.text,
        region: c['region']!.text,
        workerCount: _i('worker_count'),
        veterinarianCount: _i('veterinarian_count'),
        barnCount: _i('barn_count', 1),
        totalIndoorAreaM2: _d('area'),
        livestockCount: profileSelectedGroups.contains('livestock') ? (_i('livestock_count') == 0 ? 1 : _i('livestock_count')) : 0,
        poultryCount: profileSelectedGroups.contains('poultry') ? (_i('poultry_count') == 0 ? 1 : _i('poultry_count')) : 0,
        dogCount: profileSelectedGroups.contains('dogs') ? (_i('dog_count') == 0 ? 1 : _i('dog_count')) : 0,
        breeds: c['breeds']!.text,
        ageRange: c['age_range']!.text,
        productionPurpose: c['production_purpose']!.text,
        ventilationSystem: c['ventilation_system']!.text,
        vaccinationNotes: c['vaccination_notes']!.text,
        diseaseHistory: c['disease_history']!.text,
      );
      await VetBackend.instance.saveFarmAnimalProfile(
        widget.farm['id'] as String,
        livestockSpecies: profileSelectedGroups.contains('livestock') ? profileLivestockSpecies : <String>{},
        birdSpecies: profileSelectedGroups.contains('poultry') ? profileBirdSpecies : <String>{},
        dogEnabled: profileSelectedGroups.contains('dogs'),
        dogBreeds: profileSelectedGroups.contains('dogs') ? profileDogBreeds : <String>{},
      );
      widget.farm
        ..addAll(updatedFarm)
        ..['livestock_species'] = profileSelectedGroups.contains('livestock') ? (profileLivestockSpecies.toList()..sort()) : <String>[]
        ..['bird_species'] = profileSelectedGroups.contains('poultry') ? (profileBirdSpecies.toList()..sort()) : <String>[]
        ..['dog_enabled'] = profileSelectedGroups.contains('dogs')
        ..['dog_breeds'] = profileSelectedGroups.contains('dogs') ? (profileDogBreeds.toList()..sort()) : <String>[];
"""
v5 = replace_once(v5, save_old, save_new, 'profile real save')

v5 = replace_once(
    v5,
    """    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(
                context,
                'Could not save the profile.',
                'تعذر حفظ الملف.',
                'Profiel kon niet worden opgeslagen.',
              ),
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
""",
    """    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${tr(context, 'Could not save the profile', 'تعذر حفظ الملف', 'Profiel kon niet worden opgeslagen')}: ${e.toString()}',
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
""",
    'profile detailed error',
)

profile_ui_old = """          const SizedBox(height: 16),
          _SpeciesMultiSelect(
            title: tr(context, 'Livestock types used by AI', 'أنواع المواشي المستخدمة في الفحص', 'Veetypen voor AI'),
            options: vetLivestockSpecies,
            selected: profileLivestockSpecies,
            onChanged: (next) => setState(() { profileLivestockSpecies..clear()..addAll(next); }),
          ),
          const SizedBox(height: 12),
          _SpeciesMultiSelect(
            title: tr(context, 'Bird types used by AI', 'أنواع الطيور المستخدمة في الفحص', 'Vogeltypen voor AI'),
            options: vetBirdSpecies,
            selected: profileBirdSpecies,
            onChanged: (next) => setState(() { profileBirdSpecies..clear()..addAll(next); }),
          ),
          const SizedBox(height: 16),
"""
profile_ui_new = """          const SizedBox(height: 16),
          _AnimalGroupMultiSelect(
            selected: profileSelectedGroups,
            onToggle: _toggleProfileGroup,
          ),
          const SizedBox(height: 14),
          if (profileSelectedGroups.contains('livestock')) ...[
            _SpeciesMultiSelect(
              title: tr(context, 'Livestock types used by AI', 'أنواع المواشي المستخدمة في الفحص', 'Veetypen voor AI'),
              options: vetLivestockSpecies,
              selected: profileLivestockSpecies,
              onChanged: (next) => setState(() { profileLivestockSpecies..clear()..addAll(next); }),
            ),
            const SizedBox(height: 10),
            _Field(controller: c['livestock_count']!, label: tr(context, 'Livestock count', 'عدد المواشي', 'Aantal vee'), icon: Icons.pets_rounded, keyboard: TextInputType.number),
            const SizedBox(height: 12),
          ],
          if (profileSelectedGroups.contains('poultry')) ...[
            _SpeciesMultiSelect(
              title: tr(context, 'Bird types used by AI', 'أنواع الطيور المستخدمة في الفحص', 'Vogeltypen voor AI'),
              options: vetBirdSpecies,
              selected: profileBirdSpecies,
              onChanged: (next) => setState(() { profileBirdSpecies..clear()..addAll(next); }),
            ),
            const SizedBox(height: 10),
            _Field(controller: c['poultry_count']!, label: tr(context, 'Bird count', 'عدد الطيور', 'Aantal vogels'), icon: Icons.egg_alt_rounded, keyboard: TextInputType.number),
            const SizedBox(height: 12),
          ],
          if (profileSelectedGroups.contains('dogs')) ...[
            _DogBreedMultiSelect(
              title: tr(context, 'Dog breeds', 'سلالات الكلاب', 'Hondenrassen'),
              selected: profileDogBreeds,
              onChanged: (next) => setState(() { profileDogBreeds..clear()..addAll(next); }),
            ),
            const SizedBox(height: 10),
            _Field(controller: c['dog_count']!, label: tr(context, 'Dog count', 'عدد الكلاب', 'Aantal honden'), icon: Icons.pets_rounded, keyboard: TextInputType.number),
            const SizedBox(height: 12),
          ],
"""
v5 = replace_once(v5, profile_ui_old, profile_ui_new, 'profile conditional animal ui')

# Remove the always-visible animal count fields from the general farm field list.
for chunk in [
"""            (
              'livestock_count',
              tr(context, 'Livestock', 'المواشي', 'Vee'),
              Icons.pets_outlined,
            ),
""",
"""            (
              'poultry_count',
              tr(context, 'Birds', 'الطيور', 'Vogels'),
              Icons.egg_alt_outlined,
            ),
""",
"""            (
              'dog_count',
              tr(context, 'Dogs', 'الكلاب', 'Honden'),
              Icons.pets_rounded,
            ),
""",
]:
    v5 = replace_once(v5, chunk, '', f'remove generic count {chunk.split(chr(39))[1]}')

# Clearer species choices and real animal visuals.
species_chip_old = """              return FilterChip(
                avatar: Icon(item.icon, size: 19),
                label: Text(label),
                selected: active,
                onSelected: (_) {
"""
species_chip_new = """              return FilterChip(
                avatar: Text(item.emoji, style: const TextStyle(fontSize: 23)),
                label: Text(label, style: TextStyle(fontWeight: active ? FontWeight.w900 : FontWeight.w700, color: VetColors.text)),
                selected: active,
                selectedColor: VetColors.primary.withValues(alpha: .22),
                backgroundColor: Colors.white,
                checkmarkColor: VetColors.primary,
                showCheckmark: true,
                side: BorderSide(color: active ? VetColors.primary : VetColors.border, width: active ? 2.2 : 1),
                elevation: active ? 2 : 0,
                onSelected: (_) {
"""
v5 = replace_once(v5, species_chip_old, species_chip_new, 'species multi clearer chip')

single_old = """            return ChoiceChip(
              avatar: Icon(item.icon, size: 19),
              label: Text(label),
              selected: selectedCode == item.code,
              onSelected: enabled ? (_) => onChanged(item.code) : null,
            );
"""
single_new = """            final active = selectedCode == item.code;
            return ChoiceChip(
              avatar: Text(item.emoji, style: const TextStyle(fontSize: 23)),
              label: Text(label, style: TextStyle(fontWeight: active ? FontWeight.w900 : FontWeight.w700)),
              selected: active,
              selectedColor: VetColors.primary.withValues(alpha: .22),
              backgroundColor: Colors.white,
              side: BorderSide(color: active ? VetColors.primary : VetColors.border, width: active ? 2.2 : 1),
              onSelected: enabled ? (_) => onChanged(item.code) : null,
            );
"""
v5 = replace_once(v5, single_old, single_new, 'species single clearer chip')

# Add reusable group + dog breed selectors before single-select.
insert_anchor = "\nclass _SpeciesSingleSelect extends StatelessWidget {\n"
new_widgets = r'''
class _AnimalGroupMultiSelect extends StatelessWidget {
  const _AnimalGroupMultiSelect({required this.selected, required this.onToggle});
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final groups = <(String, String, String, String, String)>[
      ('livestock', 'Livestock', 'المواشي', 'Vee', '🐄'),
      ('poultry', 'Birds', 'الطيور', 'Vogels', '🐔'),
      ('dogs', 'Dogs', 'الكلاب', 'Honden', '🐕'),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: VetColors.softBlue,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: VetColors.blue.withValues(alpha: .28)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr(context, 'Animal sections', 'أقسام الحيوانات', 'Diercategorieën'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 9,
          runSpacing: 9,
          children: groups.map((g) {
            final active = selected.contains(g.$1);
            final locale = Localizations.localeOf(context).languageCode;
            final label = locale == 'ar' ? g.$3 : locale == 'nl' ? g.$4 : g.$2;
            return FilterChip(
              avatar: Text(g.$5, style: const TextStyle(fontSize: 24)),
              label: Text(label, style: TextStyle(fontWeight: active ? FontWeight.w900 : FontWeight.w700)),
              selected: active,
              selectedColor: VetColors.primary.withValues(alpha: .25),
              backgroundColor: Colors.white,
              checkmarkColor: VetColors.primary,
              side: BorderSide(color: active ? VetColors.primary : VetColors.border, width: active ? 2.4 : 1),
              elevation: active ? 2 : 0,
              onSelected: (_) => onToggle(g.$1),
            );
          }).toList(),
        ),
      ]),
    );
  }
}

class _DogBreedMultiSelect extends StatelessWidget {
  const _DogBreedMultiSelect({required this.title, required this.selected, required this.onChanged});
  final String title;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: VetColors.surface2, borderRadius: BorderRadius.circular(17), border: Border.all(color: VetColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15.5)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: vetDogBreeds.map((breed) {
            final active = selected.contains(breed.code);
            final label = locale == 'ar' ? breed.ar : locale == 'nl' ? breed.nl : breed.en;
            return FilterChip(
              avatar: const Text('🐕', style: TextStyle(fontSize: 21)),
              label: Text(label, style: TextStyle(fontWeight: active ? FontWeight.w900 : FontWeight.w700)),
              selected: active,
              selectedColor: VetColors.primary.withValues(alpha: .22),
              backgroundColor: Colors.white,
              checkmarkColor: VetColors.primary,
              side: BorderSide(color: active ? VetColors.primary : VetColors.border, width: active ? 2.2 : 1),
              onSelected: (_) {
                final next = Set<String>.from(selected);
                active ? next.remove(breed.code) : next.add(breed.code);
                onChanged(next);
              },
            );
          }).toList(),
        ),
      ]),
    );
  }
}
'''
v5 = replace_once(v5, insert_anchor, '\n' + new_widgets + insert_anchor, 'group and dog breed widgets')

v5_path.write_text(v5, encoding='utf-8')

# Alert editor: every metric gets BOTH real lower and upper thresholds.
alert_path = Path('lib/monitoring/sensor_alert_rules.dart')
alerts = alert_path.read_text(encoding='utf-8')
alerts = alerts.replace("mode: 'below_min'", "mode: 'outside_range'")
alerts = alerts.replace("mode: 'above_max'", "mode: 'outside_range'")

card_old = """    final threshold = switch (s.mode) {
      'below_min' => '${_rt(context, 'Alert below', 'إنذار أقل من', 'Waarschuw onder')} ${min ?? '—'} $unit',
      'above_max' => '${_rt(context, 'Alert above', 'إنذار أعلى من', 'Waarschuw boven')} ${max ?? '—'} $unit',
      _ => '${min ?? '—'} – ${max ?? '—'} $unit',
    };
"""
card_new = """    final threshold = '${_rt(context, 'Must not fall below', 'لا يقل عن', 'Niet lager dan')} ${min ?? '—'} $unit • ${_rt(context, 'Must not exceed', 'لا يزيد عن', 'Niet hoger dan')} ${max ?? '—'} $unit';
"""
alerts = replace_once(alerts, card_old, card_new, 'alert card min max')

save_old_alert = """  void _save() {
    final lo = _n(min.text), hi = _n(max.text);
    if ((s.mode == 'below_min' && lo == null) || (s.mode == 'above_max' && hi == null) || (s.mode == 'outside_range' && (lo == null || hi == null))) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_rt(context, 'Enter the required threshold for this sensor.', 'اكتب الحد المطلوب للحساس ده.', 'Vul de vereiste drempel voor deze sensor in.'))));
      return;
    }
    if (s.mode == 'outside_range' && lo! >= hi!) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_rt(context, 'Minimum must be lower than maximum.', 'الحد الأدنى لازم يكون أقل من الأعلى.', 'Minimum moet lager zijn dan maximum.'))));
      return;
    }
    final cool = int.tryParse(cooldown.text.trim()) ?? 30;
    Navigator.pop(context, _RuleDraft(metric, s.mode == 'above_max' ? null : lo, s.mode == 'below_min' ? null : hi, severity, label.text.trim(), cool.clamp(1, 1440), enabled));
  }
"""
save_new_alert = """  void _save() {
    final lo = _n(min.text), hi = _n(max.text);
    if (lo == null || hi == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_rt(context, 'Enter both the minimum and maximum thresholds.', 'اكتب الحدين: لا يقل عن ولا يزيد عن.', 'Vul zowel de minimum- als maximumgrens in.'))));
      return;
    }
    if (lo >= hi) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_rt(context, 'Minimum must be lower than maximum.', 'قيمة لا يقل عن لازم تكون أقل من قيمة لا يزيد عن.', 'Minimum moet lager zijn dan maximum.'))));
      return;
    }
    final cool = int.tryParse(cooldown.text.trim()) ?? 30;
    Navigator.pop(context, _RuleDraft(metric, lo, hi, severity, label.text.trim(), cool.clamp(1, 1440), enabled));
  }
"""
alerts = replace_once(alerts, save_old_alert, save_new_alert, 'alert save requires both')

fields_old = """            if (s.mode == 'below_min') _thresholdField(min, 'Alert when below', 'إنذار عندما تقل عن', 'Waarschuw wanneer lager dan'),
            if (s.mode == 'above_max') _thresholdField(max, 'Alert when above', 'إنذار عندما تزيد عن', 'Waarschuw wanneer hoger dan'),
            if (s.mode == 'outside_range') Row(children: [Expanded(child: _thresholdField(min, 'Minimum', 'الحد الأدنى', 'Minimum')), const SizedBox(width: 10), Expanded(child: _thresholdField(max, 'Maximum', 'الحد الأعلى', 'Maximum'))]),
"""
fields_new = """            Row(children: [
              Expanded(child: _thresholdField(min, 'Must not fall below', 'لا يقل عن', 'Niet lager dan')),
              const SizedBox(width: 10),
              Expanded(child: _thresholdField(max, 'Must not exceed', 'لا يزيد عن', 'Niet hoger dan')),
            ]),
"""
alerts = replace_once(alerts, fields_old, fields_new, 'alert two fields')
alert_path.write_text(alerts, encoding='utf-8')

print('V36 source patch applied')
