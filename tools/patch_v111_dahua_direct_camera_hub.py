from pathlib import Path

# V111: make a selected Dahua/Amcrest camera use its native authenticated API
# and direct RTSP transport instead of requiring ONVIF, route the customer into
# the integrated camera hub, and remove engineering gateway records/actions from
# normal customer-facing camera/sensor screens.

# ---------------------------------------------------------------------------
# 1) Dahua direct transport recovery after V108/V109 have been applied.
# ---------------------------------------------------------------------------
p = Path('lib/monitoring/camera_connection_service.dart')
s = p.read_text(encoding='utf-8')

success_anchor = """    if (!onvifOk && onvifFailure != null && !rtspOk) {
      notes.insert(0, 'ONVIF: $onvifFailure');
    }
    final success = useOnvif && useRtsp
"""
recovery = """    // Dahua direct mode: the native Dahua CGI above authenticates the same
    // camera credentials independently of ONVIF. Some Dahua firmware rejects
    // our lightweight RTSP DESCRIBE probe with 401 while libVLC can negotiate
    // the camera's RTSP Digest challenge correctly. When native Dahua identity
    // authentication succeeded and the RTSP socket is reachable, keep the
    // canonical Dahua stream and let libVLC perform the media authentication.
    final vendorKey = vendorHint.toLowerCase();
    final directDahua = vendorKey == 'dahua' || vendorKey == 'amcrest';
    final nativeIdentityProven = directDahua &&
        deviceInfo != null &&
        (((deviceInfo!['SerialNumber'] ?? '').trim().isNotEmpty) ||
            ((deviceInfo!['Model'] ?? '').trim().isNotEmpty));
    if (useRtsp && !rtspOk && nativeIdentityProven) {
      Socket? directSocket;
      try {
        directSocket = await Socket.connect(
          host,
          rtspPort,
          timeout: const Duration(seconds: 5),
        );
        await directSocket.close();
        rtspOk = true;
        streamUri = 'rtsp://$host:$rtspPort/cam/realmonitor?channel=1&subtype=0';
        notes.removeWhere((entry) => entry.startsWith('RTSP:'));
        notes.add('Dahua direct RTSP ready; media authentication is handled by the player.');
      } catch (e) {
        notes.removeWhere((entry) => entry.startsWith('RTSP:'));
        notes.add('RTSP: Dahua port $rtspPort is not reachable ($e)');
      } finally {
        directSocket?.destroy();
      }
    }

    if (!onvifOk && onvifFailure != null && !rtspOk) {
      notes.insert(0, 'ONVIF: $onvifFailure');
    }
    final success = useOnvif && useRtsp
"""
if 'Dahua direct RTSP ready; media authentication is handled by the player.' not in s:
    if success_anchor not in s:
        raise SystemExit('V111: connection success anchor missing')
    s = s.replace(success_anchor, recovery, 1)
p.write_text(s, encoding='utf-8')

# ---------------------------------------------------------------------------
# 2) Onboarding: selecting/detecting Dahua is RTSP/native, not ONVIF.
# ---------------------------------------------------------------------------
p = Path('lib/monitoring/dahua_thermal_camera_onboarding_page.dart')
s = p.read_text(encoding='utf-8')

# Never send a selected Dahua/Amcrest camera through ONVIF first.
s = s.replace(
    "        useOnvif: protocol.contains('ONVIF'),\n"
    "        useRtsp: protocol.contains('RTSP'),\n"
    "        vendorHint: cameraVendor,\n",
    "        useOnvif: !(cameraVendor == 'dahua' || cameraVendor == 'amcrest') &&\n"
    "            protocol.contains('ONVIF'),\n"
    "        useRtsp: (cameraVendor == 'dahua' || cameraVendor == 'amcrest') ||\n"
    "            protocol.contains('RTSP'),\n"
    "        vendorHint: cameraVendor,\n",
    1,
)
if "useOnvif: !(cameraVendor == 'dahua' || cameraVendor == 'amcrest')" not in s:
    raise SystemExit('V111: direct Dahua connector wiring missing')

# Vendor dropdown must visibly follow the real transport choice.
s = s.replace(
    "                        if (next == 'generic_rtsp') protocol = 'RTSP';\n",
    "                        if (next == 'generic_rtsp' || next == 'dahua' || next == 'amcrest') {\n"
    "                          protocol = 'RTSP';\n"
    "                        }\n"
    "                        if (next == 'generic_onvif') protocol = 'ONVIF';\n",
    1,
)

# LAN discovery: Dahua native port 37777 is enough to select direct mode.
s = s.replace(
    "          cameraVendor = 'dahua';\n          manufacturer.text = 'Dahua';\n",
    "          cameraVendor = 'dahua';\n          manufacturer.text = 'Dahua';\n          protocol = 'RTSP';\n",
    1,
)

