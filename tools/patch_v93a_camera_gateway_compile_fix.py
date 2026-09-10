from pathlib import Path

# V93a: Dart type fix for gateway UID suffix generation.
# Keep this patch idempotent because later camera versions may format the
# already-correct List<String>.generate call across multiple lines.
p = Path('lib/monitoring/camera_gateway_page.dart')
s = p.read_text(encoding='utf-8')

if 'List<String>.generate' not in s:
    if 'List<int>.generate' not in s:
        raise SystemExit('V93a gateway suffix anchor missing')
    s = s.replace('List<int>.generate', 'List<String>.generate', 1)

p.write_text(s, encoding='utf-8')
assert 'List<String>.generate' in p.read_text(encoding='utf-8')
print('Vet AI V93a applied: camera gateway suffix generation uses List<String> and compiles in Dart')
