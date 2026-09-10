from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    if old not in text:
        raise SystemExit(f'V71: {label} anchor missing')
    return text.replace(old, new, 1)


# ---------------------------------------------------------------------------
# 1) Admin navigation RBAC: do not render a false "permission required" page
# while my_admin_access is still loading. If that RPC is temporarily unavailable,
# derive the same UI capability map from the already server-verified admin role.
# Database RLS/RPC checks remain the final enforcement layer.
# ---------------------------------------------------------------------------
p = Path('lib/admin/admin_dashboard.dart')
s = p.read_text(encoding='utf-8')

field = "  Map<String, bool> capabilities = const {'overview': true};\n"
if 'bool adminAccessResolved = false;' not in s:
    if field not in s:
        raise SystemExit('V71: admin capabilities field missing')
    s = s.replace(field, field + '  bool adminAccessResolved = false;\n', 1)

if 'Map<String, bool> _fallbackCapabilitiesForRole(' not in s:
    marker = '  Future<void> _loadRole() async {\n'
    if marker not in s:
        raise SystemExit('V71: admin role loader missing')
    helper = r'''  Map<String, bool> _fallbackCapabilitiesForRole(String? rawRole) {
    const all = <String>{
      'overview', 'farms', 'customers', 'animals', 'sensors', 'alerts',
      'notifications', 'support', 'billing', 'manage_admins', 'audit',
      'global_search', 'reports', 'system',
    };
    final role = (rawRole ?? '').trim();
    final allowed = switch (role) {
      'super_admin' => all,
      'manager' => <String>{
          'overview', 'farms', 'customers', 'animals', 'sensors', 'alerts',
          'notifications', 'support', 'billing', 'manage_admins', 'audit',
          'global_search', 'reports',
        },
      'assistant_manager' => <String>{
          'overview', 'farms', 'customers', 'animals', 'sensors', 'alerts',
          'notifications', 'support',
        },
      'admin' => <String>{
          'overview', 'farms', 'customers', 'animals', 'sensors', 'alerts',
          'notifications', 'support', 'billing', 'audit', 'global_search',
          'reports',
        },
      'support' => <String>{'overview', 'support', 'customers'},
      'billing' => <String>{'overview', 'billing', 'customers'},
      'operations' => <String>{
          'overview', 'farms', 'customers', 'animals', 'sensors', 'alerts',
          'notifications', 'support',
        },
      _ => <String>{'overview'},
    };
    return <String, bool>{for (final permission in all) permission: allowed.contains(permission)};
  }

'''
    s = s.replace(marker, helper + marker, 1)

old_success = """        if (mounted) {
          setState(() {
            role = access['role']?.toString();
            capabilities = nextCapabilities;
          });
        }
        return;
"""
new_success = """        if (mounted) {
          setState(() {
            role = access['role']?.toString();
            capabilities = nextCapabilities;
            adminAccessResolved = true;
          });
        }
        return;
"""
s = replace_once(s, old_success, new_success, 'admin access success state')

old_fallback = """    final value = await admin.role();
    if (mounted) setState(() => role = value);
  }
"""
new_fallback = """    String? value;
    try {
      value = await admin.role();
    } catch (_) {}
    if (mounted) {
      setState(() {
        role = value;
        capabilities = _fallbackCapabilitiesForRole(value);
        adminAccessResolved = true;
      });
    }
  }
"""
s = replace_once(s, old_fallback, new_fallback, 'admin role fallback')

page_anchor = """  Widget _page() {
    if (!_canOpenPage(index)) {
"""
page_new = """  Widget _page() {
    if (!adminAccessResolved) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_canOpenPage(index)) {
"""
s = replace_once(s, page_anchor, page_new, 'admin permission loading guard')

for marker in [
    'bool adminAccessResolved = false;',
    '_fallbackCapabilitiesForRole',
    'adminAccessResolved = true;',
    'if (!adminAccessResolved)',
]:
    if marker not in s:
        raise SystemExit(f'V71 admin verification missing: {marker}')

p.write_text(s, encoding='utf-8')


# ---------------------------------------------------------------------------
# 2) Voice-note failure diagnostics and short-record handling. The production
# bucket now accepts audio/wav; keep recordings below the minimum as an explicit
# user-facing state instead of silently returning through the send lifecycle.
# ---------------------------------------------------------------------------
p = Path('lib/support/support_voice_note.dart')
s = p.read_text(encoding='utf-8')

old_short = """    if (rawLength < 6400) {
      _chunks.clear();
      return null;
    }
"""
new_short = """    if (rawLength < 3200) {
      _chunks.clear();
      throw StateError('VOICE_RECORDING_TOO_SHORT');
    }
"""
s = replace_once(s, old_short, new_short, 'voice short recording handling')

# Wait a little longer for the browser recorder's final PCM chunk before
# cancelling the stream subscription. Safari can flush the tail asynchronously.
s = s.replace(
    "_streamDone?.future.timeout(const Duration(milliseconds: 900))",
    "_streamDone?.future.timeout(const Duration(milliseconds: 1800))",
    1,
)

for marker in ["VOICE_RECORDING_TOO_SHORT", 'Duration(milliseconds: 1800)']:
    if marker not in s:
        raise SystemExit(f'V71 voice verification missing: {marker}')

p.write_text(s, encoding='utf-8')

print('Vet AI V71 applied: stable support RBAC loading/fallback and production-ready WAV voice-note completion')
