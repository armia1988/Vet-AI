from pathlib import Path

backend_path = Path('lib/services/vet_backend.dart')
app_path = Path('lib/v5_app.dart')
backend = backend_path.read_text(encoding='utf-8')
app = app_path.read_text(encoding='utf-8')

# Backend: allow diagnostic assessments to be explicitly linked to an animal.
if 'String? animalId,' not in backend[backend.find('Future<String> createDraftAssessment'):backend.find('Future<Map<String, dynamic>> analyzeAssessment')]:
    anchor = """  Future<String> createDraftAssessment({
    required String farmId,
    required String mediaPath,
"""
    replacement = """  Future<String> createDraftAssessment({
    required String farmId,
    required String mediaPath,
    String? animalId,
"""
    if anchor not in backend:
        raise SystemExit('V101b backend createDraftAssessment anchor not found')
    backend = backend.replace(anchor, replacement, 1)

assessment_start = backend.find('Future<String> createDraftAssessment')
assessment_end = backend.find('Future<Map<String, dynamic>> analyzeAssessment', assessment_start)
assessment_section = backend[assessment_start:assessment_end]
if "if (animalId != null) 'animal_id': animalId," not in assessment_section:
    anchor = """          'farm_id': farmId,
          'created_by': user.id,
          'media_path': mediaPath,
"""
    replacement = """          'farm_id': farmId,
          'created_by': user.id,
          if (animalId != null) 'animal_id': animalId,
          'media_path': mediaPath,
"""
    if anchor not in backend:
        raise SystemExit('V101b backend insert anchor not found')
    backend = backend.replace(anchor, replacement, 1)

# Scan panel state.
scan_class = app.find('class _V5ScanPanelState extends State<V5ScanPanel>')
if scan_class < 0:
    raise SystemExit('V101b scan panel class not found')

field_anchor = """  Map<String, dynamic>? result;
  String? assessmentId;
  late String group;
"""
if 'List<Map<String, dynamic>> scanAnimals = const [];' not in app[scan_class:]:
    replacement = """  Map<String, dynamic>? result;
  String? assessmentId;
  List<Map<String, dynamic>> scanAnimals = const [];
  String? selectedAnimalId;
  late String group;
"""
    if field_anchor not in app[scan_class:]:
        raise SystemExit('V101b scan field anchor not found')
    local = app[scan_class:]
    local = local.replace(field_anchor, replacement, 1)
    app = app[:scan_class] + local

# Load the available animals once when the scan panel starts.
init_anchor = """    dogBreedCode = _availableDogBreeds.first.code;
  }

  @override
  void dispose() {
"""
if 'unawaited(_loadScanAnimals());' not in app[scan_class:]:
    replacement = """    dogBreedCode = _availableDogBreeds.first.code;
    unawaited(_loadScanAnimals());
  }

  Future<void> _loadScanAnimals() async {
    try {
      final farmId = '${widget.farm['id'] ?? ''}';
      if (farmId.isEmpty) return;
      final rows = await Supabase.instance.client
          .from('animals')
          .select('id,animal_group,external_id,name,species')
          .eq('farm_id', farmId)
          .eq('active', true)
          .order('created_at', ascending: false);
      if (!mounted) return;
      setState(() {
        scanAnimals = rows
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      });
    } catch (_) {
      // Individual animal selection is optional; scanning still works without it.
    }
  }

  List<Map<String, dynamic>> get _scanAnimalsForGroup => scanAnimals
      .where((animal) => '${animal['animal_group'] ?? ''}' == group)
      .toList();

  String _scanAnimalLabel(Map<String, dynamic> animal) {
    final name = '${animal['name'] ?? ''}'.trim();
    final tag = '${animal['external_id'] ?? ''}'.trim();
    final species = '${animal['species'] ?? ''}'.trim();
    if (name.isNotEmpty && tag.isNotEmpty) return '$name · $tag';
    if (name.isNotEmpty) return name;
    if (tag.isNotEmpty) return tag;
    if (species.isNotEmpty) return species;
    return tr(context, 'Animal', 'حيوان', 'Dier');
  }

  @override
  void dispose() {
"""
    if init_anchor not in app[scan_class:]:
        raise SystemExit('V101b scan init anchor not found')
    local = app[scan_class:]
    local = local.replace(init_anchor, replacement, 1)
    app = app[:scan_class] + local

