from pathlib import Path

# V81: add generic IP camera onboarding as a first-class monitoring device.
# Compatible cameras can use ONVIF and/or RTSP. Standard and thermal cameras
# are supported. Camera passwords are intentionally not persisted.

p = Path('lib/v5_app.dart')
s = p.read_text(encoding='utf-8')

camera_import = "import 'monitoring/dahua_thermal_camera_onboarding_page.dart';\n"
if camera_import not in s:
    anchor = "import 'monitoring/ble_sensor_onboarding_page.dart';\n"
    if anchor not in s:
        raise SystemExit('V81: BLE onboarding import anchor missing')
    s = s.replace(anchor, anchor + camera_import, 1)

if 'DahuaThermalCameraOnboardingPage(' not in s:
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
            OutlinedButton.icon(
              onPressed: () async {
                final added = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DahuaThermalCameraOnboardingPage(
                      farmId: farmId,
                      onSaved: _retry,
                    ),
                  ),
                );
                if (added == true && mounted) _retry();
              },
              icon: const Icon(Icons.videocam_rounded, size: 28),
              label: Text(
                tr(
                  context,
                  'Add camera',
                  'إضافة كاميرا',
                  'Camera toevoegen',
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
        raise SystemExit('V81: sensor rules button anchor missing')
    s = s.replace(anchor, insert, 1)

p.write_text(s, encoding='utf-8')

checks = {
    'lib/v5_app.dart': [
        "import 'monitoring/dahua_thermal_camera_onboarding_page.dart';",
        'DahuaThermalCameraOnboardingPage(',
        'Add camera',
    ],
    'lib/monitoring/dahua_thermal_camera_onboarding_page.dart': [
        "'device_type': isThermal ? 'thermal_camera' : 'ip_camera'",
        "? 'Generic'",
        "'camera_type': cameraType",
        "onConflict: 'device_uid'",
        "'credentials_storage': 'password_not_stored'",
        'ONVIF + RTSP',
        'Hikvision',
    ],
}
for path, markers in checks.items():
    text = Path(path).read_text(encoding='utf-8')
    for marker in markers:
        if marker not in text:
            raise SystemExit(f'V81 verification missing in {path}: {marker}')

print('Vet AI V81 applied: generic ONVIF/RTSP standard and thermal camera onboarding added')
