from pathlib import Path

# V109 — DMSS-style camera onboarding hardening:
# - vendor-native identity/SN fallback for Dahua/Hikvision families
# - wider ONVIF endpoint/port fallback
# - Dahua/Hikvision SDK-port discovery hints
# - one-tap Connect & Add flow that auto-retrieves serial number
# - never requires ONVIF when a real RTSP stream was verified

# ---------- camera connection service ----------
p = Path('lib/monitoring/camera_connection_service.dart')
s = p.read_text(encoding='utf-8')

if 'String? onvifFailure;' not in s:
    s = s.replace(
        "    final notes = <String>[];\n",
        "    final notes = <String>[];\n    String? onvifFailure;\n",
        1,
    )

old = """      } catch (e) {
        notes.add('ONVIF: ${_cleanError(e)}');
      }
    }

    if (useRtsp) {
"""
new = """      } catch (e) {
        onvifFailure = _cleanError(e);
      }
    }

    // ONVIF is optional in the real world. Dahua/Hikvision-family cameras can
    // expose a perfectly usable RTSP stream while ONVIF is disabled. Try the
    // vendor HTTP API as a truthful identity/SN fallback before RTSP probing.
    if (deviceInfo == null ||
        (deviceInfo['SerialNumber'] ?? '').trim().isEmpty) {
      try {
        final nativeInfo = await _probeVendorIdentity(
          host: host,
          port: httpPort,
          username: username,
          password: password,
          vendorHint: vendorHint,
        );
        if (nativeInfo.isNotEmpty) {
          deviceInfo = <String, String>{
            ...?deviceInfo,
            ...nativeInfo,
          };
        }
      } catch (_) {
        // Identity discovery is best-effort; stream verification below remains
        // the source of truth for whether the camera can actually be used.
      }
    }

    if (useRtsp) {
"""
if old in s:
    s = s.replace(old, new, 1)
elif '_probeVendorIdentity(' not in s:
    raise SystemExit('V109: ONVIF fallback insertion anchor missing')

old = """    final success = (!useOnvif || onvifOk) && (!useRtsp || rtspOk);
"""
new = """    if (!onvifOk && onvifFailure != null && !rtspOk) {
      notes.insert(0, 'ONVIF: $onvifFailure');
    }
    final success = useOnvif && useRtsp
        ? (onvifOk || rtspOk)
        : ((!useOnvif || onvifOk) && (!useRtsp || rtspOk));
"""
if old in s:
    s = s.replace(old, new, 1)
elif 'final success = useOnvif && useRtsp' not in s:
    raise SystemExit('V109: connection success anchor missing')

old = """    final deviceUri = Uri.parse('http://$host:$port/onvif/device_service');

    final deviceInfoBody = _soapEnvelope(
      username: username,
      password: password,
      body: '<tds:GetDeviceInformation xmlns:tds=\"http://www.onvif.org/ver10/device/wsdl\"/>',
    );
    final infoResponse = await _postSoap(
      deviceUri,
      deviceInfoBody,
      'http://www.onvif.org/ver10/device/wsdl/GetDeviceInformation',
      username,
      password,
    );
    _throwOnSoapFault(infoResponse);
"""
new = """    final deviceInfoBody = _soapEnvelope(
      username: username,
      password: password,
      body: '<tds:GetDeviceInformation xmlns:tds=\"http://www.onvif.org/ver10/device/wsdl\"/>',
    );
    final candidatePorts = <int>{port, 80, 8080, 8899, 443}.toList();
    final candidatePaths = <String>[
      '/onvif/device_service',
      '/onvif/device_service/',
      '/onvif/Device_service',
      '/onvif/',
    ];
    late Uri deviceUri;
    late String infoResponse;
    Object? lastOnvifError;
    var connected = false;

    for (final candidatePort in candidatePorts) {
      final scheme = candidatePort == 443 ? 'https' : 'http';
      for (final path in candidatePaths) {
        final candidate = Uri.parse(
          '$scheme://$host:$candidatePort$path',
        );
        try {
          final response = await _postSoap(
            candidate,
            deviceInfoBody,
            'http://www.onvif.org/ver10/device/wsdl/GetDeviceInformation',
            username,
            password,
          );
          _throwOnSoapFault(response);
          deviceUri = candidate;
          infoResponse = response;
          connected = true;
          break;
        } catch (e) {
          lastOnvifError = e;
        }
      }
      if (connected) break;
    }
    if (!connected) {
      throw lastOnvifError ??
          const HttpException('No compatible ONVIF device service answered');
    }
"""
if old in s:
    s = s.replace(old, new, 1)
