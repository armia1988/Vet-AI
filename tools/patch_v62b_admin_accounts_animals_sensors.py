from pathlib import Path


def need(text: str, marker: str, label: str) -> None:
    if marker not in text:
        raise SystemExit(f'V62b: {label} marker missing: {marker}')


# ---------------------------------------------------------------------------
# Accounts: 3 clear tabs and manager / assistant-manager invitation roles.
# ---------------------------------------------------------------------------
p = Path('lib/admin/admin_account_center.dart')
s = p.read_text(encoding='utf-8')
if "import 'admin_account_control_v2.dart';" not in s:
    need(s, "import 'admin_service.dart';\n", 'account import')
    s = s.replace(
        "import 'admin_service.dart';\n",
        "import 'admin_service.dart';\nimport 'admin_account_control_v2.dart';\n",
        1,
    )

if 'length: 3,' not in s:
    need(s, '        length: 2,', 'account tab count')
    s = s.replace('        length: 2,', '        length: 3,', 1)

old_tabs = """              tabs: [
                Tab(icon: const Icon(Icons.person_add_alt_1_rounded), text: _act(context, 'Accounts & invitations', 'الحسابات والدعوات', 'Accounts & uitnodigingen')),
                Tab(icon: const Icon(Icons.admin_panel_settings_rounded), text: _act(context, 'Staff & permissions', 'الموظفون والصلاحيات', 'Medewerkers & rechten')),
              ],
"""
new_tabs = """              tabs: [
                Tab(icon: const Icon(Icons.manage_accounts_rounded), text: _act(context, 'Accounts', 'الحسابات', 'Accounts')),
                Tab(icon: const Icon(Icons.person_add_alt_1_rounded), text: _act(context, 'Invitations', 'الدعوات', 'Uitnodigingen')),
                Tab(icon: const Icon(Icons.admin_panel_settings_rounded), text: _act(context, 'Staff & permissions', 'الموظفون والصلاحيات', 'Medewerkers & rechten')),
              ],
"""
if new_tabs not in s:
    need(s, old_tabs, 'account tabs')
    s = s.replace(old_tabs, new_tabs, 1)

old_views = '          const Expanded(child: TabBarView(children: [VetAdminAccountsInvitePage(), VetAdminStaffCenter()])),\n'
new_views = '          const Expanded(child: TabBarView(children: [VetAdminAccountControlV2(), VetAdminAccountsInvitePage(), VetAdminStaffCenter()])),\n'
if new_views not in s:
    need(s, old_views, 'account views')
    s = s.replace(old_views, new_views, 1)

invite_roles_old = """                      DropdownMenuItem(value: 'super_admin', child: Text('Super Admin')),
                      DropdownMenuItem(value: 'admin', child: Text('Admin')),
"""
invite_roles_new = """                      DropdownMenuItem(value: 'super_admin', child: Text('Super Admin')),
                      DropdownMenuItem(value: 'manager', child: Text('Manager')),
                      DropdownMenuItem(value: 'assistant_manager', child: Text('Assistant Manager')),
                      DropdownMenuItem(value: 'admin', child: Text('Admin')),
"""
if "DropdownMenuItem(value: 'assistant_manager', child: Text('Assistant Manager'))" not in s:
    need(s, invite_roles_old, 'invite manager roles')
    s = s.replace(invite_roles_old, invite_roles_new, 1)
p.write_text(s, encoding='utf-8')


# ---------------------------------------------------------------------------
# Staff permissions: first-class Manager and Assistant Manager roles.
# ---------------------------------------------------------------------------
p = Path('lib/admin/admin_staff_center.dart')
s = p.read_text(encoding='utf-8')
staff_roles_old = """                    DropdownMenuItem(value: 'super_admin', child: Text('Super Admin')),
                    DropdownMenuItem(value: 'admin', child: Text('Admin')),
"""
staff_roles_new = """                    DropdownMenuItem(value: 'super_admin', child: Text('Super Admin')),
                    DropdownMenuItem(value: 'manager', child: Text('Manager')),
                    DropdownMenuItem(value: 'assistant_manager', child: Text('Assistant Manager')),
                    DropdownMenuItem(value: 'admin', child: Text('Admin')),
"""
if "value: 'assistant_manager'" not in s:
    need(s, staff_roles_old, 'staff manager roles')
    s = s.replace(staff_roles_old, staff_roles_new, 1)
p.write_text(s, encoding='utf-8')


# ---------------------------------------------------------------------------
# Company/farm detail: real nested pages with AppBar/back, visible Accounts and
# Add Sensor shortcuts, and a customer-scoped sensor creation form.
# ---------------------------------------------------------------------------
p = Path('lib/admin/admin_company_center.dart')
s = p.read_text(encoding='utf-8')

