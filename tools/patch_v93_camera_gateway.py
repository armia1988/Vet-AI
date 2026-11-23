from pathlib import Path

# V93: real always-on local camera gateway architecture.
# Adds gateway management/status UI next to the camera center and alert center.

camera = Path('lib/monitoring/camera_center_page.dart')
s = camera.read_text(encoding='utf-8')

gateway_import = "import 'camera_gateway_page.dart';\n"
alert_import = "import 'camera_alert_center_page.dart';\n"
if gateway_import not in s:
    assert alert_import in s, 'V93 camera alert import anchor missing'
    s = s.replace(alert_import, alert_import + gateway_import, 1)

if 'CameraGatewayPage(farmId: widget.farmId)' not in s:
    anchor = """          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => CameraAlertCenterPage(farmId: widget.farmId)),
            ),
            icon: const Icon(Icons.notifications_active_rounded),
            tooltip: 'Camera alerts',
          ),
"""
    insert = anchor + """          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => CameraGatewayPage(farmId: widget.farmId)),
            ),
            icon: const Icon(Icons.hub_rounded),
            tooltip: 'Local camera gateway',
          ),
"""
    assert anchor in s, 'V93 Camera Center alert action anchor missing'
    s = s.replace(anchor, insert, 1)

camera.write_text(s, encoding='utf-8')

app = Path('lib/v5_app.dart')
s = app.read_text(encoding='utf-8')
app_gateway_import = "import 'monitoring/camera_gateway_page.dart';\n"
app_alert_import = "import 'monitoring/camera_alert_center_page.dart';\n"
if app_gateway_import not in s:
    assert app_alert_import in s, 'V93 v5 alert import anchor missing'
    s = s.replace(app_alert_import, app_alert_import + app_gateway_import, 1)

if "'Local Camera Gateway'" not in s or 'CameraGatewayPage(farmId: farmId)' not in s:
    anchor = """            OutlinedButton.icon(
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
    insert = anchor + """            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CameraGatewayPage(farmId: farmId),
                ),
              ),
              icon: const Icon(Icons.hub_rounded, size: 25),
              label: Text(
                tr(
                  context,
                  'Local Camera Gateway',
                  'بوابة الكاميرات المحلية',
                  'Lokale cameragateway',
                ),
              ),
            ),
            const SizedBox(height: 10),
"""
    assert anchor in s, 'V93 v5 Camera Alerts button anchor missing'
    s = s.replace(anchor, insert, 1)

app.write_text(s, encoding='utf-8')

checks = {
    'lib/monitoring/camera_gateway_page.dart': [
        'class CameraGatewayPage',
        "device_type': 'camera_gateway'",
        "from('camera_gateway_status')",
        "device_secret_hash': tokenHash",
        'DateTime.now().toUtc().difference',
        '24/7 camera monitoring needs an always-on device',
    ],
    'lib/monitoring/camera_center_page.dart': [
        "import 'camera_gateway_page.dart';",
        'CameraGatewayPage(farmId: widget.farmId)',
        "tooltip: 'Local camera gateway'",
    ],
    'lib/v5_app.dart': [
        "import 'monitoring/camera_gateway_page.dart';",
        'CameraGatewayPage(farmId: farmId)',
        "'Local Camera Gateway'",
        "'بوابة الكاميرات المحلية'",
    ],
    'supabase/functions/camera-gateway-ingest/index.ts': [
        'gateway_device_token',
        'device_secret_hash',
        'camera_gateway_status',
        'thermal_alert_threshold_c',
        'vet-ai-apns-push',
    ],
    'tools/vet_ai_camera_gateway.py': [
        'CreatePullPointSubscription',
        'PullMessages',
        'camera-gateway-ingest',
        'thermal_rule_sample',
        'The phone is not part of the monitoring path',
    ],
}
for path, markers in checks.items():
    text = Path(path).read_text(encoding='utf-8')
    for marker in markers:
        if marker not in text:
            raise SystemExit(f'V93 verification missing in {path}: {marker}')

print('Vet AI V93 applied: authenticated always-on local camera gateway, 24/7 ONVIF event forwarding, thermal threshold forwarding and live gateway status')
