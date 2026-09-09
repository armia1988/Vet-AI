from pathlib import Path

p = Path('lib/admin/admin_dashboard.dart')
s = p.read_text(encoding='utf-8')

if "import 'package:shared_preferences/shared_preferences.dart';" not in s:
    s = s.replace(
        "import 'package:flutter/material.dart';\n",
        "import 'package:flutter/material.dart';\nimport 'package:shared_preferences/shared_preferences.dart';\n",
        1,
    )

if '_restoreAdminSection();' not in s:
    s = s.replace(
        '''    _loadRole();
    unawaited(admin.prewarm());
''',
        '''    _loadRole();
    _restoreAdminSection();
    unawaited(admin.prewarm());
''',
        1,
    )

if 'Future<void> _restoreAdminSection()' not in s:
    marker = '''  Future<void> _loadRole() async {
'''
    helper = '''  Future<void> _restoreAdminSection() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getInt('vet_ai_admin_section');
    if (!mounted || saved == null || saved < 0 || saved > 14) return;
    setState(() => index = saved);
  }

  void _selectAdminSection(int next) {
    if (next == index) return;
    setState(() => index = next);
    SharedPreferences.getInstance().then((prefs) => prefs.setInt('vet_ai_admin_section', next));
  }

'''
    if marker not in s:
        raise SystemExit('V63f load-role anchor missing')
    s = s.replace(marker, helper + marker, 1)

s = s.replace('setState(() => index = i);\n                        Navigator.pop(context);', '_selectAdminSection(i);\n                        Navigator.pop(context);', 1)
s = s.replace('onTap: () => setState(() => index = i),', 'onTap: () => _selectAdminSection(i),', 1)

for required in [
    "SharedPreferences.getInstance()",
    "vet_ai_admin_section",
    "_selectAdminSection(i)",
    "_restoreAdminSection();",
]:
    if required not in s:
        raise SystemExit(f'V63f verification missing: {required}')

p.write_text(s, encoding='utf-8')
print('Vet AI V63f applied: admin section survives browser/app refresh instead of jumping to overview')
