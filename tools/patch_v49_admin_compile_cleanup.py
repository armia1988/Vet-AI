from pathlib import Path
import re

admin = Path('lib/admin/admin_dashboard.dart')
s = admin.read_text(encoding='utf-8')
s = s.replace('Icons.command_rounded', 'Icons.dashboard_customize_rounded')

imports = [
    "import 'admin_sensor_center.dart';\n",
    "import 'admin_notification_center.dart';\n",
    "import 'admin_company_center.dart';\n",
]
anchor = "import 'admin_service.dart';\n"
if anchor not in s:
    raise SystemExit('V49 admin: import anchor not found')
for item in imports:
    if item not in s:
        s = s.replace(anchor, anchor + item, 1)

routes = [
    (
        """      case 1:\n        return _FarmsPage(key: ValueKey('farms-$refreshTick'));\n""",
        """      case 1:\n        return VetAdminCompanyCenter(key: ValueKey('farms-$refreshTick'));\n""",
        'VetAdminCompanyCenter',
    ),
    (
        """      case 4:\n        return _SensorsPage(key: ValueKey('sensors-$refreshTick'));\n""",
        """      case 4:\n        return VetAdminSensorCenter(key: ValueKey('sensors-$refreshTick'));\n""",
        'VetAdminSensorCenter',
    ),
    (
        """      case 6:\n        return _NotificationsPage(key: ValueKey('notifications-$refreshTick'));\n""",
        """      case 6:\n        return VetAdminNotificationCenter(key: ValueKey('notifications-$refreshTick'));\n""",
        'VetAdminNotificationCenter',
    ),
]
for old, new, marker in routes:
    if old in s:
        s = s.replace(old, new, 1)
    elif f'return {marker}(' not in s:
        raise SystemExit(f'V49 admin route missing: {marker}')

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

print('Vet AI V49 admin cleanup and advanced company/sensor/notification centers applied')