# Add optional individual animal selector immediately after species selection.
scan_class = app.find('class _V5ScanPanelState extends State<V5ScanPanel>')
section = app[scan_class:]
if "'Link to animal (recommended)'" not in section:
    species_marker = 'options: _currentSpeciesOptions,'
    species_pos = section.find(species_marker)
    if species_pos < 0:
        raise SystemExit('V101b species selector marker not found')
    insert_anchor = "        const SizedBox(height: 16),\n        Container("
    insert_pos = section.find(insert_anchor, species_pos)
    if insert_pos < 0:
        raise SystemExit('V101b post-species insertion anchor not found')
    animal_selector = """        if (_scanAnimalsForGroup.isNotEmpty) ...[
          const SizedBox(height: 14),
          DropdownButtonFormField<String?>(
            value: _scanAnimalsForGroup.any(
              (animal) => '${animal['id']}' == selectedAnimalId,
            )
                ? selectedAnimalId
                : null,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: tr(
                context,
                'Link to animal (recommended)',
                'اربط الفحص بالحيوان (موصى به)',
                'Koppel aan dier (aanbevolen)',
              ),
              helperText: tr(
                context,
                'Enables the 12 / 24 / 48 hour AI follow-up timeline.',
                'يفعّل متابعة AI بعد 12 / 24 / 48 ساعة.',
                'Activeert de AI-follow-up na 12 / 24 / 48 uur.',
              ),
            ),
            items: [
              DropdownMenuItem<String?>(
                value: null,
                child: Text(
                  tr(context, 'No individual animal', 'بدون حيوان محدد', 'Geen individueel dier'),
                ),
              ),
              ..._scanAnimalsForGroup.map(
                (animal) => DropdownMenuItem<String?>(
                  value: '${animal['id']}',
                  child: Text(
                    _scanAnimalLabel(animal),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
            onChanged: busy
                ? null
                : (value) => setState(() {
                    selectedAnimalId = value;
                    result = null;
                  }),
          ),
        ],
"""
    section = section[:insert_pos] + animal_selector + section[insert_pos:]
    app = app[:scan_class] + section

# Pass the selected animal into the assessment.
scan_class = app.find('class _V5ScanPanelState extends State<V5ScanPanel>')
section = app[scan_class:]
if 'animalId: selectedAnimalId,' not in section:
    anchor = """      final newAssessmentId = await VetBackend.instance.createDraftAssessment(
        farmId: farmId,
        mediaPath: path,
"""
    replacement = """      final newAssessmentId = await VetBackend.instance.createDraftAssessment(
        farmId: farmId,
        mediaPath: path,
        animalId: selectedAnimalId,
"""
    if anchor not in section:
        raise SystemExit('V101b assessment call anchor not found')
    section = section.replace(anchor, replacement, 1)
    app = app[:scan_class] + section

for marker in [
    'List<Map<String, dynamic>> scanAnimals = const [];',
    'Future<void> _loadScanAnimals() async',
    "'Link to animal (recommended)'",
    'animalId: selectedAnimalId,',
]:
    if marker not in app:
        raise SystemExit(f'V101b app marker missing: {marker}')

assessment_start = backend.find('Future<String> createDraftAssessment')
assessment_end = backend.find('Future<Map<String, dynamic>> analyzeAssessment', assessment_start)
assessment_section = backend[assessment_start:assessment_end]
for marker in ['String? animalId,', "if (animalId != null) 'animal_id': animalId,"]:
    if marker not in assessment_section:
        raise SystemExit(f'V101b backend marker missing: {marker}')

backend_path.write_text(backend, encoding='utf-8')
app_path.write_text(app, encoding='utf-8')
print('V101b AI scan animal linking applied')
