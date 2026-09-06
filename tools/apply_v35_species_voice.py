from pathlib import Path
import re


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        if new in text:
            return text
        raise SystemExit(f"V35 patch marker missing: {label}")
    return text.replace(old, new, 1)


def inject_after(text: str, needle: str, addition: str, label: str, start: int = 0) -> str:
    i = text.find(needle, start)
    if i < 0:
        if addition.strip() in text:
            return text
        raise SystemExit(f"V35 injection marker missing: {label}")
    j = i + len(needle)
    return text[:j] + addition + text[j:]


# ---------- v5_app.dart ----------
p = Path('lib/v5_app.dart')
s = p.read_text(encoding='utf-8')
s = replace_once(
    s,
    "import 'monitoring/sensor_alert_rules.dart';\nimport 'legal/vet_legal_pages.dart';",
    "import 'monitoring/sensor_alert_rules.dart';\nimport 'models/animal_taxonomy.dart';\nimport 'legal/vet_legal_pages.dart';",
    'taxonomy import',
)
s = replace_once(
    s,
    "  final selectedGroups = <String>{'livestock'};\n\n  final company",
    "  final selectedGroups = <String>{'livestock'};\n  final selectedLivestockSpecies = <String>{'cattle'};\n  final selectedBirdSpecies = <String>{'chicken'};\n\n  final company",
    'onboarding species sets',
)
# Capture the farm id so subtype profile can be saved transactionally after onboarding RPC.
s = replace_once(s, "      await VetBackend.instance.createFarm(\n        FarmSetupPayload(", "      final createdFarmId = await VetBackend.instance.createFarm(\n        FarmSetupPayload(", 'capture created farm')
onb = s.index('final createdFarmId = await VetBackend.instance.createFarm')
end_call = s.find("      );\n      if (!mounted) return;", onb)
if end_call < 0:
    raise SystemExit('V35 onboarding createFarm closing marker missing')
insert = "      );\n      await VetBackend.instance.saveFarmAnimalProfile(\n        createdFarmId,\n        livestockSpecies: selectedGroups.contains('livestock') ? selectedLivestockSpecies : <String>{},\n        birdSpecies: selectedGroups.contains('poultry') ? selectedBirdSpecies : <String>{},\n        dogEnabled: selectedGroups.contains('dogs'),\n      );\n"
s = s[:end_call] + insert + s[end_call + len("      );\n"):]
# Use Birds wording in user-facing labels while preserving database group key `poultry`.
s = s.replace("tr(context, 'Poultry', 'الدواجن', 'Pluimvee')", "tr(context, 'Birds', 'الطيور', 'Vogels')")
s = s.replace("tr(context, 'Poultry count', 'عدد الدواجن', 'Aantal pluimvee')", "tr(context, 'Bird count', 'عدد الطيور', 'Aantal vogels')")
# Insert subtype multi-selects in onboarding after the group cards.
dog_marker = "        onTap: () => _toggleGroup('dogs'),\n      ),\n      const SizedBox(height: 18),"
dog_repl = "        onTap: () => _toggleGroup('dogs'),\n      ),\n      const SizedBox(height: 14),\n      if (selectedGroups.contains('livestock')) ...[\n        _SpeciesMultiSelect(\n          title: tr(context, 'Livestock types', 'أنواع المواشي', 'Veetypen'),\n          options: vetLivestockSpecies,\n          selected: selectedLivestockSpecies,\n          onChanged: (next) => setState(() { selectedLivestockSpecies..clear()..addAll(next); }),\n        ),\n        const SizedBox(height: 12),\n      ],\n      if (selectedGroups.contains('poultry')) ...[\n        _SpeciesMultiSelect(\n          title: tr(context, 'Bird types', 'أنواع الطيور', 'Vogeltypen'),\n          options: vetBirdSpecies,\n          selected: selectedBirdSpecies,\n          onChanged: (next) => setState(() { selectedBirdSpecies..clear()..addAll(next); }),\n        ),\n        const SizedBox(height: 12),\n      ],\n      const SizedBox(height: 6),"
s = replace_once(s, dog_marker, dog_repl, 'onboarding subtype selector')

