from pathlib import Path
import re

admin = Path('lib/admin/admin_dashboard.dart')
s = admin.read_text(encoding='utf-8')
s = s.replace('Icons.command_rounded', 'Icons.dashboard_customize_rounded')

sensor_import = "import 'admin_sensor_center.dart';\n"
if sensor_import not in s:
    anchor = "import 'admin_service.dart';\n"
    if anchor not in s:
        raise SystemExit('V49 admin sensor center: import anchor not found')
    s = s.replace(anchor, anchor + sensor_import, 1)

old_sensor_route = """      case 4:\n        return _SensorsPage(key: ValueKey('sensors-$refreshTick'));\n"""
new_sensor_route = """      case 4:\n        return VetAdminSensorCenter(key: ValueKey('sensors-$refreshTick'));\n"""
if old_sensor_route in s:
    s = s.replace(old_sensor_route, new_sensor_route, 1)
elif 'return VetAdminSensorCenter(' not in s:
    raise SystemExit('V49 admin sensor center: route anchor not found')

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

print('Vet AI V49 admin compile cleanup and advanced sensor center applied')
