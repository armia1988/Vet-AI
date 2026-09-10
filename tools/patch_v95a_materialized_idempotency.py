from pathlib import Path

# V95a: make the production camera patch chain safe when V95 is already
# materialized in source. V85/V95 can otherwise re-add the same camera
# constructor metadata when the release pipeline reapplies the patch chain.

p = Path('lib/monitoring/camera_center_page.dart')
s = p.read_text(encoding='utf-8')

block = """            httpPort: int.tryParse((caps['http_port'] ?? '80').toString()) ?? 80,
            subStreamUri: (caps['substream_uri'] ?? '').toString().trim(),
            onvif: caps['onvif'] == true,
            capabilities: caps,
"""

# Collapse any adjacent duplicate metadata blocks created by reapplying V85
# then V95 to an already materialized Camera Center source.
while block + block in s:
    s = s.replace(block + block, block, 1)

# Also handle the intermediate V85-only duplicate httpPort form if V95 changes
# in a future patch order.
http_line = "            httpPort: int.tryParse((caps['http_port'] ?? '80').toString()) ?? 80,\n"
while http_line + http_line in s:
    s = s.replace(http_line + http_line, http_line, 1)

p.write_text(s, encoding='utf-8')

text = p.read_text(encoding='utf-8')
if text.count("subStreamUri: (caps['substream_uri'] ?? '').toString().trim(),") != 1:
    raise SystemExit('V95a expected exactly one saved-camera subStreamUri argument')
if text.count("onvif: caps['onvif'] == true,") != 1:
    raise SystemExit('V95a expected exactly one saved-camera onvif argument')
if text.count('capabilities: caps,') != 1:
    raise SystemExit('V95a expected exactly one saved-camera capabilities argument')

print('Vet AI V95a applied: materialized camera source remains safe when production patches are reapplied')
