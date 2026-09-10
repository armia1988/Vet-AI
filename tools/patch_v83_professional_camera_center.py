from pathlib import Path

# V83: professional multi-camera monitoring center.
# Adds a first-class Camera Center next to Add camera, with real saved RTSP
# streams, layouts 1/4/6/8/12/16/32, audio selection, reconnect and fullscreen.

p = Path('lib/v5_app.dart')
s = p.read_text(encoding='utf-8')

camera_center_import = "import 'monitoring/camera_center_page.dart';\n"
anchor_import = "import 'monitoring/sensor_alert_rules.dart';\n"
if camera_center_import not in s:
    if anchor_import not in s:
        raise SystemExit('V83: sensor alert rules import anchor missing')
    s = s.replace(anchor_import, anchor_import + camera_center_import, 1)

if 'CameraCenterPage(farmId: farmId)' not in s:
    anchor = """            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SensorAlertRulesScreen(farmId: farmId),
                ),
              ),
"""
    insert = """            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CameraCenterPage(farmId: farmId),
                ),
              ),
              icon: const Icon(Icons.video_camera_back_rounded, size: 27),
              label: Text(
                tr(
                  context,
                  'Camera Center',
                  'مركز الكاميرات',
                  'Cameracentrum',
                ),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SensorAlertRulesScreen(farmId: farmId),
                ),
              ),
"""
    if anchor not in s:
        raise SystemExit('V83: sensor rules button anchor missing')
    s = s.replace(anchor, insert, 1)

p.write_text(s, encoding='utf-8')

checks = {
    'lib/v5_app.dart': [
        "import 'monitoring/camera_center_page.dart';",
        'CameraCenterPage(farmId: farmId)',
        "'Camera Center'",
    ],
    'lib/monitoring/camera_center_page.dart': [
        'static const _layouts = <int>[1, 4, 6, 8, 12, 16, 32];',
        "from('sensor_devices')",
        'FlutterSecureStorage',
        'VlcPlayerController.network',
        'controller.setVolume',
        '_openFullscreen',
        '_reconnect',
    ],
}
for path, markers in checks.items():
    text = Path(path).read_text(encoding='utf-8')
    for marker in markers:
        if marker not in text:
            raise SystemExit(f'V83 verification missing in {path}: {marker}')

print('Vet AI V83 applied: professional multi-camera center with real RTSP wall, audio, layouts and fullscreen')
