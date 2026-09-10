from pathlib import Path

p = Path('lib/monitoring/camera_center_page.dart')
s = p.read_text()

if "import 'camera_control_page.dart';" not in s:
    anchor = "import '../services/vet_backend.dart';\n"
    assert anchor in s, 'V85 import anchor missing'
    s = s.replace(anchor, anchor + "import 'camera_control_page.dart';\n", 1)

old = """        final key = (caps['credential_key'] ?? '').toString().trim();
        final password = key.isEmpty ? '' : (await _secureStorage.read(key: key) ?? '');
        result.add(
"""
new = """        final uid = (row['device_uid'] ?? '').toString();
        final configuredKey = (caps['credential_key'] ?? '').toString().trim();
        final key = configuredKey.isEmpty ? 'vetai.camera.$uid.password' : configuredKey;
        final password = await _secureStorage.read(key: key) ?? '';
        result.add(
"""
if old in s:
    s = s.replace(old, new, 1)

old = """            uid: (row['device_uid'] ?? '').toString(),
            name: (caps['camera_name'] ?? row['controller_model'] ?? 'IP Camera').toString(),
"""
new = """            uid: uid,
            name: (caps['camera_name'] ?? row['controller_model'] ?? 'IP Camera').toString(),
"""
if old in s:
    s = s.replace(old, new, 1)

old = """            thermal: type == 'thermal_camera' || caps['thermal'] == true,
            host: (caps['host'] ?? '').toString(),
"""
new = """            thermal: type == 'thermal_camera' || caps['thermal'] == true,
            host: (caps['host'] ?? '').toString(),
            httpPort: int.tryParse((caps['http_port'] ?? '80').toString()) ?? 80,
"""
assert old in s or 'httpPort:' in s, 'V85 camera load anchor missing'
if old in s:
    s = s.replace(old, new, 1)

if 'Future<void> _cameraControls(_CameraDevice camera)' not in s:
    anchor = "  void _cameraInfo(_CameraDevice camera) {\n"
    assert anchor in s, 'V85 camera info anchor missing'
    method = """  Future<void> _cameraControls(_CameraDevice camera) async {
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
        builder: (_) => CameraControlPage(
          cameraName: camera.name,
          host: camera.host,
          httpPort: camera.httpPort,
          username: camera.username,
          password: camera.password,
        ),
      ),
    );
  }

"""
    s = s.replace(anchor, method + anchor, 1)

old = """              onPressed: selected == null ? null : () => _cameraInfo(selected),
              color: Colors.white,
              disabledColor: Colors.white24,
              icon: const Icon(Icons.tune_rounded),
              tooltip: 'Camera settings',
"""
new = """              onPressed: selected == null ? null : () => _cameraControls(selected),
              color: Colors.white,
              disabledColor: Colors.white24,
              icon: const Icon(Icons.control_camera_rounded),
              tooltip: 'Camera controls',
"""
assert old in s or "_cameraControls(selected)" in s, 'V85 toolbar anchor missing'
if old in s:
    s = s.replace(old, new, 1)

old = """    required this.thermal,
    required this.host,
  });
"""
new = """    required this.thermal,
    required this.host,
    required this.httpPort,
  });
"""
assert old in s or 'required this.httpPort' in s, 'V85 constructor anchor missing'
if old in s:
    s = s.replace(old, new, 1)

old = """  final bool thermal;
  final String host;

  String get authenticatedUri {
"""
new = """  final bool thermal;
  final String host;
  final int httpPort;

  String get authenticatedUri {
"""
assert old in s or 'final int httpPort;' in s, 'V85 field anchor missing'
if old in s:
    s = s.replace(old, new, 1)

assert "import 'camera_control_page.dart';" in s
assert 'Future<void> _cameraControls(_CameraDevice camera)' in s
assert "_cameraControls(selected)" in s
assert 'final int httpPort;' in s
assert "vetai.camera.$uid.password" in s

p.write_text(s)
print('V85 ONVIF PTZ/capability controls integrated')