# Profile species state and persistence.
s = replace_once(
    s,
    "  Map<String, dynamic>? profile;\n  late final Map<String, TextEditingController> c;",
    "  Map<String, dynamic>? profile;\n  late final Map<String, TextEditingController> c;\n  late final Set<String> profileLivestockSpecies;\n  late final Set<String> profileBirdSpecies;",
    'profile species state',
)
profile_start = s.index('class _V5ProfileScreenState')
farm_marker = "    final f = widget.farm;\n"
pos = s.find(farm_marker, profile_start)
if pos < 0:
    raise SystemExit('V35 profile farm marker missing')
profile_init = "    final f = widget.farm;\n    profileLivestockSpecies = ((f['livestock_species'] as List?) ?? const []).map((e) => e.toString()).where((e) => e.isNotEmpty).toSet();\n    profileBirdSpecies = ((f['bird_species'] as List?) ?? const []).map((e) => e.toString()).where((e) => e.isNotEmpty).toSet();\n    if (profileLivestockSpecies.isEmpty && ((f['livestock_count'] as num?)?.toInt() ?? 0) > 0) profileLivestockSpecies.add('cattle');\n    if (profileBirdSpecies.isEmpty && ((f['poultry_count'] as num?)?.toInt() ?? 0) > 0) profileBirdSpecies.add('chicken');\n"
s = s[:pos] + profile_init + s[pos + len(farm_marker):]
# Persist species profile after the farm edit.
update_idx = s.index('      await VetBackend.instance.updateFarm(', profile_start)
profile_close = s.find("      );\n      if (mounted)", update_idx)
if profile_close < 0:
    raise SystemExit('V35 profile updateFarm closing marker missing')
profile_save = "      );\n      await VetBackend.instance.saveFarmAnimalProfile(\n        widget.farm['id'] as String,\n        livestockSpecies: _i('livestock_count') > 0 ? profileLivestockSpecies : <String>{},\n        birdSpecies: _i('poultry_count') > 0 ? profileBirdSpecies : <String>{},\n        dogEnabled: _i('dog_count') > 0,\n      );\n"
s = s[:profile_close] + profile_save + s[profile_close + len("      );\n"):]
# Put editable subtype controls before the generic farm fields.
profile_loop = "          for (final spec in <(String, String, IconData)>["
profile_loop_idx = s.find(profile_loop, profile_start)
if profile_loop_idx < 0:
    raise SystemExit('V35 profile field loop missing')
profile_widgets = "          _SpeciesMultiSelect(\n            title: tr(context, 'Livestock types used by AI', 'أنواع المواشي المستخدمة في الفحص', 'Veetypen voor AI'),\n            options: vetLivestockSpecies,\n            selected: profileLivestockSpecies,\n            onChanged: (next) => setState(() { profileLivestockSpecies..clear()..addAll(next); }),\n          ),\n          const SizedBox(height: 12),\n          _SpeciesMultiSelect(\n            title: tr(context, 'Bird types used by AI', 'أنواع الطيور المستخدمة في الفحص', 'Vogeltypen voor AI'),\n            options: vetBirdSpecies,\n            selected: profileBirdSpecies,\n            onChanged: (next) => setState(() { profileBirdSpecies..clear()..addAll(next); }),\n          ),\n          const SizedBox(height: 16),\n"
s = s[:profile_loop_idx] + profile_widgets + s[profile_loop_idx:]

