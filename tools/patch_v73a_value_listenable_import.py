from pathlib import Path

p = Path('lib/support/support_voice_recorder_bar.dart')
s = p.read_text(encoding='utf-8')
foundation = "import 'package:flutter/foundation.dart';\n"
material = "import 'package:flutter/material.dart';\n"
if foundation not in s:
    if material not in s:
        raise SystemExit('V73a: Material import anchor missing')
    s = s.replace(material, foundation + material, 1)
p.write_text(s, encoding='utf-8')

if "ValueListenable<double> level" not in s:
    raise SystemExit('V73a: voice recorder level contract missing')
print('Vet AI V73a applied: ValueListenable foundation import fixed for web/iOS builds')