if 'Future<void> _addSensor() async {' not in s:
    start = s.find('  Future<void> _openManager(Widget page) async {')
    end = s.find('  void _manage(String value) {', start)
    if start < 0 or end < 0:
        raise SystemExit('V62b: company manager route block missing')
    block = r'''  Future<void> _openManager(Widget page, String title) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(title)),
          body: SafeArea(child: page),
        ),
      ),
    );
    if (mounted) reload();
  }

  Future<void> _addSensor() async {
    final uid = TextEditingController();
    final name = TextEditingController();
    final type = TextEditingController(text: 'vetai_sensor_hub');
    final section = TextEditingController();
    final firmware = TextEditingController();
    final notes = TextEditingController();
    var active = true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(_ct(context, 'Add sensor to this customer', 'إضافة حساس للعميل', 'Sensor aan deze klant toevoegen')),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: uid, decoration: InputDecoration(labelText: _ct(context, 'Device UID / serial number', 'UID / الرقم التسلسلي', 'Apparaat-UID / serienummer'))),
                const SizedBox(height: 10),
                TextField(controller: name, decoration: InputDecoration(labelText: _ct(context, 'Sensor name', 'اسم الحساس', 'Sensornaam'))),
                const SizedBox(height: 10),
                TextField(controller: type, decoration: InputDecoration(labelText: _ct(context, 'Device type', 'نوع الجهاز', 'Apparaattype'))),
                const SizedBox(height: 10),
                TextField(controller: section, decoration: InputDecoration(labelText: _ct(context, 'Section / barn', 'القسم / الحظيرة', 'Afdeling / stal'))),
                const SizedBox(height: 10),
                TextField(controller: firmware, decoration: const InputDecoration(labelText: 'Firmware')),
                const SizedBox(height: 10),
                TextField(controller: notes, minLines: 2, maxLines: 4, decoration: InputDecoration(labelText: _ct(context, 'Private admin notes', 'ملاحظات الإدارة', 'Privé-adminnotities'))),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: active,
                  onChanged: (v) => setLocal(() => active = v),
                  title: Text(_ct(context, 'Enable immediately', 'تفعيل فورًا', 'Direct activeren')),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_ct(context, 'Cancel', 'إلغاء', 'Annuleren'))),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(_ct(context, 'Add sensor', 'إضافة الحساس', 'Sensor toevoegen'))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    if (uid.text.trim().isEmpty || type.text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_ct(context, 'UID and device type are required.', 'UID ونوع الجهاز مطلوبين.', 'UID en apparaattype zijn verplicht.'))),
        );
      }
      return;
    }

    try {
      await admin.client.rpc('admin_create_sensor_device', params: {
        'p_farm_id': widget.farm['id'].toString(),
        'p_device_uid': uid.text.trim(),
        'p_display_name': name.text.trim(),
        'p_device_type': type.text.trim(),
        'p_section_name': section.text.trim(),
        'p_firmware_version': firmware.text.trim(),
        'p_active': active,
        'p_admin_notes': notes.text.trim(),
      });
      admin.invalidateCache();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_ct(context, 'Sensor added to this customer.', 'تم إضافة الحساس للعميل.', 'Sensor is aan deze klant toegevoegd.'))),
        );
      }
      reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: VetColors.red),
        );
      }
    }
  }

'''
    s = s[:start] + block + s[end:]

route_map = {
    '_openManager(const VetAdminAccountCenter());': "_openManager(const VetAdminAccountCenter(), _ct(context, 'Accounts & users', 'الحسابات والمستخدمون', 'Accounts & gebruikers'));",
    '_openManager(const VetAdminSensorCenter());': "_openManager(const VetAdminSensorCenter(), _ct(context, 'Sensors & devices', 'الحساسات والأجهزة', 'Sensoren & apparaten'));",
    '_openManager(const VetAdminAnimalCenter());': "_openManager(const VetAdminAnimalCenter(), _ct(context, 'Animal management', 'إدارة الحيوانات', 'Dierenbeheer'));",
    '_openManager(const VetAdminSupportCenter());': "_openManager(const VetAdminSupportCenter(), _ct(context, 'Support inbox', 'صندوق الدعم', 'Support-inbox'));",
}
for old, new in route_map.items():
    s = s.replace(old, new)

refresh_action = "            IconButton(onPressed: reload, tooltip: _ct(context, 'Refresh', 'تحديث', 'Vernieuwen'), icon: const Icon(Icons.refresh_rounded)),\n"
if 'tooltip: _ct(context, \'Accounts\'' not in s:
    need(s, refresh_action, 'company appbar refresh action')
    quick = """            IconButton(
              tooltip: _ct(context, 'Accounts', 'الحسابات', 'Accounts'),
              onPressed: () => _openManager(const VetAdminAccountCenter(), _ct(context, 'Accounts & users', 'الحسابات والمستخدمون', 'Accounts & gebruikers')),
              icon: const Icon(Icons.manage_accounts_rounded),
            ),
            IconButton(
              tooltip: _ct(context, 'Add sensor', 'إضافة حساس', 'Sensor toevoegen'),
              onPressed: _addSensor,
              icon: const Icon(Icons.add_circle_outline_rounded),
            ),
"""
    s = s.replace(refresh_action, quick + refresh_action, 1)