# Scan panel: selected species is mandatory and becomes part of cache + assessment.
scan_start = s.index('class _V5ScanPanelState')
s = s[:scan_start] + s[scan_start:].replace("  late String group;\n", "  late String group;\n  late String speciesCode;\n", 1)
groups_marker = "  List<String> get groups => [\n    if (((widget.farm['livestock_count'] as num?)?.toInt() ?? 0) > 0)\n      'livestock',\n    if (((widget.farm['poultry_count'] as num?)?.toInt() ?? 0) > 0) 'poultry',\n    if (((widget.farm['dog_count'] as num?)?.toInt() ?? 0) > 0) 'dogs',\n  ];\n"
groups_add = groups_marker + "\n  List<String> _speciesCodesForGroup(String g) {\n    if (g == 'dogs') return const ['dog'];\n    final key = g == 'poultry' ? 'bird_species' : 'livestock_species';\n    final configured = ((widget.farm[key] as List?) ?? const []).map((e) => e.toString()).where((e) => e.isNotEmpty).toList();\n    if (configured.isNotEmpty) return configured;\n    return vetSpeciesForGroup(g).map((e) => e.code).toList();\n  }\n\n  List<VetAnimalSpecies> get _currentSpeciesOptions {\n    final allowed = _speciesCodesForGroup(group).toSet();\n    return vetSpeciesForGroup(group).where((e) => allowed.contains(e.code)).toList();\n  }\n"
s = replace_once(s, groups_marker, groups_add, 'scan species getters')
s = replace_once(
    s,
    "    group = groups.isEmpty ? 'livestock' : groups.first;\n  }",
    "    group = groups.isEmpty ? 'livestock' : groups.first;\n    final initialSpecies = _speciesCodesForGroup(group);\n    speciesCode = initialSpecies.isEmpty ? (group == 'dogs' ? 'dog' : group == 'poultry' ? 'chicken' : 'cattle') : initialSpecies.first;\n  }",
    'scan species init',
)
s = s.replace("      '|$group|$language|${notes.text.trim().toLowerCase()}',", "      '|$group|$speciesCode|$language|${notes.text.trim().toLowerCase()}',")
s = s.replace("return 'vet_ai_exact_scan_v2_$digest';", "return 'vet_ai_exact_scan_v3_$digest';")
# Pass subtype into the draft row itself.
create_marker = "        symptomNotes: notes.text,\n        animalGroup: group,\n      );"
create_repl = "        symptomNotes: notes.text,\n        animalGroup: group,\n        speciesCode: speciesCode,\n        birdType: group == 'poultry' ? speciesCode : null,\n      );"
scan_segment = s[scan_start:]
if create_marker not in scan_segment:
    raise SystemExit('V35 createDraftAssessment marker missing')
scan_segment = scan_segment.replace(create_marker, create_repl, 1)
s = s[:scan_start] + scan_segment
# Group change also resets species + cached visible result.
old_choice = "                    onSelected: busy ? null : (_) => setState(() => group = g),"
new_choice = "                    onSelected: busy ? null : (_) => setState(() {\n                      group = g;\n                      final choices = _speciesCodesForGroup(g);\n                      speciesCode = choices.isEmpty ? (g == 'dogs' ? 'dog' : g == 'poultry' ? 'chicken' : 'cattle') : choices.first;\n                      result = null;\n                    }),"
s = replace_once(s, old_choice, new_choice, 'scan group change')
# Insert a required single-species selector immediately before image card.
scan_marker_idx = s.index("        if (groups.length == 1)", scan_start)
space_idx = s.find("        const SizedBox(height: 16),", scan_marker_idx)
if space_idx < 0:
    raise SystemExit('V35 scan species UI insertion marker missing')
selector = "        const SizedBox(height: 12),\n        _SpeciesSingleSelect(\n          title: group == 'livestock'\n              ? tr(context, 'Choose livestock type', 'اختار نوع المواشي', 'Kies veetype')\n              : group == 'poultry'\n              ? tr(context, 'Choose bird type', 'اختار نوع الطير', 'Kies vogeltype')\n              : tr(context, 'Animal type', 'نوع الحيوان', 'Diertype'),\n          options: _currentSpeciesOptions,\n          selectedCode: speciesCode,\n          enabled: !busy,\n          onChanged: (code) => setState(() { speciesCode = code; result = null; }),\n        ),\n"
s = s[:space_idx] + selector + s[space_idx:]
# History shows exact species.
s = s.replace("title: Text('${a['animal_group'] ?? ''} • ${a['risk'] ?? ''}'),", "title: Text('${a['species_code'] ?? a['animal_group'] ?? ''} • ${a['risk'] ?? ''}'),")

