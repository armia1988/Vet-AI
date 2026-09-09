from pathlib import Path

p = Path('lib/admin/admin_company_center.dart')
s = p.read_text(encoding='utf-8')

s = s.replace(
    "              onManage: () => _openManager(const VetAdminSensorCenter()),",
    "              onManage: _addSensor,",
)
s = s.replace(
    "              onManage: () => _openManager(const VetAdminAnimalCenter()),",
    "              onManage: () => _openManager(const VetAdminAnimalCenter(), _ct(context, 'Animal management', 'إدارة الحيوانات', 'Dierenbeheer')),
",
)
s = s.replace(
    "              onManage: () => _openManager(const VetAdminSupportCenter()),",
    "              onManage: () => _openManager(const VetAdminSupportCenter(), _ct(context, 'Support inbox', 'صندوق الدعم', 'Support-inbox')),
",
)

# Guard against any remaining one-argument manager calls after V62 changed the
# method signature to (page, title).
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