elif "candidatePaths = <String>[" not in s:
    raise SystemExit('V109: ONVIF URI anchor missing')

s = s.replace(
    "      final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);\n",
    "      final client = HttpClient()\n"
    "        ..connectionTimeout = const Duration(seconds: 5)\n"
    "        ..badCertificateCallback = (_, __, ___) => true;\n",
    1,
)

s = s.replace(
    "    for (final method in const <String>['OPTIONS', 'DESCRIBE']) {\n",
    "    for (final method in const <String>['DESCRIBE']) {\n",
    1,
)

if 'Future<Map<String, String>> _probeVendorIdentity({' not in s:
    anchor = "  Future<_OnvifProbeResult> _probeOnvif({\n"
    methods = r'''  Future<Map<String, String>> _probeVendorIdentity({
    required String host,
    required int port,
    required String username,
    required String password,
    required String vendorHint,
  }) async {
    final hint = vendorHint.toLowerCase();
    final probes = <String>[];

    void add(String profile) {
      if (!probes.contains(profile)) probes.add(profile);
    }

    if (hint == 'dahua' || hint == 'amcrest') add('dahua');
    if (hint == 'hikvision' || hint == 'annke' || hint == 'ezviz') {
      add('hikvision');
    }
    if (hint == 'auto' || hint == 'generic_onvif' || hint == 'generic_rtsp') {
      add('dahua');
      add('hikvision');
    }

    Object? lastError;
    for (final profile in probes) {
      try {
        if (profile == 'dahua') {
          final body = await _authenticatedHttpGet(
            host: host,
            port: port,
            path: '/cgi-bin/magicBox.cgi?action=getSystemInfo',
            username: username,
            password: password,
          );
          final values = <String, String>{};
          for (final line in body.split(RegExp(r'[\r\n]+'))) {
            final i = line.indexOf('=');
            if (i <= 0) continue;
            values[line.substring(0, i).trim().toLowerCase()] =
                line.substring(i + 1).trim();
          }
          final serial = values['serialnumber'] ??
              values['serialno'] ??
              values['sn'];
          final model = values['devicetype'] ??
              values['deviceclass'] ??
              values['machine'];
          if ((serial ?? '').isEmpty && (model ?? '').isEmpty) {
            throw const FormatException('Dahua identity response was not recognized');
          }
          return <String, String>{
            'Manufacturer': hint == 'amcrest' ? 'Amcrest' : 'Dahua',
            if ((model ?? '').isNotEmpty) 'Model': model!,
            if ((serial ?? '').isNotEmpty) 'SerialNumber': serial!,
            if ((values['softwareversion'] ?? '').isNotEmpty)
              'FirmwareVersion': values['softwareversion']!,
            if ((values['hardwareversion'] ?? '').isNotEmpty)
              'HardwareId': values['hardwareversion']!,
          };
        }

        if (profile == 'hikvision') {
          final body = await _authenticatedHttpGet(
            host: host,
            port: port,
            path: '/ISAPI/System/deviceInfo',
            username: username,
            password: password,
          );
          final serial = _vendorXmlValue(body, 'serialNumber');
          final model = _vendorXmlValue(body, 'model');
          final manufacturer = _vendorXmlValue(body, 'manufacturer');
          if ((serial ?? '').isEmpty && (model ?? '').isEmpty) {
            throw const FormatException('Hikvision identity response was not recognized');
          }
          return <String, String>{
            'Manufacturer': (manufacturer ?? '').isNotEmpty
                ? manufacturer!
                : (hint == 'annke'
                    ? 'ANNKE'
                    : hint == 'ezviz'
                        ? 'EZVIZ'
                        : 'Hikvision'),
            if ((model ?? '').isNotEmpty) 'Model': model!,
            if ((serial ?? '').isNotEmpty) 'SerialNumber': serial!,
            if ((_vendorXmlValue(body, 'firmwareVersion') ?? '').isNotEmpty)
              'FirmwareVersion': _vendorXmlValue(body, 'firmwareVersion')!,
            if ((_vendorXmlValue(body, 'hardwareVersion') ?? '').isNotEmpty)
              'HardwareId': _vendorXmlValue(body, 'hardwareVersion')!,
          };
        }
      } catch (e) {
        lastError = e;
      }
    }
    if (lastError != null) throw lastError;
    return const <String, String>{};
  }

  Future<String> _authenticatedHttpGet({
    required String host,
    required int port,
    required String path,
    required String username,
    required String password,
  }) async {
    final scheme = port == 443 ? 'https' : 'http';
    final uri = Uri.parse('$scheme://$host:$port$path');

    Future<_HttpSoapResponse> send(String? authorization) async {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5)
        ..badCertificateCallback = (_, __, ___) => true;
      try {
        final request = await client.getUrl(uri).timeout(const Duration(seconds: 7));
        request.headers.set(HttpHeaders.connectionHeader, 'close');
        request.headers.set(HttpHeaders.acceptHeader, '*/*');
        if (authorization != null) {
          request.headers.set(HttpHeaders.authorizationHeader, authorization);
        }
        final response = await request.close().timeout(const Duration(seconds: 8));
        final text = await utf8.decoder.bind(response).join();
        return _HttpSoapResponse(
          response.statusCode,
          text,
          response.headers.value(HttpHeaders.wwwAuthenticateHeader),
        );
      } finally {
        client.close(force: true);
      }
    }

    var response = await send(null);
    if (response.statusCode == HttpStatus.unauthorized) {
      final challenge = response.wwwAuthenticate ?? '';
      if (challenge.isEmpty) {
        throw HttpException('HTTP 401 authentication challenge missing', uri: uri);
      }
      String? authorization;
      final lower = challenge.toLowerCase();
      if (lower.contains('digest')) {
        final digest = challenge.substring(lower.indexOf('digest'));
        final digestUri = uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
        authorization = _httpDigestAuthorization(
          challenge: digest,
          username: username,
          password: password,
          method: 'GET',
          uri: digestUri.isEmpty ? '/' : digestUri,
        );
      } else if (lower.contains('basic')) {
        authorization =
            'Basic ${base64Encode(utf8.encode('$username:$password'))}';
      }
      if (authorization == null) {
        throw HttpException('Unsupported HTTP authentication scheme', uri: uri);
      }
      response = await send(authorization);
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('HTTP ${response.statusCode}', uri: uri);
    }
    return response.body;
  }

  String? _vendorXmlValue(String body, String tag) {
    final match = RegExp(
      '<(?:\\w+:)?${RegExp.escape(tag)}\\b[^>]*>([^<]*)</(?:\\w+:)?${RegExp.escape(tag)}>',
      caseSensitive: false,
    ).firstMatch(body);
    final value = match?.group(1)?.trim();
    return value == null || value.isEmpty ? null : _xmlUnescape(value);
  }

'''
    if anchor not in s:
        raise SystemExit('V109: vendor identity insertion anchor missing')
    s = s.replace(anchor, methods + anchor, 1)

