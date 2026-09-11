from pathlib import Path

required_files = {
    'lib/health/animal_health_service.dart': [
        'class AnimalHealthService',
        'farm_health_dashboard',
        'animal_health_events',
        'animal_vaccinations',
        'animal_medications',
        'Future<List<AnimalTimelineItem>> timeline',
    ],
    'lib/health/animal_health_center.dart': [
        'class AnimalHealthCenterPage',
        'Farm Health Center',
        'Health timeline',
        'Schedule vaccination',
        'Medication plans',
        'AI cases · 24h',
    ],
    'supabase/migrations/20260911091500_v98_v100_animal_health_management.sql': [
        'create table if not exists public.animal_health_events',
        'create table if not exists public.animal_vaccinations',
        'create table if not exists public.animal_medications',
        'create or replace function public.farm_health_dashboard',
        'enable row level security',
    ],
    'tools/patch_v100_animal_health_center.py': [
        'AnimalHealthCenterPage(farmId: farmId)',
        "import 'health/animal_health_center.dart';",
    ],
}

for file_name, markers in required_files.items():
    path = Path(file_name)
    if not path.exists():
        raise SystemExit(f'V100 missing file: {file_name}')
    text = path.read_text(encoding='utf-8')
    for marker in markers:
        if marker not in text:
            raise SystemExit(f'V100 missing marker: {file_name} / {marker}')

app = Path('lib/v5_app.dart').read_text(encoding='utf-8')
for marker in [
    "import 'health/animal_health_center.dart';",
    'AnimalHealthCenterPage(farmId: farmId)',
    "'Farm Health Center'",
]:
    if marker not in app:
        raise SystemExit(f'V100 app integration missing: {marker}')

if app.count("import 'health/animal_health_center.dart';") != 1:
    raise SystemExit('V100 health center import is duplicated')
if app.count('AnimalHealthCenterPage(farmId: farmId)') != 1:
    raise SystemExit('V100 health center navigation is duplicated')

print('V98-V100 animal health timeline, care manager and smart dashboard verified')
