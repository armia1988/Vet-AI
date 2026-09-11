from pathlib import Path

path = Path('lib/health/animal_health_center.dart')
text = path.read_text(encoding='utf-8')

text = text.replace('    int? doseIntervalHours;\n', '    var doseIntervalHours = 0;\n')
text = text.replace('DropdownButtonFormField<int?>(', 'DropdownButtonFormField<int>(')
text = text.replace('DropdownMenuItem<int?>(\n                        value: null,', "DropdownMenuItem<int>(\n                        value: 0,")
text = text.replace('DropdownMenuItem<int?>', 'DropdownMenuItem<int>')
text = text.replace(
    """                    onChanged: (value) {\n                      setDialogState(() {\n                        doseIntervalHours = value;\n                        if (value != null && nextDose == null) {\n                          nextDose = start.add(Duration(hours: value));\n                        }\n                      });\n                    },\n""",
    """                    onChanged: (value) {\n                      setDialogState(() {\n                        doseIntervalHours = value ?? 0;\n                        if (doseIntervalHours > 0 && nextDose == null) {\n                          nextDose = start.add(Duration(hours: doseIntervalHours));\n                        }\n                      });\n                    },\n""",
)
text = text.replace(
    '          doseIntervalHours: doseIntervalHours,\n',
    '          doseIntervalHours: doseIntervalHours == 0 ? null : doseIntervalHours,\n',
)
text = text.replace(
    'Care reminders are checked every 15 minutes. Vaccines due within 24 hours and scheduled medication doses create a real Vet AI alert and iOS push notification.',
    'Care reminders are checked every 15 minutes. Vaccines due within 24 hours and scheduled medication doses create a Vet AI alert and use the registered iOS APNs push delivery path.',
)
text = text.replace(
    'يتم فحص تذكيرات الرعاية كل 15 دقيقة. التطعيمات المستحقة خلال 24 ساعة وجرعات الدواء المجدولة تنشئ تنبيه Vet AI حقيقي وإشعار Push على iPhone.',
    'يتم فحص تذكيرات الرعاية كل 15 دقيقة. التطعيمات المستحقة خلال 24 ساعة وجرعات الدواء المجدولة تنشئ تنبيه Vet AI وتستخدم مسار APNs المسجل لإشعارات iPhone.',
)
text = text.replace(
    'Zorgherinneringen worden elke 15 minuten gecontroleerd. Vaccins binnen 24 uur en geplande medicatiedoses maken een echte Vet AI-melding en iOS-pushmelding.',
    'Zorgherinneringen worden elke 15 minuten gecontroleerd. Vaccins binnen 24 uur en geplande medicatiedoses maken een Vet AI-melding en gebruiken het geregistreerde iOS APNs-pushpad.',
)

for marker in [
    'var doseIntervalHours = 0;',
    'DropdownButtonFormField<int>(',
    'value: 0,',
    'doseIntervalHours: doseIntervalHours == 0 ? null : doseIntervalHours,',
    'registered iOS APNs push delivery path',
]:
    if marker not in text:
        raise SystemExit(f'V99c marker missing: {marker}')

if 'DropdownButtonFormField<int?>(' in text or 'int? doseIntervalHours;' in text:
    raise SystemExit('V99c nullable interval state remains')

path.write_text(text, encoding='utf-8')
print('V99c care reminder interval UI hardened')
