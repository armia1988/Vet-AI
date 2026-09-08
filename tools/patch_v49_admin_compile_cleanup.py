from pathlib import Path
import re

admin = Path('lib/admin/admin_dashboard.dart')
s = admin.read_text(encoding='utf-8')
s = s.replace('Icons.command_rounded', 'Icons.dashboard_customize_rounded')
admin.write_text(s, encoding='utf-8')

v5 = Path('lib/v5_app.dart')
s = v5.read_text(encoding='utf-8')
pattern = re.compile(
    r"\n    const columns = 5;.*?\n}\n\nString _animalGroupAssetFromSpriteIndex",
    re.S,
)
if pattern.search(s):
    s = pattern.sub('\n\nString _animalGroupAssetFromSpriteIndex', s, count=1)
v5.write_text(s, encoding='utf-8')

print('Vet AI V49 admin compile cleanup applied')
