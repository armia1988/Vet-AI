from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    if old not in text:
        raise SystemExit(f'V62: {label} anchor missing')
    return text.replace(old, new, 1)


# ---------------------------------------------------------------------------
# 1) Accounts center: make the first tab a real account-control screen while
#    preserving the existing invitation and RBAC staff pages.
# ---------------------------------------------------------------------------
p = Path('lib/admin/admin_account_center.dart')
s = p.read_text(encoding='utf-8')
if "import 'admin_account_control_v2.dart';" not in s:
    s = s.replace("import 'admin_service.dart';\n", "import 'admin_service.dart';\nimport 'admin_account_control_v2.dart';\n", 1)
s = replace_once(s, '        length: 2,', '        length: 3,', 'account tab count')
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
s = replace_once(s, old_tabs, new_tabs, 'account tabs')
s = replace_once(
    s,
    '          const Expanded(child: TabBarView(children: [VetAdminAccountsInvitePage(), VetAdminStaffCenter()])),',
    '          const Expanded(child: TabBarView(children: [VetAdminAccountControlV2(), VetAdminAccountsInvitePage(), VetAdminStaffCenter()])),',
    'account tab views',
)
p.write_text(s, encoding='utf-8')


# ---------------------------------------------------------------------------
# 2) Staff RBAC: add Manager and Assistant Manager as first-class roles.
# ---------------------------------------------------------------------------
p = Path('lib/admin/admin_staff_center.dart')
s = p.read_text(encoding='utf-8')
role_anchor = """                    DropdownMenuItem(value: 'super_admin', child: Text('Super Admin')),
                    DropdownMenuItem(value: 'admin', child: Text('Admin')),
"""
role_new = """                    DropdownMenuItem(value: 'super_admin', child: Text('Super Admin')),
                    DropdownMenuItem(value: 'manager', child: Text('Manager')),
                    DropdownMenuItem(value: 'assistant_manager', child: Text('Assistant Manager')),
                    DropdownMenuItem(value: 'admin', child: Text('Admin')),
"""
s = replace_once(s, role_anchor, role_new, 'manager staff roles')
p.write_text(s, encoding='utf-8')


# ---------------------------------------------------------------------------
# 3) Company/customer detail: manager screens are real routes with a visible
#    back button. Add visible Accounts and Add Sensor actions in the app bar.
# ---------------------------------------------------------------------------
p = Path('lib/admin/admin_company_center.dart')
s = p.read_text(encoding='utf-8')
old_open = """  Future<void> _openManager(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (mounted) reload();
  }
"""
new_open = """  Future<void> _openManager(Widget page, String title) async {
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
                SwitchListTile(contentPadding: EdgeInsets.zero, value: active, onChanged: (v) => setLocal(() => active = v), title: Text(_ct(context, 'Enable immediately', 'تفعيل فورًا', 'Direct activeren'))),
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_ct(context, 'UID and device type are required.', 'UID ونوع الجهاز مطلوبين.', 'UID en apparaattype zijn verplicht.'))));
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_ct(context, 'Sensor added to this customer.', 'تم إضافة الحساس للعميل.', 'Sensor is aan deze klant toegevoegd.'))));
      reload();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: VetColors.red));
    }
  }
"""
s = replace_once(s, old_open, new_open, 'manager route shell')

replacements = [
    ("_openManager(const VetAdminAccountCenter());", "_openManager(const VetAdminAccountCenter(), _ct(context, 'Accounts & users', 'الحسابات والمستخدمون', 'Accounts & gebruikers'));"),
    ("_openManager(const VetAdminSensorCenter());", "_openManager(const VetAdminSensorCenter(), _ct(context, 'Sensors & devices', 'الحساسات والأجهزة', 'Sensoren & apparaten'));"),
    ("_openManager(const VetAdminAnimalCenter());", "_openManager(const VetAdminAnimalCenter(), _ct(context, 'Animal management', 'إدارة الحيوانات', 'Dierenbeheer'));"),
    ("_openManager(const VetAdminSupportCenter());", "_openManager(const VetAdminSupportCenter(), _ct(context, 'Support inbox', 'صندوق الدعم', 'Support-inbox'));"),
]
for old, new in replacements:
    s = s.replace(old, new)

