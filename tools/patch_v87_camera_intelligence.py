from pathlib import Path

p = Path('lib/monitoring/camera_center_page.dart')
s = p.read_text()

if "import 'camera_intelligence_page.dart';" not in s:
    anchor = "import 'camera_control_page.dart';\n"
    assert anchor in s, 'V87 import anchor missing'
    s = s.replace(anchor, anchor + "import 'camera_intelligence_page.dart';\n", 1)

if 'Future<void> _cameraIntelligence(_CameraDevice camera)' not in s:
    anchor = "  Future<void> _cameraControls(_CameraDevice camera) async {\n"
    assert anchor in s, 'V87 controls anchor missing'
    method = """  Future<void> _cameraIntelligence(_CameraDevice camera) async {
    if (camera.host.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera host is missing. Verify this camera again.')),
      );
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => CameraIntelligencePage(
          cameraName: camera.name,
          host: camera.host,
          httpPort: camera.httpPort,
          username: camera.username,
          password: camera.password,
          vendor: camera.vendor,
        ),
      ),
    );
  }

"""
    s = s.replace(anchor, method + anchor, 1)

old = """            IconButton(
              onPressed: selected == null ? null : () => _cameraControls(selected),
              color: Colors.white,
              disabledColor: Colors.white24,
              icon: const Icon(Icons.control_camera_rounded),
              tooltip: 'Camera controls',
            ),
            const Spacer(),
"""
new = """            IconButton(
              onPressed: selected == null ? null : () => _cameraControls(selected),
              color: Colors.white,
              disabledColor: Colors.white24,
              icon: const Icon(Icons.control_camera_rounded),
              tooltip: 'Camera controls',
            ),
            IconButton(
              onPressed: selected == null ? null : () => _cameraIntelligence(selected),
              color: Colors.white,
              disabledColor: Colors.white24,
              icon: const Icon(Icons.psychology_alt_rounded),
              tooltip: 'Capabilities / Thermal / AI',
            ),
            const Spacer(),
"""
assert old in s or '_cameraIntelligence(selected)' in s, 'V87 toolbar anchor missing'
if old in s:
    s = s.replace(old, new, 1)

assert "import 'camera_intelligence_page.dart';" in s
assert 'Future<void> _cameraIntelligence(_CameraDevice camera)' in s
assert '_cameraIntelligence(selected)' in s

p.write_text(s)
print('V87 camera intelligence integrated')
