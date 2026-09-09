from pathlib import Path

p = Path('lib/admin/admin_company_center.dart')
s = p.read_text(encoding='utf-8')

old_sensor = """              onManage: () => _openManager(const VetAdminSensorCenter()),"""
new_sensor = """              onManage: _addSensor,"""
s = s.replace(old_sensor, new_sensor)

old_animal = """              onManage: () => _openManager(const VetAdminAnimalCenter()),"""
new_animal = """              onManage: () => _openManager(const VetAdminAnimalCenter(), _ct(context, 'Animal management', 'إدارة الحيوانات', 'Dierenbeheer')),"""
s = s.replace(old_animal, new_animal)

old_support = """              onManage: () => _openManager(const VetAdminSupportCenter()),"""
new_support = """              onManage: () => _openManager(const VetAdminSupportCenter(), _ct(context, 'Support inbox', 'صندوق الدعم', 'Support-inbox')),"""
s = s.replace(old_support, new_support)

for marker in [
    '_openManager(const VetAdminSensorCenter())',
    '_openManager(const VetAdminAnimalCenter())',
    '_openManager(const VetAdminSupportCenter())',
    '_openManager(const VetAdminAccountCenter())',
]:
    if marker in s:
        raise SystemExit(f'V62c unresolved manager route: {marker}')

p.write_text(s, encoding='utf-8')
print('Vet AI V62c applied: all company manager routes use titled AppBar/back navigation; sensor action opens customer-scoped add form')