old_actions = """          actions: [
            IconButton(onPressed: reload, tooltip: _ct(context, 'Refresh', 'تحديث', 'Vernieuwen'), icon: const Icon(Icons.refresh_rounded)),
            PopupMenuButton<String>(
"""
new_actions = """          actions: [
            IconButton(
              tooltip: _ct(context, 'Accounts', 'الحسابات', 'Accounts'),
              onPressed: () => _openManager(const VetAdminAccountCenter(), _ct(context, 'Accounts & users', 'الحسابات والمستخدمون', 'Accounts & gebruikers')),
              icon: const Icon(Icons.manage_accounts_rounded),
            ),
            IconButton(
              tooltip: _ct(context, 'Add sensor', 'إضافة حساس', 'Sensor toevoegen'),
              onPressed: _addSensor,
              icon: const Icon(Icons.add_circle_outline_rounded),
            ),
            IconButton(onPressed: reload, tooltip: _ct(context, 'Refresh', 'تحديث', 'Vernieuwen'), icon: const Icon(Icons.refresh_rounded)),
            PopupMenuButton<String>(
"""
s = replace_once(s, old_actions, new_actions, 'company quick actions')

s = s.replace("button: _ct(context, 'Manage sensors', 'إدارة الحساسات', 'Sensoren beheren'),", "button: _ct(context, 'Add sensor', 'إضافة حساس', 'Sensor toevoegen'),", 1)
s = s.replace("onManage: () => _openManager(const VetAdminSensorCenter(), _ct(context, 'Sensors & devices', 'الحساسات والأجهزة', 'Sensoren & apparaten')),
", "onManage: _addSensor,\n", 1)
p.write_text(s, encoding='utf-8')


# ---------------------------------------------------------------------------
# 4) Admin web layout: stop iPhone Safari/accessibility text scaling from making
#    management pages enormous. Keep a fixed professional admin scale.
# ---------------------------------------------------------------------------
p = Path('lib/admin/admin_entry.dart')
s = p.read_text(encoding='utf-8')
if 'builder: (context, child) {' not in s:
    anchor = """        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
"""
    builder = anchor + """        builder: (context, child) {
          final media = MediaQuery.of(context);
          return MediaQuery(
            data: media.copyWith(textScaler: const TextScaler.linear(1.0)),
            child: child ?? const SizedBox.shrink(),
          );
        },
"""
    if anchor not in s:
        raise SystemExit('V62: admin text-scale anchor missing')
    # Only patch the VetAdminApp MaterialApp: this is the final occurrence in file.
    pos = s.rfind(anchor)
    s = s[:pos] + builder + s[pos + len(anchor):]
p.write_text(s, encoding='utf-8')


# ---------------------------------------------------------------------------
# 5) Dashboard destination naming: make Accounts unmistakable.
# ---------------------------------------------------------------------------
p = Path('lib/admin/admin_dashboard.dart')
s = p.read_text(encoding='utf-8')
s = s.replace(
    "_AdminDestination(Icons.admin_panel_settings_rounded, _at(context, 'Accounts & staff', 'الحسابات والموظفون', 'Accounts & medewerkers'))",
    "_AdminDestination(Icons.manage_accounts_rounded, _at(context, 'Accounts & users', 'الحسابات والمستخدمون', 'Accounts & gebruikers'))",
)
p.write_text(s, encoding='utf-8')

for path, markers in {
    'lib/admin/admin_account_center.dart': ['VetAdminAccountControlV2()', 'length: 3'],
    'lib/admin/admin_staff_center.dart': ["value: 'manager'", "value: 'assistant_manager'"],
    'lib/admin/admin_company_center.dart': ['Future<void> _addSensor()', 'Icons.manage_accounts_rounded', 'appBar: AppBar(title: Text(title))'],
    'lib/admin/admin_entry.dart': ['TextScaler.linear(1.0)'],
}.items():
    text = Path(path).read_text(encoding='utf-8')
    for marker in markers:
        if marker not in text:
            raise SystemExit(f'V62 verification missing {marker} in {path}')

print('Vet AI V62 applied: compact admin routes with back buttons, account/email/password controls, manager roles, and direct customer sensor creation')
