from pathlib import Path

p = Path('lib/admin/admin_dashboard.dart')
s = p.read_text(encoding='utf-8')
old = '        body: RepaintBoundary(child: _page()),\n'
new = '        body: _page(),\n'
if old in s:
    s = s.replace(old, new, 1)
elif new not in s:
    raise SystemExit('V65a: admin mobile body anchor missing')
p.write_text(s, encoding='utf-8')
print('Vet AI V65a applied: admin mobile scaffold normalized for incoming-call layer')
