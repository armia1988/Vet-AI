from pathlib import Path

# V112 can be applied more than once by the historical release patch chain.
# Keep CameraControlPage idempotent by collapsing repeated vendor constructor
# arguments/fields after every V112 application.
p = Path('lib/monitoring/camera_control_page.dart')
s = p.read_text(encoding='utf-8')

while "    this.vendor = '',\n    this.vendor = '',\n" in s:
    s = s.replace(
        "    this.vendor = '',\n    this.vendor = '',\n",
        "    this.vendor = '',\n",
        1,
    )

while "  final String vendor;\n  final String vendor;\n" in s:
    s = s.replace(
        "  final String vendor;\n  final String vendor;\n",
        "  final String vendor;\n",
        1,
    )

# Also handle an accidental blank-line variant without touching any other field.
while "  final String vendor;\n\n  final String vendor;\n" in s:
    s = s.replace(
        "  final String vendor;\n\n  final String vendor;\n",
        "  final String vendor;\n",
        1,
    )

if s.count("  final String vendor;\n") != 1:
    raise SystemExit(
        f'V112c: expected exactly one CameraControlPage vendor field, found {s.count("  final String vendor;" )}'
    )
if s.count("    this.vendor = '',\n") != 1:
    raise SystemExit(
        f'V112c: expected exactly one CameraControlPage vendor constructor argument, found {s.count("    this.vendor = \'\'," )}'
    )

p.write_text(s, encoding='utf-8')
print('V112c CameraControlPage vendor wiring is idempotent')
