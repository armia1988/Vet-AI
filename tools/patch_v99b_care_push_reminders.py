from pathlib import Path

service_path = Path('lib/health/animal_health_service.dart')
ui_path = Path('lib/health/animal_health_center.dart')

service = service_path.read_text(encoding='utf-8')
ui = ui_path.read_text(encoding='utf-8')

# Service: persist a structured dose interval and support advancing the next dose.
if 'int? doseIntervalHours,' not in service:
    old = """    DateTime? endsAt,\n    DateTime? nextDoseAt,\n    String? notes,\n"""
    new = """    DateTime? endsAt,\n    int? doseIntervalHours,\n    DateTime? nextDoseAt,\n    String? notes,\n"""
    if old not in service:
        raise SystemExit('V99b service parameter anchor not found')
    service = service.replace(old, new, 1)

if "'dose_interval_hours': doseIntervalHours," not in service:
    old = """      'frequency': frequency.trim().isEmpty ? null : frequency.trim(),\n      'starts_at': startsAt.toUtc().toIso8601String(),\n"""
    new = """      'frequency': frequency.trim().isEmpty ? null : frequency.trim(),\n      'dose_interval_hours': doseIntervalHours,\n      'starts_at': startsAt.toUtc().toIso8601String(),\n"""
    if old not in service:
        raise SystemExit('V99b medication insert anchor not found')
    service = service.replace(old, new, 1)

if 'Future<void> recordMedicationDose(' not in service:
    anchor = '  Future<void> completeMedication(Map<String, dynamic> medication) async {'
    if anchor not in service:
        raise SystemExit('V99b completeMedication anchor not found')
    method = """  Future<void> recordMedicationDose(Map<String, dynamic> medication) async {\n    final now = DateTime.now();\n    final rawInterval = medication['dose_interval_hours'];\n    final intervalHours = rawInterval is num\n        ? rawInterval.toInt()\n        : int.tryParse('${rawInterval ?? ''}');\n    final nextDose = intervalHours != null && intervalHours > 0\n        ? now.add(Duration(hours: intervalHours))\n        : null;\n\n    await _client\n        .from('animal_medications')\n        .update({\n          'status': 'active',\n          'next_dose_at': nextDose?.toUtc().toIso8601String(),\n        })\n        .eq('id', '${medication['id']}');\n\n    await addHealthEvent(\n      farmId: '${medication['farm_id']}',\n      animalId: '${medication['animal_id']}',\n      eventType: 'treatment',\n      title: 'Medication dose given: ${medication['medication_name'] ?? ''}',\n      details: [\n        if (medication['dose'] != null) 'Dose: ${medication['dose']}',\n        if (medication['route'] != null) 'Route: ${medication['route']}',\n        if (nextDose != null) 'Next dose: ${nextDose.toLocal()}',\n      ].join(' · '),\n      occurredAt: now,\n    );\n  }\n\n"""
    service = service.replace(anchor, method + anchor, 1)

# UI: structured interval selector for dependable recurring reminders.
if 'int? doseIntervalHours;' not in ui:
    old = """    var start = DateTime.now();\n    DateTime? nextDose;\n"""
    new = """    var start = DateTime.now();\n    DateTime? nextDose;\n    int? doseIntervalHours;\n"""
    if old not in ui:
        raise SystemExit('V99b UI dose state anchor not found')
    ui = ui.replace(old, new, 1)