p.write_text(s, encoding='utf-8')

# ---------- LAN discovery ----------
p = Path('lib/monitoring/onvif_discovery_service.dart')
s = p.read_text(encoding='utf-8')

s = s.replace(
    "static const List<int> _candidatePorts = <int>[80, 443, 554, 8000, 8080, 8899];",
    "static const List<int> _candidatePorts = <int>[80, 443, 554, 37777, 8000, 8080, 8899];",
    1,
)
s = s.replace(
    "open.contains(554) || open.contains(8000) || open.contains(8899);",
    "open.contains(554) || open.contains(37777) || open.contains(8000) || open.contains(8899);",
    1,
)
p.write_text(s, encoding='utf-8')

# ---------- onboarding: auto vendor + auto SN + one-tap add ----------
p = Path('lib/monitoring/dahua_thermal_camera_onboarding_page.dart')
s = p.read_text(encoding='utf-8')

old = """    final discoveredHardware = (result['hardware'] ?? '').toString().trim();
    setState(() {
      if (discoveredHost.isNotEmpty) host.text = discoveredHost;
"""
new = """    final discoveredHardware = (result['hardware'] ?? '').toString().trim();
    final openPorts = List<int>.from(result['openPorts'] as List? ?? const <int>[]);
    setState(() {
      if (discoveredHost.isNotEmpty) host.text = discoveredHost;
      if (cameraVendor == 'auto') {
        if (openPorts.contains(37777)) {
          cameraVendor = 'dahua';
          manufacturer.text = 'Dahua';
        } else if (openPorts.contains(8000)) {
          cameraVendor = 'hikvision';
          manufacturer.text = 'Hikvision';
        } else {
          final inferred = _vendorFromManufacturer(discoveredHardware);
          if (inferred != 'auto') {
            cameraVendor = inferred;
            manufacturer.text = _vendorDisplayName(inferred);
          }
        }
      }
"""
if old in s:
    s = s.replace(old, new, 1)
