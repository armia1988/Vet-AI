from pathlib import Path

app = Path('lib/v5_app.dart')
s = app.read_text(encoding='utf-8')
artwork = {
    'assets/icons/livestock_final.png': 'assets/icons/livestock_section.webp',
    'assets/icons/poultry_final.png': 'assets/icons/poultry_section.webp',
    'assets/icons/dog_final.png': 'assets/icons/dog_section.webp',
}
for old, new in artwork.items():
    count = s.count(old)
    if count < 1:
        raise SystemExit(f'V29: expected artwork reference not found: {old}')
    s = s.replace(old, new)
    print(f'V29: replaced {count} reference(s): {old} -> {new}')
app.write_text(s, encoding='utf-8')

report = Path('lib/analysis/vet_analysis_report.dart')
s = report.read_text(encoding='utf-8')
start_marker = "    try {\n      await _tts.stop();\n      final isArabic = widget.languageCode.toLowerCase().startsWith('ar');"
end_marker = "    } catch (_) {\n      // The complete written result remains available if audio is unavailable.\n    }\n"
start = s.find(start_marker)
if start < 0:
    raise SystemExit('V29: device TTS fallback start marker not found')
end = s.find(end_marker, start)
if end < 0:
    raise SystemExit('V29: device TTS fallback end marker not found')
end += len(end_marker)
replacement = """    if (mounted && !_muted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.translate(
              'Natural cloud voice is temporarily unavailable. Please try the speaker again.',
              'الصوت الطبيعي السحابي غير متاح مؤقتًا. جرّب زر السماعة مرة تانية.',
              'De natuurlijke cloudstem is tijdelijk niet beschikbaar. Probeer de luidspreker opnieuw.',
            ),
          ),
        ),
      );
    }
    return;
"""
s = s[:start] + replacement + s[end:]
if '_tts.speak(text)' in s:
    raise SystemExit('V29: robotic device TTS speak call still present')
report.write_text(s, encoding='utf-8')
print('V29: robotic device TTS fallback disabled')