# Add reusable selectors if not already present.
if 'class _SpeciesMultiSelect extends StatelessWidget' not in s:
    s += r'''

class _SpeciesMultiSelect extends StatelessWidget {
  const _SpeciesMultiSelect({required this.title, required this.options, required this.selected, required this.onChanged});
  final String title;
  final List<VetAnimalSpecies> options;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: VetColors.surface2, borderRadius: BorderRadius.circular(17), border: Border.all(color: VetColors.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15.5)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: options.map((item) {
              final active = selected.contains(item.code);
              final locale = Localizations.localeOf(context).languageCode;
              final label = locale == 'ar' ? item.ar : locale == 'nl' ? item.nl : item.en;
              return FilterChip(
                avatar: Icon(item.icon, size: 19),
                label: Text(label),
                selected: active,
                onSelected: (_) {
                  final next = Set<String>.from(selected);
                  if (active) {
                    if (next.length > 1) next.remove(item.code);
                  } else {
                    next.add(item.code);
                  }
                  onChanged(next);
                },
              );
            }).toList(),
          ),
        ]),
      );
}

class _SpeciesSingleSelect extends StatelessWidget {
  const _SpeciesSingleSelect({required this.title, required this.options, required this.selectedCode, required this.enabled, required this.onChanged});
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
      decoration: BoxDecoration(color: VetColors.softBlue, borderRadius: BorderRadius.circular(17), border: Border.all(color: VetColors.blue.withValues(alpha: .2))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [const Icon(Icons.pets_outlined, color: VetColors.blue), const SizedBox(width: 8), Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15.5))]),
        const SizedBox(height: 9),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: options.map((item) {
            final label = locale == 'ar' ? item.ar : locale == 'nl' ? item.nl : item.en;
            return ChoiceChip(
              avatar: Icon(item.icon, size: 19),
              label: Text(label),
              selected: selectedCode == item.code,
              onSelected: enabled ? (_) => onChanged(item.code) : null,
            );
          }).toList(),
        ),
      ]),
    );
  }
}
'''
p.write_text(s, encoding='utf-8')

# ---------- vet_backend.dart ----------
p = Path('lib/services/vet_backend.dart')
s = p.read_text(encoding='utf-8')
s = replace_once(
    s,
    "    String symptomNotes = '',\n    String animalGroup = 'livestock',\n  }) async {",
    "    String symptomNotes = '',\n    String animalGroup = 'livestock',\n    required String speciesCode,\n    String? birdType,\n  }) async {",
    'draft species signature',
)
s = replace_once(
    s,
    "          'animal_group': animalGroup,\n          'risk': 'insufficient_data',",
    "          'animal_group': animalGroup,\n          'species_code': speciesCode,\n          'bird_type': birdType,\n          'risk': 'insufficient_data',",
    'draft species insert',
)
p.write_text(s, encoding='utf-8')