elif "openPorts.contains(37777)" not in s:
    raise SystemExit('V109: discovery vendor inference anchor missing')

s = s.replace(
    "_dt(context, 'Serial number (optional)', 'السيريال (اختياري)', 'Serienummer (optioneel)')",
    "_dt(context, 'Serial number (automatic)', 'الرقم التسلسلي (تلقائي)', 'Serienummer (automatisch)')",
    1,
)

if 'Future<void> _connectAndAdd() async {' not in s:
    anchor = "  Future<void> _save() async {\n"
    helper = """  Future<void> _connectAndAdd() async {
    if (busy) return;
    await _testConnection();
    if (!mounted || !testedSuccessfully) return;
    await _save();
  }

"""
    if anchor not in s:
        raise SystemExit('V109: connect-and-add insertion anchor missing')
    s = s.replace(anchor, helper + anchor, 1)

if "'remote_identifier':" not in s:
    s = s.replace(
        "            'serial_number': serial.text.trim().isEmpty ? null : serial.text.trim(),\n",
        "            'serial_number': serial.text.trim().isEmpty ? null : serial.text.trim(),\n"
        "            'remote_identifier': serial.text.trim().isEmpty ? null : serial.text.trim(),\n"
        "            'remote_transport': 'not_configured',\n",
        1,
    )

old = """            FilledButton.icon(
              onPressed: busy || !testedSuccessfully ? null : _save,
              icon: const Icon(Icons.add_link_rounded),
              label: Text(_dt(context, 'Add connected camera', 'إضافة الكاميرا المتصلة', 'Verbonden camera toevoegen')),
            ),
"""
new = """            FilledButton.icon(
              onPressed: busy ? null : _connectAndAdd,
              icon: busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.video_camera_back_rounded),
              label: Text(_dt(
                context,
                'Connect & add camera',
                'توصيل وإضافة الكاميرا',
                'Camera verbinden en toevoegen',
              )),
            ),
"""
if old in s:
    s = s.replace(old, new, 1)
elif "'Connect & add camera'" not in s:
    raise SystemExit('V109: primary add button anchor missing')

s = s.replace(
    "'Vet AI tests ONVIF and/or RTSP against the camera before it can be added.'",
    "'Search the LAN, choose the camera, enter its login and Vet AI will detect the brand, working stream and serial number automatically.'",
    1,
)
s = s.replace(
    "'يقوم Vet AI باختبار ONVIF و/أو RTSP مع الكاميرا فعليًا قبل السماح بإضافتها.'",
    "'ابحث في الشبكة واختر الكاميرا وأدخل بيانات الدخول، وسيحدد Vet AI الماركة والبث والرقم التسلسلي تلقائيًا.'",
    1,
)
s = s.replace(
    "'Vet AI test ONVIF en/of RTSP echt met de camera voordat deze kan worden toegevoegd.'",
    "'Zoek op het LAN, kies de camera en voer de login in. Vet AI detecteert merk, werkende stream en serienummer automatisch.'",
    1,
)

p.write_text(s, encoding='utf-8')

connection = Path('lib/monitoring/camera_connection_service.dart').read_text(encoding='utf-8')
discovery = Path('lib/monitoring/onvif_discovery_service.dart').read_text(encoding='utf-8')
onboarding = Path('lib/monitoring/dahua_thermal_camera_onboarding_page.dart').read_text(encoding='utf-8')

for token in [
    '_probeVendorIdentity',
    '/cgi-bin/magicBox.cgi?action=getSystemInfo',
    '/ISAPI/System/deviceInfo',
    "candidatePaths = <String>[",
    "['DESCRIBE']",
]:
    if token not in connection:
        raise SystemExit(f'V109 connection verification missing: {token}')
for token in ['37777', '8000']:
    if token not in discovery:
        raise SystemExit(f'V109 discovery verification missing: {token}')
for token in [
    'openPorts.contains(37777)',
    'Serial number (automatic)',
    'Future<void> _connectAndAdd() async',
    "'remote_transport': 'not_configured'",
    'Connect & add camera',
]:
    if token not in onboarding:
        raise SystemExit(f'V109 onboarding verification missing: {token}')

print('V109 DMSS-style camera connect + automatic serial identity applied')
