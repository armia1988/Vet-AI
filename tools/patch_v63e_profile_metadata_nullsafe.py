from pathlib import Path
import runpy

p = Path('lib/admin/admin_dashboard.dart')
s = p.read_text(encoding='utf-8')

# V63e: null-safe profile metadata access.
old = """    final metadata = user?.userMetadata;
    final rawName = metadata is Map ? metadata['full_name'] : null;
"""
new = """    final rawName = user?.userMetadata?['full_name'];
"""
if new not in s:
    if old not in s:
        raise SystemExit('V63e profile metadata anchor missing')
    s = s.replace(old, new, 1)

# V63f behavior: keep the selected admin section through browser/app refresh.
if "import 'package:shared_preferences/shared_preferences.dart';" not in s:
    s = s.replace(
        "import 'package:flutter/material.dart';\n",
        "import 'package:flutter/material.dart';\nimport 'package:shared_preferences/shared_preferences.dart';\n",
        1,
    )

if '_restoreAdminSection();' not in s:
    anchor = """    _loadRole();
    unawaited(admin.prewarm());
"""
    if anchor not in s:
        anchor = """    _loadRole();
"""
        if anchor not in s:
            raise SystemExit('V63e admin init anchor missing')
        s = s.replace(anchor, anchor + "    _restoreAdminSection();\n", 1)
    else:
        s = s.replace(anchor, """    _loadRole();
    _restoreAdminSection();
    unawaited(admin.prewarm());
""", 1)

if 'Future<void> _restoreAdminSection()' not in s:
    marker = """  Future<void> _loadRole() async {
"""
    helper = """  Future<void> _restoreAdminSection() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getInt('vet_ai_admin_section');
    if (!mounted || saved == null || saved < 0 || saved >= destinations.length) return;
    setState(() => index = saved);
  }

  void _selectAdminSection(int next) {
    if (next == index) return;
    setState(() => index = next);
    SharedPreferences.getInstance().then(
      (prefs) => prefs.setInt('vet_ai_admin_section', next),
    );
  }

"""
    if marker not in s:
        raise SystemExit('V63e load-role method anchor missing')
    s = s.replace(marker, helper + marker, 1)

s = s.replace(
    """                        setState(() => index = i);
                        Navigator.pop(context);
""",
    """                        _selectAdminSection(i);
                        Navigator.pop(context);
""",
    1,
)
s = s.replace(
    "onTap: () => setState(() => index = i),",
    "onTap: () => _selectAdminSection(i),",
    1,
)

for required in [
    "user?.userMetadata?['full_name']",
    "SharedPreferences.getInstance()",
    "vet_ai_admin_section",
    "_selectAdminSection(i)",
    "_restoreAdminSection();",
]:
    if required not in s:
        raise SystemExit(f'V63e verification missing: {required}')

p.write_text(s, encoding='utf-8')
print('Vet AI V63e applied: null-safe profile metadata and persistent current admin section after refresh')

# Later cross-platform support fixes are chained here so both GitHub Pages and
# Codemagic generated builds receive the exact same chat/call behavior.
runpy.run_path('tools/patch_v64_reliable_support_calls.py', run_name='__main__')
runpy.run_path('tools/patch_v64c_support_chat_whatsapp_behavior.py', run_name='__main__')
runpy.run_path('tools/patch_v64d_support_chat_compile_guard.py', run_name='__main__')
runpy.run_path('tools/patch_v64e_support_agent_async_import.py', run_name='__main__')
runpy.run_path('tools/patch_v65a_admin_scaffold_compat.py', run_name='__main__')
runpy.run_path('tools/patch_v65_support_call_ringing.py', run_name='__main__')
runpy.run_path('tools/patch_v65b_chat_route_call_tones.py', run_name='__main__')
runpy.run_path('tools/patch_v65c_admin_call_layer_balance.py', run_name='__main__')
runpy.run_path('tools/patch_v65_chat_keyboard_audio_stability.py', run_name='__main__')