interval_marker = "Automatic reminder interval"
if interval_marker not in ui:
    anchor = """                  TextField(\n                    controller: frequency,\n                    decoration: InputDecoration(\n                      labelText: _t(context, 'Frequency', 'التكرار', 'Frequentie'),\n                      hintText: _t(context, 'e.g. every 12 hours', 'مثال: كل 12 ساعة', 'bijv. elke 12 uur'),\n                    ),\n                  ),\n                  const SizedBox(height: 8),\n"""
    replacement = """                  TextField(\n                    controller: frequency,\n                    decoration: InputDecoration(\n                      labelText: _t(context, 'Frequency', 'التكرار', 'Frequentie'),\n                      hintText: _t(context, 'e.g. every 12 hours', 'مثال: كل 12 ساعة', 'bijv. elke 12 uur'),\n                    ),\n                  ),\n                  const SizedBox(height: 10),\n                  DropdownButtonFormField<int?>(\n                    value: doseIntervalHours,\n                    decoration: InputDecoration(\n                      labelText: _t(\n                        context,\n                        'Automatic reminder interval',\n                        'فاصل التذكير التلقائي',\n                        'Automatisch herinneringsinterval',\n                      ),\n                    ),\n                    items: [\n                      DropdownMenuItem<int?>(\n                        value: null,\n                        child: Text(_t(context, 'One-time / manual', 'مرة واحدة / يدوي', 'Eenmalig / handmatig')),\n                      ),\n                      const DropdownMenuItem<int?>(value: 6, child: Text('6 h')),\n                      const DropdownMenuItem<int?>(value: 8, child: Text('8 h')),\n                      const DropdownMenuItem<int?>(value: 12, child: Text('12 h')),\n                      const DropdownMenuItem<int?>(value: 24, child: Text('24 h')),\n                      const DropdownMenuItem<int?>(value: 48, child: Text('48 h')),\n                      const DropdownMenuItem<int?>(value: 72, child: Text('72 h')),\n                      const DropdownMenuItem<int?>(value: 168, child: Text('7 days')),\n                    ],\n                    onChanged: (value) {\n                      setDialogState(() {\n                        doseIntervalHours = value;\n                        if (value != null && nextDose == null) {\n                          nextDose = start.add(Duration(hours: value));\n                        }\n                      });\n                    },\n                  ),\n                  const SizedBox(height: 8),\n"""
    if anchor not in ui:
        raise SystemExit('V99b frequency UI anchor not found')
    ui = ui.replace(anchor, replacement, 1)

if 'doseIntervalHours: doseIntervalHours,' not in ui:
    old = """          startsAt: start,\n          nextDoseAt: nextDose,\n          notes: notes.text,\n"""
    new = """          startsAt: start,\n          doseIntervalHours: doseIntervalHours,\n          nextDoseAt: nextDose,\n          notes: notes.text,\n"""
    if old not in ui:
        raise SystemExit('V99b addMedication call anchor not found')
    ui = ui.replace(old, new, 1)

info_marker = 'Care reminders are checked every 15 minutes'
if info_marker not in ui:
    anchor = """          const SizedBox(height: 22),\n          Text(\n            _t(context, 'Vaccinations', 'التطعيمات', 'Vaccinaties'),\n"""
    info = """          const SizedBox(height: 14),\n          Card(\n            child: ListTile(\n              leading: const Icon(Icons.notifications_active_rounded),\n              title: Text(\n                _t(\n                  context,\n                  'Automatic care reminders',\n                  'تذكيرات الرعاية التلقائية',\n                  'Automatische zorgherinneringen',\n                ),\n                style: const TextStyle(fontWeight: FontWeight.w800),\n              ),\n              subtitle: Text(\n                _t(\n                  context,\n                  'Care reminders are checked every 15 minutes. Vaccines due within 24 hours and scheduled medication doses create a real Vet AI alert and iOS push notification.',\n                  'يتم فحص تذكيرات الرعاية كل 15 دقيقة. التطعيمات المستحقة خلال 24 ساعة وجرعات الدواء المجدولة تنشئ تنبيه Vet AI حقيقي وإشعار Push على iPhone.',\n                  'Zorgherinneringen worden elke 15 minuten gecontroleerd. Vaccins binnen 24 uur en geplande medicatiedoses maken een echte Vet AI-melding en iOS-pushmelding.',\n                ),\n              ),\n            ),\n          ),\n          const SizedBox(height: 22),\n          Text(\n            _t(context, 'Vaccinations', 'التطعيمات', 'Vaccinaties'),\n"""
    if anchor not in ui:
        raise SystemExit('V99b care reminder info anchor not found')
    ui = ui.replace(anchor, info, 1)

