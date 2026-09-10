from pathlib import Path

# V81: add Dahua thermal camera as a first-class monitoring device.
# The camera is registered in sensor_devices using the existing farm RLS model.
# Sensitive camera passwords are intentionally not persisted.

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
              icon: const Icon(Icons.thermostat_rounded, size: 28),
              label: Text(
                tr(
                  context,
                  'Add Dahua thermal camera',
                  'إضافة كاميرا داهوا حرارية',
                  'Dahua thermische camera toevoegen',
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
        'Add Dahua thermal camera',
    ],
    'lib/monitoring/dahua_thermal_camera_onboarding_page.dart': [
        "device_type': 'thermal_camera'",
        "'vendor': 'Dahua'",
        "onConflict: 'device_uid'",
        "'credentials_storage': 'password_not_stored'",
        'ONVIF + RTSP',
    ],
}
for path, markers in checks.items():
    text = Path(path).read_text(encoding='utf-8')
    for marker in markers:
        if marker not in text:
            raise SystemExit(f'V81 verification missing in {path}: {marker}')

print('Vet AI V81 applied: Dahua thermal camera onboarding added to customer Sensors panel')
