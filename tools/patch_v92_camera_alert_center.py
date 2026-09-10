from pathlib import Path

# V92: farm-wide professional camera alert center.
# Integrates persistent camera alerts into Camera Center and the farm monitoring hub.

camera = Path('lib/monitoring/camera_center_page.dart')
s = camera.read_text(encoding='utf-8')

imp = "import 'camera_alert_center_page.dart';\n"
anchor = "import '../services/vet_backend.dart';\n"
if imp not in s:
    assert anchor in s, 'V92 camera center import anchor missing'
    s = s.replace(anchor, anchor + imp, 1)

if 'CameraAlertCenterPage(farmId: widget.farmId)' not in s:
    anchor = """        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded), tooltip: 'Refresh'),
"""
    insert = """        actions: [
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => CameraAlertCenterPage(farmId: widget.farmId)),
            ),
            icon: const Icon(Icons.notifications_active_rounded),
            tooltip: 'Camera alerts',
          ),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded), tooltip: 'Refresh'),
"""
    assert anchor in s, 'V92 camera center app bar anchor missing'
    s = s.replace(anchor, insert, 1)

camera.write_text(s, encoding='utf-8')

app = Path('lib/v5_app.dart')
s = app.read_text(encoding='utf-8')
alert_import = "import 'monitoring/camera_alert_center_page.dart';\n"
camera_import = "import 'monitoring/camera_center_page.dart';\n"
if alert_import not in s:
    assert camera_import in s, 'V92 v5 camera import anchor missing'
    s = s.replace(camera_import, camera_import + alert_import, 1)

if "'Camera Alerts'" not in s or 'CameraAlertCenterPage(farmId: farmId)' not in s:
    anchor = """            FilledButton.icon(
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
"""
    insert = anchor + """            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CameraAlertCenterPage(farmId: farmId),
                ),
              ),
              icon: const Icon(Icons.notifications_active_rounded, size: 25),
              label: Text(
                tr(
                  context,
                  'Camera Alerts',
                  'تنبيهات الكاميرات',
                  'Camera-alarmen',
                ),
              ),
            ),
            const SizedBox(height: 10),
"""
    assert anchor in s, 'V92 v5 camera center button anchor missing'
    s = s.replace(anchor, insert, 1)

app.write_text(s, encoding='utf-8')

checks = {
    'lib/monitoring/camera_alert_center_page.dart': [
        'class CameraAlertCenterPage',
        "stateFilter = 'open'",
        "riskFilter = 'all'",
        '_unacknowledgedCount',
        '_criticalOpenCount',
        'repository.acknowledge(id)',
        'repository.resolve(id)',
        'repository.reopen(id)',
    ],
    'lib/monitoring/camera_alert_repository.dart': [
        'recentForFarm',
        'Future<void> resolve',
        'Future<void> reopen',
    ],
    'lib/monitoring/camera_center_page.dart': [
        "import 'camera_alert_center_page.dart';",
        'CameraAlertCenterPage(farmId: widget.farmId)',
        "tooltip: 'Camera alerts'",
    ],
    'lib/v5_app.dart': [
        "import 'monitoring/camera_alert_center_page.dart';",
        'CameraAlertCenterPage(farmId: farmId)',
        "'Camera Alerts'",
        "'تنبيهات الكاميرات'",
    ],
}
for path, markers in checks.items():
    text = Path(path).read_text(encoding='utf-8')
    for marker in markers:
        if marker not in text:
            raise SystemExit(f'V92 verification missing in {path}: {marker}')

print('Vet AI V92 applied: farm-wide camera alert center with filtering, acknowledgement, resolve/reopen and Camera Center integration')