# ---------- vet_case_workflow.dart telemetry ----------
p = Path('lib/services/vet_case_workflow.dart')
s = p.read_text(encoding='utf-8')
s = replace_once(s, "import 'vet_backend.dart';", "import 'vet_backend.dart';\nimport 'vet_operations.dart';", 'voice telemetry import')
voice_start = "    final clean = text.trim();\n    if (clean.isEmpty) return null;"
voice_repl = "    final clean = text.trim();\n    if (clean.isEmpty) return null;\n    await logVoiceClientEvent(stage: 'start', route: 'voice_v35', appVersion: '0.6.21', projectRef: SupabaseConfig.projectRef);"
s = replace_once(s, voice_start, voice_repl, 'voice start telemetry')
# Direct response telemetry before status handling.
direct_marker = "        if (response.statusCode < 200 || response.statusCode >= 300) {\n          return null;\n        }"
direct_repl = "        await logVoiceClientEvent(stage: 'direct_response', route: 'http', httpStatus: response.statusCode, detail: 'bytes=${raw.length}', appVersion: '0.6.21', projectRef: SupabaseConfig.projectRef);\n        if (response.statusCode < 200 || response.statusCode >= 300) {\n          return null;\n        }"
s = replace_once(s, direct_marker, direct_repl, 'direct response telemetry')
# Replace first direct catch in requestDirect with exception logging.
s = replace_once(
    s,
    "      } catch (_) {\n        return null;\n      } finally {\n        httpClient.close(force: true);",
    "      } catch (e) {\n        await logVoiceClientEvent(stage: 'direct_exception', route: 'http', detail: e.toString(), appVersion: '0.6.21', projectRef: SupabaseConfig.projectRef);\n        return null;\n      } finally {\n        httpClient.close(force: true);",
    'direct exception telemetry',
)
# SDK telemetry.
s = replace_once(
    s,
    "        return _decodeVoicePayload(response.data);\n      } catch (_) {\n        return null;\n      }",
    "        final decoded = _decodeVoicePayload(response.data);\n        await logVoiceClientEvent(stage: decoded == null ? 'sdk_decode_empty' : 'sdk_success', route: 'sdk', detail: decoded == null ? 'No decodable audio payload' : 'audio_bytes=${decoded.length}', appVersion: '0.6.21', projectRef: SupabaseConfig.projectRef);\n        return decoded;\n      } catch (e) {\n        await logVoiceClientEvent(stage: 'sdk_exception', route: 'sdk', detail: e.toString(), appVersion: '0.6.21', projectRef: SupabaseConfig.projectRef);\n        return null;\n      }",
    'sdk telemetry',
)
s = replace_once(s, "    if (session == null) return null;\n\n    // Route 1", "    if (session == null) {\n      await logVoiceClientEvent(stage: 'no_session', route: 'auth', appVersion: '0.6.21', projectRef: SupabaseConfig.projectRef);\n      return null;\n    }\n\n    // Route 1", 'voice no session telemetry')
p.write_text(s, encoding='utf-8')

# ---------- report audio-player telemetry ----------
p = Path('lib/analysis/vet_analysis_report.dart')
s = p.read_text(encoding='utf-8')
s = replace_once(s, "import '../services/vet_case_workflow.dart';", "import '../services/vet_case_workflow.dart';\nimport '../services/vet_operations.dart';", 'report telemetry import')
play_marker = "          await _audio.play(BytesSource(natural));\n          return;"
play_repl = "          await VetBackend.instance.logVoiceClientEvent(stage: 'audio_player_start', route: 'audioplayers', detail: 'audio_bytes=${natural.length}', appVersion: '0.6.21');\n          await _audio.play(BytesSource(natural));\n          await VetBackend.instance.logVoiceClientEvent(stage: 'audio_player_started', route: 'audioplayers', appVersion: '0.6.21');\n          return;"
s = replace_once(s, play_marker, play_repl, 'audio player telemetry')
p.write_text(s, encoding='utf-8')