# Once a direct vendor succeeds, keep the UI/provisioned capabilities truthful.
state_anchor = """        if (result.rtspOk && !result.onvifOk) protocol = 'RTSP';
        if (result.onvifOk && !result.rtspOk) protocol = 'ONVIF';
"""
state_replacement = """        if (cameraVendor == 'dahua' || cameraVendor == 'amcrest') {
          protocol = 'RTSP';
        } else {
          if (result.rtspOk && !result.onvifOk) protocol = 'RTSP';
          if (result.onvifOk && !result.rtspOk) protocol = 'ONVIF';
        }
"""
if state_anchor in s:
    s = s.replace(state_anchor, state_replacement, 1)
elif "if (cameraVendor == 'dahua' || cameraVendor == 'amcrest')" not in s:
    raise SystemExit('V111: onboarding protocol-state anchor missing')

p.write_text(s, encoding='utf-8')

# ---------------------------------------------------------------------------
# 3) Existing live wall: engineering gateway must not be a customer action.
# ---------------------------------------------------------------------------
p = Path('lib/monitoring/camera_center_page.dart')
s = p.read_text(encoding='utf-8')
s = s.replace("import 'camera_gateway_page.dart';\n", '')
gateway_action = """          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => CameraGatewayPage(farmId: widget.farmId)),
            ),
            icon: const Icon(Icons.hub_rounded),
            tooltip: 'Local camera gateway',
          ),
"""
s = s.replace(gateway_action, '')
if 'Local camera gateway' in s or 'CameraGatewayPage(' in s:
    raise SystemExit('V111: gateway action still exposed in CameraCenterPage')
p.write_text(s, encoding='utf-8')

# ---------------------------------------------------------------------------
# 4) Main app route: Camera Center opens the integrated hub. Hide old gateway
#    button and filter camera/gateway records out of the generic Sensors list.
# ---------------------------------------------------------------------------
p = Path('lib/v5_app.dart')
s = p.read_text(encoding='utf-8')

if "import 'monitoring/camera_hub_page.dart';" not in s:
    import_anchor = "import 'monitoring/camera_center_page.dart';\n"
    if import_anchor not in s:
        raise SystemExit('V111: v5 camera center import anchor missing')
    s = s.replace(import_anchor, import_anchor + "import 'monitoring/camera_hub_page.dart';\n", 1)

s = s.replace("import 'monitoring/camera_gateway_page.dart';\n", '')
s = s.replace('CameraCenterPage(farmId: farmId)', 'CameraHubPage(farmId: farmId)')
if 'CameraHubPage(farmId: farmId)' not in s:
    raise SystemExit('V111: Camera Center was not routed to CameraHubPage')

# Remove the complete Local Camera Gateway button by locating its containing
# OutlinedButton block. This avoids leaving a blank or dead customer control.
while 'Local Camera Gateway' in s:
    marker = s.index('Local Camera Gateway')
    start = s.rfind('            OutlinedButton.icon(', 0, marker)
    if start < 0:
        raise SystemExit('V111: could not locate Local Camera Gateway button start')
    next_widget = s.find('            const SizedBox', marker)
    if next_widget < 0:
        raise SystemExit('V111: could not locate widget after Local Camera Gateway')
    s = s[:start] + s[next_widget:]

# Remove any other direct route reference left behind in the normal V5 UI.
if 'CameraGatewayPage(' in s:
    raise SystemExit('V111: CameraGatewayPage still exposed from V5')

old_loader = """  Future<List<Map<String, dynamic>>> _loadDevices() {
    return VetBackend.instance
        .sensorDevices(farmId)
        .timeout(const Duration(seconds: 12));
  }
"""
new_loader = """  Future<List<Map<String, dynamic>>> _loadDevices() async {
    final rows = await VetBackend.instance
        .sensorDevices(farmId)
        .timeout(const Duration(seconds: 12));
    return rows.where((device) {
      final type = (device['device_type'] ?? '').toString();
      return type != 'camera_gateway' &&
          type != 'ip_camera' &&
          type != 'thermal_camera';
    }).toList();
  }
"""
if old_loader in s:
    s = s.replace(old_loader, new_loader)
elif "type != 'camera_gateway'" not in s:
    raise SystemExit('V111: generic Sensors loader anchor missing')

p.write_text(s, encoding='utf-8')

# ---------------------------------------------------------------------------
# 5) Release guards: no fake gateway UI, and the real hub must exist.
# ---------------------------------------------------------------------------
hub = Path('lib/monitoring/camera_hub_page.dart')
if not hub.exists():
    raise SystemExit('V111: camera_hub_page.dart is missing')
hub_text = hub.read_text(encoding='utf-8')
for required in [
    'class CameraHubPage',
    'CameraCenterPage(farmId: widget.farmId)',
    'CameraAlertCenterPage(farmId: widget.farmId)',
    'DahuaThermalCameraOnboardingPage',
    "label: _t('Live', 'مباشر', 'Live')",
]:
    if required not in hub_text:
        raise SystemExit(f'V111: camera hub verification missing: {required}')

print('V111 Dahua direct camera transport and integrated camera hub applied')
