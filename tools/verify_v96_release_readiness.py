from pathlib import Path
import plistlib

# V96 release-readiness guard.
# This runs after the production patch chain and before any signed Codemagic IPA.

required_files = [
    'lib/monitoring/camera_connection_service.dart',
    'lib/monitoring/camera_stream_profile_service.dart',
    'lib/monitoring/camera_center_page.dart',
    'lib/monitoring/camera_intelligence_page.dart',
    'lib/monitoring/camera_gateway_page.dart',
    'lib/monitoring/camera_alert_center_page.dart',
    'tools/vet_ai_camera_gateway.py',
    'tools/patch_v95a_materialized_idempotency.py',
    'codemagic.yaml',
]
for path in required_files:
    if not Path(path).exists():
        raise SystemExit(f'V96 missing required release file: {path}')

camera_markers = {
    'lib/monitoring/camera_stream_profile_service.dart': [
        'class CameraStreamProfileService',
        'GetProfiles',
        'GetStreamUri',
    ],
    'lib/monitoring/camera_center_page.dart': [
        "qualityMode = 'auto'",
        'addAutomaticKeepAlives: false',
        'autoPlay: widget.active',
        'wallActive = false',
        '_discoverMissingStreamProfiles',
        'CameraGatewayPage(farmId: widget.farmId)',
        'CameraAlertCenterPage(farmId: widget.farmId)',
    ],
    'lib/monitoring/camera_intelligence_page.dart': [
        'eventsReconnecting',
        'Camera-supported modules',
    ],
    'lib/monitoring/camera_gateway_page.dart': [
        'Per-camera health',
        'List<String>.generate',
    ],
    'lib/monitoring/onvif_analytics_events_service.dart': [
        'GetSupportedAnalyticsModules',
        'renewPullPointSubscription',
        'xmlns:wsa',
    ],
    'tools/vet_ai_camera_gateway.py': [
        'AGENT_VERSION = "0.2.0-v94"',
        'RenewRequest',
        'event_dedupe_seconds',
        'subscription_renewals',
    ],
}
for path, markers in camera_markers.items():
    text = Path(path).read_text(encoding='utf-8')
    for marker in markers:
        if marker not in text:
            raise SystemExit(f'V96 camera release marker missing: {path} / {marker}')

codemagic = Path('codemagic.yaml').read_text(encoding='utf-8')
required_patches = [
    'patch_v82_camera_live_digest.py',
    'patch_v83_professional_camera_center.py',
    'patch_v84_onvif_network_discovery.py',
    'patch_v85_onvif_ptz_controls.py',
    'patch_v87_camera_intelligence.py',
    'patch_v90_camera_alert_persistence.py',
    'patch_v91_camera_alert_hardening.py',
    'patch_v92_camera_alert_center.py',
    'patch_v93_camera_gateway.py',
    'patch_v93a_camera_gateway_compile_fix.py',
    'patch_v95_camera_wall_performance.py',
    'patch_v95a_materialized_idempotency.py',
]
for patch in required_patches:
    if patch not in codemagic:
        raise SystemExit(f'V96 Codemagic production chain missing: {patch}')

for marker in [
    'bundle_identifier: com.vetai.app',
    'distribution_type: app_store',
    'app_store_connect: Codemagic Key',
    'flutter build ipa --release',
    '-t lib/main_v2.dart',
    'xcode-project use-profiles',
    'verify_v96_release_readiness.py',
]:
    if marker not in codemagic:
        raise SystemExit(f'V96 Codemagic release marker missing: {marker}')

plist_path = Path('ios/Runner/Info.plist')
if plist_path.exists():
    with plist_path.open('rb') as f:
        plist = plistlib.load(f)
    if not str(plist.get('NSCameraUsageDescription', '')).strip():
        raise SystemExit('V96 iOS camera usage description missing')
    if not str(plist.get('NSMicrophoneUsageDescription', '')).strip():
        raise SystemExit('V96 iOS microphone usage description missing')
    if not str(plist.get('NSLocalNetworkUsageDescription', '')).strip():
        raise SystemExit('V96 iOS local-network usage description missing')
    ats = plist.get('NSAppTransportSecurity') or {}
    if ats.get('NSAllowsArbitraryLoads') is not True:
        raise SystemExit('V96 iOS RTSP/local camera ATS allowance missing')

print('Vet AI V96 release readiness verified: production camera chain, iOS permissions, signing configuration and release target are aligned')
