from pathlib import Path

path = Path('lib/v5_app.dart')
text = path.read_text(encoding='utf-8')

import_line = "import 'health/animal_health_center.dart';\n"
import_anchor = "import 'monitoring/camera_gateway_page.dart';\n"
if import_line not in text:
    if import_anchor not in text:
        raise SystemExit('V100 import anchor not found')
    text = text.replace(import_anchor, import_anchor + import_line, 1)

marker = "AnimalHealthCenterPage(farmId: farmId)"
if marker not in text:
    anchor = """            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CameraCenterPage(farmId: farmId),
                ),
              ),
"""
    if anchor not in text:
        raise SystemExit('V100 Camera Center navigation anchor not found')
    button = """            FilledButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AnimalHealthCenterPage(farmId: farmId),
                ),
              ),
              icon: const Icon(Icons.health_and_safety_rounded, size: 27),
              label: Text(
                tr(
                  context,
                  'Farm Health Center',
                  'مركز صحة المزرعة',
                  'Gezondheidscentrum',
                ),
              ),
            ),
            const SizedBox(height: 10),
"""
    text = text.replace(anchor, button + anchor, 1)

if text.count(import_line) != 1:
    raise SystemExit('V100 health center import must exist exactly once')
if text.count(marker) != 1:
    raise SystemExit('V100 health center navigation must exist exactly once')

path.write_text(text, encoding='utf-8')
print('V100 animal health center navigation applied')
