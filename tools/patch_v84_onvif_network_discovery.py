from pathlib import Path

# V84: real local-network ONVIF WS-Discovery.
# Adds a professional "Find cameras" flow to camera onboarding. A discovered
# camera fills its real IP/hostname and HTTP port; normal credential verification
# still has to pass before it can be saved.

p = Path('lib/monitoring/dahua_thermal_camera_onboarding_page.dart')
s = p.read_text(encoding='utf-8')

import_line = "import 'onvif_discovery_page.dart';\n"
anchor_import = "import 'camera_connection_service.dart';\n"
if import_line not in s:
    if anchor_import not in s:
        raise SystemExit('V84: camera connection import anchor missing')
    s = s.replace(anchor_import, anchor_import + import_line, 1)

if 'Future<void> _discoverCamera() async {' not in s:
    anchor = '  Future<void> _testConnection() async {\n'
    if anchor not in s:
        raise SystemExit('V84: test connection method anchor missing')
    method = '''  Future<void> _discoverCamera() async {\n    FocusScope.of(context).unfocus();\n    final result = await Navigator.push<Map<String, dynamic>>(\n      context,\n      MaterialPageRoute(builder: (_) => const OnvifDiscoveryPage()),\n    );\n    if (!mounted || result == null) return;\n    final discoveredHost = (result['host'] ?? '').toString().trim();\n    final discoveredPort = result['httpPort'];\n    final discoveredName = (result['name'] ?? '').toString().trim();\n    final discoveredHardware = (result['hardware'] ?? '').toString().trim();\n    setState(() {\n      if (discoveredHost.isNotEmpty) host.text = discoveredHost;\n      if (discoveredPort is int && discoveredPort > 0) port.text = '$discoveredPort';\n      if (discoveredName.isNotEmpty && name.text.trim() == 'IP Camera') name.text = discoveredName;\n      if (discoveredHardware.isNotEmpty && model.text.trim().isEmpty) model.text = discoveredHardware;\n      testedSuccessfully = false;\n      discoveredStreamUri = null;\n      testDetails = null;\n    });\n  }\n\n'''
    s = s.replace(anchor, method + anchor, 1)

if "'Find cameras'" not in s:
    field_anchor = "            _field(host, _dt(context, 'IP address / hostname', 'IP / اسم الشبكة', 'IP-adres / hostnaam'), Icons.lan_outlined, keyboardType: TextInputType.url, hintText: '192.168.1.120'),\n"
    if field_anchor not in s:
        raise SystemExit('V84: host field anchor missing')
    block = '''            SizedBox(\n              width: double.infinity,\n              child: OutlinedButton.icon(\n                onPressed: busy ? null : _discoverCamera,\n                icon: const Icon(Icons.radar_rounded),\n                label: Text(_dt(context, 'Find cameras', 'البحث عن الكاميرات', 'Camera\\'s zoeken')),\n              ),\n            ),\n            const SizedBox(height: 12),\n'''
    s = s.replace(field_anchor, block + field_anchor, 1)

p.write_text(s, encoding='utf-8')

checks = {
    'lib/monitoring/dahua_thermal_camera_onboarding_page.dart': [
        "import 'onvif_discovery_page.dart';",
        'Future<void> _discoverCamera() async {',
        'OnvifDiscoveryPage()',
        "'Find cameras'",
        "'البحث عن الكاميرات'",
    ],
    'lib/monitoring/onvif_discovery_service.dart': [
        "InternetAddress('239.255.255.250')",
        'NetworkVideoTransmitter',
        'ProbeMatch',
        'RawDatagramSocket.bind',
    ],
    'lib/monitoring/onvif_discovery_page.dart': [
        'OnvifDiscoveryService',
        "'Find cameras'",
        'preferredXAddr',
    ],
}
for path, markers in checks.items():
    text = Path(path).read_text(encoding='utf-8')
    for marker in markers:
        if marker not in text:
            raise SystemExit(f'V84 verification missing in {path}: {marker}')

# The dedicated V84 iOS workflow stops after this patch, so apply the current
# camera verification compatibility layer here as well. V105b is idempotent.
for extra in [
    'tools/patch_v105_camera_connection_compat.py',
    'tools/patch_v105b_camera_onboarding_truthful.py',
]:
    if Path(extra).exists():
        code = Path(extra).read_text(encoding='utf-8')
        exec(compile(code, extra, 'exec'), {'__name__': '__main__'})

print('Vet AI V84 applied: discovery integrated and V105 camera verification compatibility active')