if "row['dose_interval_hours']" not in ui:
    old = """                    if (row['frequency'] != null) '${row['frequency']}',\n                    if (next != null) '${_t(context, 'Next', 'القادم', 'Volgende')}: ${_dateLabel(next)}',\n"""
    new = """                    if (row['frequency'] != null) '${row['frequency']}',\n                    if (row['dose_interval_hours'] != null)\n                      '${_t(context, 'Reminder', 'التذكير', 'Herinnering')}: ${row['dose_interval_hours']} h',\n                    if (next != null) '${_t(context, 'Next', 'القادم', 'Volgende')}: ${_dateLabel(next)}',\n"""
    if old not in ui:
        raise SystemExit('V99b medication subtitle anchor not found')
    ui = ui.replace(old, new, 1)

if "value: 'dose'" not in ui:
    old = """                  trailing: active\n                      ? IconButton.filledTonal(\n                          tooltip: _t(context, 'Complete treatment', 'إنهاء العلاج', 'Behandeling afronden'),\n                          onPressed: () async {\n                            try {\n                              await AnimalHealthService.instance.completeMedication(row);\n                              await load();\n                            } catch (e) {\n                              if (mounted) _showError(context, e);\n                            }\n                          },\n                          icon: const Icon(Icons.check_rounded),\n                        )\n                      : const Icon(Icons.check_circle_outline_rounded),\n"""
    new = """                  trailing: active\n                      ? PopupMenuButton<String>(\n                          tooltip: _t(context, 'Medication actions', 'إجراءات الدواء', 'Medicatieacties'),\n                          onSelected: (value) async {\n                            try {\n                              if (value == 'dose') {\n                                await AnimalHealthService.instance.recordMedicationDose(row);\n                              } else if (value == 'complete') {\n                                await AnimalHealthService.instance.completeMedication(row);\n                              }\n                              await load();\n                            } catch (e) {\n                              if (mounted) _showError(context, e);\n                            }\n                          },\n                          itemBuilder: (context) => [\n                            if (row['status'] == 'active' && next != null)\n                              PopupMenuItem<String>(\n                                value: 'dose',\n                                child: ListTile(\n                                  contentPadding: EdgeInsets.zero,\n                                  leading: const Icon(Icons.medication_liquid_rounded),\n                                  title: Text(_t(context, 'Dose given', 'تم إعطاء الجرعة', 'Dosis gegeven')),\n                                ),\n                              ),\n                            PopupMenuItem<String>(\n                              value: 'complete',\n                              child: ListTile(\n                                contentPadding: EdgeInsets.zero,\n                                leading: const Icon(Icons.check_circle_outline_rounded),\n                                title: Text(_t(context, 'Complete treatment', 'إنهاء العلاج', 'Behandeling afronden')),\n                              ),\n                            ),\n                          ],\n                        )\n                      : const Icon(Icons.check_circle_outline_rounded),\n"""
    if old not in ui:
        raise SystemExit('V99b medication action anchor not found')
    ui = ui.replace(old, new, 1)

# Verification markers and idempotency.
for marker in [
    'int? doseIntervalHours,',
    "'dose_interval_hours': doseIntervalHours,",
    'Future<void> recordMedicationDose(',
]:
    if marker not in service:
        raise SystemExit(f'V99b service marker missing: {marker}')

for marker in [
    'Automatic reminder interval',
    'doseIntervalHours: doseIntervalHours,',
    'Care reminders are checked every 15 minutes',
    "value: 'dose'",
]:
    if marker not in ui:
        raise SystemExit(f'V99b UI marker missing: {marker}')

service_path.write_text(service, encoding='utf-8')
ui_path.write_text(ui, encoding='utf-8')
print('V99b care push reminder UI and dose workflow applied')
