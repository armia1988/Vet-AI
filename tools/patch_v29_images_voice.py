from pathlib import Path

app = Path('lib/v5_app.dart')
s = app.read_text(encoding='utf-8')
s = s.replace('assets/icons/livestock_final.png', 'assets/icons/livestock_section.webp')
s = s.replace('assets/icons/poultry_final.png', 'assets/icons/poultry_section.webp')
s = s.replace('assets/icons/dog_final.png', 'assets/icons/dog_section.webp')
app.write_text(s, encoding='utf-8')
print('V29: section artwork paths updated')

report = Path('lib/analysis/vet_analysis_report.dart')
s = report.read_text(encoding='utf-8')
start = s.find("    try {\n      await _tts.stop();\n      final isArabic = widget.languageCode.toLowerCase().startsWith('ar');")
end_marker = "    } catch (_) {\n      // The complete written result remains available if audio is unavailable.\n    }\n"
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
report.write_text(s, encoding='utf-8')
print('V29: robotic device TTS fallback disabled')
