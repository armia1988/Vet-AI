from pathlib import Path

app = Path('lib/v5_app.dart')
s = app.read_text(encoding='utf-8')
artwork = {
    'assets/icons/livestock_final.png': 'assets/icons/livestock_section.webp',
    'assets/icons/poultry_final.png': 'assets/icons/poultry_section.webp',
    'assets/icons/dog_final.png': 'assets/icons/dog_section.webp',
}
for old, new in artwork.items():
    old_count = s.count(old)
    new_count = s.count(new)
    if old_count > 0:
        s = s.replace(old, new)
        print(f'V29: replaced {old_count} reference(s): {old} -> {new}')
    elif new_count > 0:
        print(f'V29: artwork already migrated: {new}')
    else:
        raise SystemExit(f'V29: neither old nor new artwork reference found: {old} / {new}')
app.write_text(s, encoding='utf-8')

report = Path('lib/analysis/vet_analysis_report.dart')
s = report.read_text(encoding='utf-8')

# Remove the device-TTS locale helper only when it still exists.
lang_start = s.find("  String _speechLanguage(String code) {")
lang_end_marker = "  String _speechSafeText(String input) {"
if lang_start >= 0:
    lang_end = s.find(lang_end_marker, lang_start)
    if lang_end < 0:
        raise SystemExit('V29: _speechLanguage helper end marker not found')
    s = s[:lang_start] + s[lang_end:]
    print('V29: removed obsolete device-TTS locale helper')

start_marker = "    try {\n      await _tts.stop();\n      final isArabic = widget.languageCode.toLowerCase().startsWith('ar');"
end_marker = "    } catch (_) {\n      // The complete written result remains available if audio is unavailable.\n    }\n"
replacement_marker = 'Natural cloud voice is temporarily unavailable. Please try the speaker again.'
start = s.find(start_marker)
if start >= 0:
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
    print('V29: robotic device TTS fallback disabled')
elif replacement_marker in s:
    print('V29: cloud-only voice path already applied')
else:
    raise SystemExit('V29: neither old device TTS block nor cloud-only replacement found')

if '_tts.speak(text)' in s:
    raise SystemExit('V29: robotic device TTS speak call still present')

report.write_text(s, encoding='utf-8')
print('V29: patch verification complete')
