from pathlib import Path

checks = {
    'lib/health/animal_health_center.dart': [
        'length: 4,',
        'class _FollowUpTab extends StatefulWidget',
        'AiFollowupService.instance.submitFollowup',
        '12 / 24 / 48 hour AI follow-up',
    ],
    'lib/health/ai_followup_service.dart': [
        "from('animal_ai_followups')",
        "'analyze-followup'",
        'uploadDiagnosticMedia',
        "'AI_FOLLOWUP_COMPLETE'",
    ],
    'lib/health/animal_health_service.dart': [
        "from('animal_vaccinations')",
        "from('animal_medications')",
        'dose_interval_hours',
        'recordMedicationDose',
    ],
    'lib/v5_app.dart': [
        "import 'health/animal_health_center.dart';",
        'AnimalHealthCenterPage(farmId: farmId)',
        'animalId: selectedAnimalId',
    ],
    'supabase/functions/analyze-followup/index.ts': [
        'AI_FOLLOWUP_COMPLETE',
        'trend === "worse"',
        '.from("animal_ai_followups")',
        '.from("alerts").insert',
        'IMAGE 1 — original baseline',
        'IMAGE 2 — current follow-up',
    ],
    'supabase/functions/vet-ai-apns-push/index.ts': [
        'alert_id',
    ],
    'supabase/migrations/20260911102000_v102_production_validation.sql': [
        'vet_ai_v102_transactional_smoke',
        'V102_ROLLBACK_SENTINEL',
        'array[12,24,48]',
        'external_notifications_sent',
        'release_validation_runs',
        'vet_ai_v102_record_validation',
    ],
}

for filename, markers in checks.items():
    path = Path(filename)
    if not path.exists():
        raise SystemExit(f'V102 missing required file: {filename}')
    text = path.read_text(encoding='utf-8')
    for marker in markers:
        if marker not in text:
            raise SystemExit(f'V102 missing marker in {filename}: {marker}')

migration = Path('supabase/migrations/20260911102000_v102_production_validation.sql').read_text(encoding='utf-8')
if 'revoke all on function public.vet_ai_v102_transactional_smoke() from authenticated;' not in migration:
    raise SystemExit('V102 transactional smoke test must not be callable by normal authenticated users')
if "grant execute on function public.vet_ai_v102_transactional_smoke() to service_role;" not in migration:
    raise SystemExit('V102 transactional smoke test must be service-role only')

edge = Path('supabase/functions/analyze-followup/index.ts').read_text(encoding='utf-8')
if 'MAX_IMAGE_BYTES = 8 * 1024 * 1024' not in edge:
    raise SystemExit('V102 follow-up image-size guard missing')
if 'responseJsonSchema: SCHEMA' not in edge:
    raise SystemExit('V102 follow-up structured output schema missing')

print('V102 production E2E source wiring verified')
