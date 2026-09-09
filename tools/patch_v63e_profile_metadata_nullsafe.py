from pathlib import Path

p = Path('lib/admin/admin_dashboard.dart')
s = p.read_text(encoding='utf-8')
old = """    final metadata = user?.userMetadata;
    final rawName = metadata is Map ? metadata['full_name'] : null;
"""
new = """    final rawName = user?.userMetadata?['full_name'];
"""
if new not in s:
    if old not in s:
        raise SystemExit('V63e profile metadata anchor missing')
    s = s.replace(old, new, 1)
p.write_text(s, encoding='utf-8')
print('Vet AI V63e applied: null-safe admin profile metadata access')
