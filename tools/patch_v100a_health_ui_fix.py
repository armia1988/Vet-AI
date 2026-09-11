from pathlib import Path

path = Path('lib/health/animal_health_center.dart')
text = path.read_text(encoding='utf-8')
old = """              onPressed: title.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, true),
"""
new = """              onPressed: () => Navigator.pop(
                dialogContext,
                title.text.trim().isNotEmpty,
              ),
"""
if old in text:
    text = text.replace(old, new, 1)
elif new not in text:
    raise SystemExit('V100a health-event save anchor not found')
path.write_text(text, encoding='utf-8')
print('V100a health-event save action fixed')
