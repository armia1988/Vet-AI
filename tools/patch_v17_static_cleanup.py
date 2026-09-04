from pathlib import Path

# 1) Keep legal section bullet support but explicitly suppress the current
# analyzer warning until bullet content is actually used by a page.
legal = Path('lib/legal/vet_legal_pages.dart')
s = legal.read_text()
ignore = '// ignore_for_file: unused_element_parameter\n\n'
if not s.startswith('// ignore_for_file: unused_element_parameter'):
    s = ignore + s
legal.write_text(s)

# 2) Flutter 3.47 deprecates value on DropdownButtonFormField.
rules = Path('lib/monitoring/sensor_alert_rules.dart')
s = rules.read_text()
old = 'DropdownButtonFormField<String>(value: metric,'
new = 'DropdownButtonFormField<String>(initialValue: metric,'
if old not in s and new not in s:
    raise SystemExit('sensor DropdownButtonFormField target not found')
s = s.replace(old, new, 1)
rules.write_text(s)

# 3) VetOperations only uses VetBackend types/members; Supabase import is redundant.
ops = Path('lib/services/vet_operations.dart')
s = ops.read_text()
s = s.replace("import 'package:supabase_flutter/supabase_flutter.dart';\n\n", '', 1)
ops.write_text(s)

# 4) flutter/services already exports Uint8List for the uses in V5, so the
# direct dart:typed_data import is redundant under Flutter 3.47.
app = Path('lib/v5_app.dart')
s = app.read_text()
s = s.replace("import 'dart:typed_data';\n\n", '', 1)
app.write_text(s)

print('V17 static-analysis cleanup applied')