# ---------- analyze-case species authority ----------
p = Path('supabase/functions/analyze-case/index.ts')
s = p.read_text(encoding='utf-8')
s = replace_once(s, 'select("id,farm_id,media_path,symptom_notes,animal_group")', 'select("id,farm_id,media_path,symptom_notes,animal_group,species_code,bird_type")', 'analysis assessment species select')
s = replace_once(
    s,
    '  const animalGroup=assessment.animal_group??"livestock";\n',
    '  const animalGroup=assessment.animal_group??"livestock";const selectedSpecies=clean(assessment.species_code||assessment.bird_type);if(!selectedSpecies)return fail("SPECIES_REQUIRED",ar?"اختار نوع الحيوان قبل التحليل.":"Select the animal species before analysis.",400);\n',
    'selected species requirement',
)
s = replace_once(
    s,
    '  const diseases=allDiseases.filter((d:any)=>Array.isArray(d.animal_groups)&&d.animal_groups.includes(animalGroup));',
    '  const diseases=allDiseases.filter((d:any)=>Array.isArray(d.animal_groups)&&d.animal_groups.includes(animalGroup)&&speciesScopeMatches(d.species_scope,selectedSpecies));',
    'pre-model species catalog filter',
)
s = replace_once(
    s,
    'Selected animal group: ${animalGroup}\\nSymptoms/history:',
    'Selected animal group: ${animalGroup}\\nUSER-SELECTED SPECIES (authoritative): ${selectedSpecies}\\nSymptoms/history:',
    'analysis species prompt',
)
s = replace_once(
    s,
    'SPECIES RULE: species_scope is binding. Never return a disease whose species_scope excludes the observed species.',
    'SPECIES RULE: species_scope is binding. The user-selected species is authoritative for catalog filtering. Use species_observed only to detect a possible image/selection mismatch; never silently switch species. Never return a disease whose species_scope excludes the user-selected species.',
    'analysis species safety prompt',
)
s = replace_once(
    s,
    'const species=clean(m.species_observed);const small=smallRuminant(species);',
    'const speciesObserved=clean(m.species_observed);const species=selectedSpecies;const small=smallRuminant(species);',
    'analysis deterministic selected species',
)
s = s.replace('speciesScopeMatches(d.species_scope,species)', 'speciesScopeMatches(d.species_scope,selectedSpecies)')
s = replace_once(
    s,
    'assessment_id:assessmentId,animal_group:animalGroup,group_match:groupMatch,',
    'assessment_id:assessmentId,animal_group:animalGroup,selected_species:selectedSpecies,group_match:groupMatch,',
    'analysis result selected species',
)
s = replace_once(s, 'species_observed:species,lesion_morphology:', 'species_observed:speciesObserved,lesion_morphology:', 'analysis observed species output')
p.write_text(s, encoding='utf-8')

# ---------- finalize report species authority ----------
p = Path('supabase/functions/finalize-case-report/index.ts')
s = p.read_text(encoding='utf-8')
s = replace_once(s, 'select("id,farm_id,animal_group,symptom_notes,ai_analysis,ai_usage,risk,status,differential_diagnoses,observed_signs")', 'select("id,farm_id,animal_group,species_code,bird_type,symptom_notes,ai_analysis,ai_usage,risk,status,differential_diagnoses,observed_signs")', 'final assessment species select')
s = replace_once(
    s,
    '  const cleanAnswers:Array<{question:string;answer:string}>=[];',
    '  const selectedSpecies=clean(a.species_code||a.bird_type||a.ai_analysis?.selected_species||a.ai_analysis?.species_observed);if(!selectedSpecies)return json({code:"SPECIES_REQUIRED",risk:"insufficient_data",message:isAr(language)?"اختار نوع الحيوان قبل التقرير النهائي.":"Select the animal species before the final report."},400);\n  const cleanAnswers:Array<{question:string;answer:string}>=[];',
    'final selected species',
)
s = replace_once(
    s,
    'const initial=guardTriage(rawInitial,Array.isArray(a.differential_diagnoses)?a.differential_diagnoses:[],language,cleanAnswers);',
    'const initial=guardTriage({...rawInitial,species_observed:selectedSpecies},Array.isArray(a.differential_diagnoses)?a.differential_diagnoses:[],language,cleanAnswers);',
    'final guard selected species',
)
s = s.replace('speciesScopeMatches(x.species_scope,clean(initial.species_observed))', 'speciesScopeMatches(x.species_scope,selectedSpecies)')
s = replace_once(s, 'Animal group: ${a.animal_group??"unknown"}\\\nSymptoms/history:', 'Animal group: ${a.animal_group??"unknown"}\\\nUser-selected species: ${selectedSpecies}\\\nSymptoms/history:', 'final model species prompt')
p.write_text(s, encoding='utf-8')

# ---------- version ----------
p = Path('pubspec.yaml')
s = p.read_text(encoding='utf-8')
s = re.sub(r'^version:\s*[^\n]+', 'version: 0.6.21+33', s, count=1, flags=re.M)
p.write_text(s, encoding='utf-8')

print('V35 species, diagnosis, voice telemetry source patch applied')