s = s.replace(
    "button: _ct(context, 'Manage sensors', 'إدارة الحساسات', 'Sensoren beheren'),",
    "button: _ct(context, 'Add sensor', 'إضافة حساس', 'Sensor toevoegen'),",
    1,
)

sensor_manage = "              onManage: () => _openManager(const VetAdminSensorCenter(), _ct(context, 'Sensors & devices', 'الحساسات والأجهزة', 'Sensoren & apparaten')),\n"
if sensor_manage in s:
    s = s.replace(sensor_manage, '              onManage: _addSensor,\n', 1)

p.write_text(s, encoding='utf-8')


# ---------------------------------------------------------------------------
# Animal page: make it unmistakably a control center, while preserving all CRUD.
# ---------------------------------------------------------------------------
p = Path('lib/admin/admin_animal_center.dart')
s = p.read_text(encoding='utf-8')
s = s.replace(
    "_ant(context, 'Animal registry operations', 'إدارة سجل الحيوانات', 'Dierregisterbeheer')",
    "_ant(context, 'Animal management control center', 'مركز إدارة وتحكم الحيوانات', 'Controlecentrum dierenbeheer')",
    1,
)
s = s.replace(
    "_ant(context, 'Create and edit animal records across every customer farm and see sensor assignments.', 'أضف وعدّل سجلات الحيوانات في كل مزارع العملاء وشاهد الحساسات المرتبطة بها.', 'Maak en bewerk dierrecords voor alle klantboerderijen en bekijk sensorkoppelingen.')",
    "_ant(context, 'Full control of animal records, status, identity, farm assignment and linked sensors.', 'تحكم كامل في سجلات الحيوانات وحالتها وبياناتها والمزرعة والحساسات المرتبطة بها.', 'Volledig beheer van dierrecords, status, identiteit, boerderij en gekoppelde sensoren.')",
    1,
)
p.write_text(s, encoding='utf-8')


# ---------------------------------------------------------------------------
# Fixed admin text scale on the web/iPhone so browser accessibility zoom cannot
# turn nested management pages into giant labels.
# ---------------------------------------------------------------------------
p = Path('lib/admin/admin_entry.dart')
s = p.read_text(encoding='utf-8')
admin_pos = s.find('class VetAdminApp extends StatefulWidget')
if admin_pos < 0:
    raise SystemExit('V62b: VetAdminApp missing')
segment = s[admin_pos:]
if 'textScaler: const TextScaler.linear(1.0)' not in segment:
    anchor = """        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
"""
    local_pos = segment.find(anchor)
    if local_pos < 0:
        raise SystemExit('V62b: admin MaterialApp localization anchor missing')
    insert_at = admin_pos + local_pos + len(anchor)
    builder = """        builder: (context, child) {
          final media = MediaQuery.of(context);
          return MediaQuery(
            data: media.copyWith(textScaler: const TextScaler.linear(1.0)),
            child: child ?? const SizedBox.shrink(),
          );
        },
"""
    s = s[:insert_at] + builder + s[insert_at:]
p.write_text(s, encoding='utf-8')


# ---------------------------------------------------------------------------
# Dashboard label: make Accounts visible and obvious.
# ---------------------------------------------------------------------------
p = Path('lib/admin/admin_dashboard.dart')
s = p.read_text(encoding='utf-8')
s = s.replace(
    "_AdminDestination(Icons.admin_panel_settings_rounded, _at(context, 'Accounts & staff', 'الحسابات والموظفون', 'Accounts & medewerkers'))",
    "_AdminDestination(Icons.manage_accounts_rounded, _at(context, 'Accounts & users', 'الحسابات والمستخدمون', 'Accounts & gebruikers'))",
)
s = s.replace(
    "_AdminDestination(Icons.admin_panel_settings_rounded, _at(context, 'Admin staff', 'فريق الإدارة', 'Adminteam'))",
    "_AdminDestination(Icons.manage_accounts_rounded, _at(context, 'Accounts & users', 'الحسابات والمستخدمون', 'Accounts & gebruikers'))",
)
p.write_text(s, encoding='utf-8')


checks = {
    'lib/admin/admin_account_center.dart': ['VetAdminAccountControlV2()', 'length: 3', "value: 'assistant_manager'"],
    'lib/admin/admin_staff_center.dart': ["value: 'manager'", "value: 'assistant_manager'"],
    'lib/admin/admin_company_center.dart': ['Future<void> _addSensor() async {', 'appBar: AppBar(title: Text(title))', 'Icons.manage_accounts_rounded', 'onPressed: _addSensor'],
    'lib/admin/admin_animal_center.dart': ['Animal management control center', 'مركز إدارة وتحكم الحيوانات'],
    'lib/admin/admin_entry.dart': ['textScaler: const TextScaler.linear(1.0)'],
}
for file_name, markers in checks.items():
    text = Path(file_name).read_text(encoding='utf-8')
    for marker in markers:
        if marker not in text:
            raise SystemExit(f'V62b verification missing {marker} in {file_name}')

print('Vet AI V62b applied: compact admin control pages, back navigation, account/email/password reset controls, manager roles, and direct customer sensor creation')
