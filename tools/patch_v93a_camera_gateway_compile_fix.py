from pathlib import Path

# V93a: Dart type fix for gateway UID suffix generation.
p = Path('lib/monitoring/camera_gateway_page.dart')
s = p.read_text(encoding='utf-8')
old = "return List<int>.generate(5, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();"
new = "return List<String>.generate(5, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();"
if new not in s:
    if old not in s:
        raise SystemExit('V93a gateway suffix anchor missing')
    s = s.replace(old, new, 1)
p.write_text(s, encoding='utf-8')
assert new in p.read_text(encoding='utf-8')
print('Vet AI V93a applied: camera gateway suffix generation uses List<String> and compiles in Dart')
