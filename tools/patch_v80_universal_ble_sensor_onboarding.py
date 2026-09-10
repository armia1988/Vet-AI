from pathlib import Path
import plistlib
import runpy

# V80: Universal BLE-first sensor onboarding.
# The mobile app discovers a Vet AI-compatible sensor locally, registers it
# securely with the existing provisioning Edge Function, then sends Wi-Fi/cloud
# credentials over BLE. After that the device runs independently through its
# internet backhaul.

# ---------------------------------------------------------------------------
# 1) Fix the onboarding page to use the canonical production Supabase URL.
# ---------------------------------------------------------------------------
p = Path('lib/monitoring/ble_sensor_onboarding_page.dart')
s = p.read_text(encoding='utf-8')
if "import '../config/supabase_config.dart';" not in s:
    anchor = "import '../i18n/vet_locale.dart';\n"
    if anchor not in s:
        raise SystemExit('V80: BLE page import anchor missing')
    s = s.replace(anchor, "import '../config/supabase_config.dart';\n" + anchor, 1)
s = s.replace(
    'supabaseUrl: VetBackend.instance.client.rest.url,',
    'supabaseUrl: SupabaseConfig.url,',
)
p.write_text(s, encoding='utf-8')

# ---------------------------------------------------------------------------
# 2) Add the one-tap Bluetooth onboarding entry to the customer Sensors panel.
# ---------------------------------------------------------------------------
p = Path('lib/v5_app.dart')
s = p.read_text(encoding='utf-8')
if "import 'monitoring/ble_sensor_onboarding_page.dart';" not in s:
    anchor = "import 'monitoring/sensor_alert_rules.dart';\n"
    if anchor not in s:
        raise SystemExit('V80: v5 sensor import anchor missing')
    s = s.replace(anchor, anchor + "import 'monitoring/ble_sensor_onboarding_page.dart';\n", 1)

if 'VetBleSensorOnboardingPage(' not in s:
    anchor = """            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SensorAlertRulesScreen(farmId: farmId),
                ),
              ),
"""
    insert = """            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () async {
                final connected = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VetBleSensorOnboardingPage(
                      farmId: farmId,
                      onProvisioned: _retry,
                    ),
                  ),
                );
                if (connected == true && mounted) _retry();
              },
              icon: const Icon(Icons.bluetooth_searching_rounded, size: 29),
              label: Text(
                tr(
                  context,
                  'Connect sensor with Bluetooth',
                  'ربط حساس بالبلوتوث',
                  'Sensor koppelen via Bluetooth',
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
        raise SystemExit('V80: sensors panel button anchor missing')
    s = s.replace(anchor, insert, 1)
p.write_text(s, encoding='utf-8')

# ---------------------------------------------------------------------------
# 3) Native Bluetooth privacy/permission declarations on generated projects.
# These projects are regenerated in GitHub Actions/Codemagic, so permissions
# must be applied here rather than only editing transient ios/android files.
# ---------------------------------------------------------------------------
ios_plist = Path('ios/Runner/Info.plist')
if ios_plist.exists():
    with ios_plist.open('rb') as f:
        data = plistlib.load(f)
    data['NSBluetoothAlwaysUsageDescription'] = (
        'Vet AI uses Bluetooth to find and securely configure nearby farm sensors.'
    )
    # Kept for compatibility with older iOS versions supported by plugins.
    data['NSBluetoothPeripheralUsageDescription'] = (
        'Vet AI uses Bluetooth to connect nearby farm sensors.'
    )
    with ios_plist.open('wb') as f:
        plistlib.dump(data, f, sort_keys=False)
else:
    print('V80: iOS project not present; Bluetooth plist step skipped for web build')

android_manifest = Path('android/app/src/main/AndroidManifest.xml')
if android_manifest.exists():
    a = android_manifest.read_text(encoding='utf-8')
    marker = '<application'
    if marker not in a:
        raise SystemExit('V80: Android application anchor missing')
    permissions = """    <uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
    <uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30" />
"""
    if 'android.permission.BLUETOOTH_SCAN' not in a:
        idx = a.index(marker)
        a = a[:idx] + permissions + a[idx:]
    android_manifest.write_text(a, encoding='utf-8')
else:
    print('V80: Android project not present; Bluetooth manifest step skipped for web build')

# ---------------------------------------------------------------------------
# 4) Build-time invariants: fail early if BLE onboarding gets disconnected from
# the real backend or accidentally becomes a demo-only UI.
# ---------------------------------------------------------------------------
checks = {
    'lib/services/ble_sensor_models.dart': [
        'class VetBleProtocol',
        'protocolVersion = 1',
        'device_token',
        'wifi_ssid',
    ],
    'lib/services/ble_sensor_provisioning_native.dart': [
        'FlutterReactiveBle',
        'scanForDevices',
        'connectToDevice',
        'writeCharacteristicWithResponse',
        'subscribeToCharacteristic',
    ],
    'lib/monitoring/ble_sensor_onboarding_page.dart': [
        "functions.invoke(\n        'provision-sensor-device'",
        'VetBleCloudConfig(',
        'SupabaseConfig.url',
        'Connect sensor',
    ],
    'lib/v5_app.dart': [
        'VetBleSensorOnboardingPage(',
        'Connect sensor with Bluetooth',
    ],
}
for path, markers in checks.items():
    text = Path(path).read_text(encoding='utf-8')
    for marker in markers:
        if marker not in text:
            raise SystemExit(f'V80 verification missing in {path}: {marker}')

print('Vet AI V80 applied: universal BLE discovery, secure provisioning, Wi-Fi/cloud handoff and mobile permissions')

# V81 extends the same Sensors panel with Dahua thermal cameras.
runpy.run_path('tools/patch_v81_dahua_thermal_camera_onboarding.py', run_name='__main__')
