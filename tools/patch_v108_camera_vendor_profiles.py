from pathlib import Path
import subprocess
import sys

# V105b/V107/V108: truthful camera onboarding, resilient RTSP, vendor profiles,
# hidden engineering gateway UI, and approved Vet AI launcher icon recovery.

# ---------------- Camera onboarding ----------------
p = Path('lib/monitoring/dahua_thermal_camera_onboarding_page.dart')
s = p.read_text(encoding='utf-8')

if "String cameraVendor = 'auto';" not in s:
    s = s.replace(
        "  String protocol = 'ONVIF + RTSP';\n",
        "  String protocol = 'ONVIF + RTSP';\n  String cameraVendor = 'auto';\n",
        1,
    )

if "final rtspPath = TextEditingController();" not in s:
    s = s.replace(
        "  final serial = TextEditingController();\n",
        "  final serial = TextEditingController();\n  final rtspPath = TextEditingController();\n",
        1,
    )

s = s.replace(
    "for (final controller in [host, port, rtspPort, username, password])",
    "for (final controller in [host, port, rtspPort, username, password, rtspPath])",
    1,
)

if "    rtspPath.dispose();" not in s:
    s = s.replace("    serial.dispose();\n", "    serial.dispose();\n    rtspPath.dispose();\n", 1)

if "bool verifiedOnvif = false;" not in s:
    s = s.replace(
        "  String? testDetails;\n",
        "  String? testDetails;\n  bool verifiedOnvif = false;\n  bool verifiedRtsp = false;\n",
        1,
    )

needle = '''      testDetails = null;
    });
  }
'''
if needle in s and "verifiedOnvif = false;" not in s[s.find(needle):s.find(needle)+220]:
    s = s.replace(
        needle,
        '''      testDetails = null;
      verifiedOnvif = false;
      verifiedRtsp = false;
    });
  }
''',
        1,
    )

old = '''        useOnvif: protocol.contains('ONVIF'),
        useRtsp: protocol.contains('RTSP'),
      );
'''
new = '''        useOnvif: protocol.contains('ONVIF'),
        useRtsp: protocol.contains('RTSP'),
        vendorHint: cameraVendor,
        customRtspPath: rtspPath.text.trim().isEmpty ? null : rtspPath.text.trim(),
      );
'''
if old in s:
    s = s.replace(old, new, 1)
elif "vendorHint: cameraVendor" not in s:
    raise SystemExit('V108: connector vendor arguments anchor missing')

old = '''      setState(() {
        testedSuccessfully = result.success;
        discoveredStreamUri = discoveredProfiles?.mainStreamUri ?? result.streamUri;
        discoveredSubStreamUri = discoveredProfiles?.subStreamUri;
        discoveredProfileCount = discoveredProfiles?.profiles.length ?? 0;
        testDetails = result.message;
      });
'''
new = '''      final usableStream = discoveredProfiles?.mainStreamUri ?? result.streamUri;
      final connectionUsable = result.success || (result.rtspOk && usableStream != null);
      final detectedVendor = _vendorFromManufacturer(info['Manufacturer'] ?? '');
      setState(() {
        if (cameraVendor == 'auto' && detectedVendor != 'auto') {
          cameraVendor = detectedVendor;
        }
        verifiedOnvif = result.onvifOk;
        verifiedRtsp = result.rtspOk;
        testedSuccessfully = connectionUsable;
        discoveredStreamUri = usableStream;
        discoveredSubStreamUri = discoveredProfiles?.subStreamUri;
        discoveredProfileCount = discoveredProfiles?.profiles.length ?? 0;
        testDetails = result.message;
        if (result.rtspOk && !result.onvifOk) protocol = 'RTSP';
        if (result.onvifOk && !result.rtspOk) protocol = 'ONVIF';
      });
'''
if old in s:
    s = s.replace(old, new, 1)
elif "final connectionUsable = result.success || (result.rtspOk && usableStream != null);" in s:
    if "final detectedVendor = _vendorFromManufacturer" not in s:
        s = s.replace(
            "      final connectionUsable = result.success || (result.rtspOk && usableStream != null);\n"
            "      setState(() {\n",
            "      final connectionUsable = result.success || (result.rtspOk && usableStream != null);\n"
            "      final detectedVendor = _vendorFromManufacturer(info['Manufacturer'] ?? '');\n"
            "      setState(() {\n"
            "        if (cameraVendor == 'auto' && detectedVendor != 'auto') {\n"
            "          cameraVendor = detectedVendor;\n"
            "        }\n",
            1,
        )
else:
    raise SystemExit('V108: truthful connection state anchor missing')

s = s.replace("      if (result.success) {\n", "      if (connectionUsable) {\n", 1)

s = s.replace(
    "            'onvif': protocol.contains('ONVIF'),\n"
    "            'rtsp': protocol.contains('RTSP'),\n"
    "            'connection_verified': true,\n",
    "            'onvif': verifiedOnvif,\n"
    "            'rtsp': verifiedRtsp,\n"
    "            'connection_verified': testedSuccessfully,\n",
    1,
)

if "'serial_number': serial.text.trim().isEmpty ? null : serial.text.trim()," not in s:
    s = s.replace(
        "            'camera_type': cameraType,\n",
        "            'camera_type': cameraType,\n"
        "            'serial_number': serial.text.trim().isEmpty ? null : serial.text.trim(),\n",
        1,
    )

s = s.replace(
    """      final vendor = manufacturer.text.trim().isEmpty
          ? 'Generic'
          : manufacturer.text.trim();
""",
    """      final vendor = manufacturer.text.trim().isEmpty
          ? (cameraVendor == 'auto' || cameraVendor.startsWith('generic_')
              ? 'Generic'
              : _vendorDisplayName(cameraVendor))
          : manufacturer.text.trim();
""",
    1,
)

if "'vendor_profile': cameraVendor," not in s:
    s = s.replace(
        "            'vendor': vendor,\n",
        "            'vendor': vendor,\n"
        "            'vendor_profile': cameraVendor,\n"
        "            'custom_rtsp_path': rtspPath.text.trim().isEmpty ? null : rtspPath.text.trim(),\n",
        1,
    )

if "String _vendorFromManufacturer(String value)" not in s:
    helper_anchor = "  void _snack(String text, bool error) {\n"
    helper = r'''  String _vendorFromManufacturer(String value) {
    final v = value.toLowerCase();
    if (v.contains('dahua') || v.contains('amcrest')) return v.contains('amcrest') ? 'amcrest' : 'dahua';
    if (v.contains('hikvision')) return 'hikvision';
    if (v.contains('annke')) return 'annke';
    if (v.contains('hanwha') || v.contains('samsung techwin')) return 'hanwha';
    if (v.contains('uniview') || v == 'unv') return 'uniview';
    if (v.contains('axis')) return 'axis';
    if (v.contains('reolink')) return 'reolink';
    if (v.contains('vivotek')) return 'vivotek';
    if (v.contains('bosch')) return 'bosch';
    if (v.contains('foscam')) return 'foscam';
    if (v.contains('vigi') || v.contains('tp-link')) return 'vigi';
    if (v.contains('ezviz')) return 'ezviz';
    return 'auto';
  }

  String _vendorDisplayName(String value) {
    const names = <String, String>{
      'dahua': 'Dahua',
      'hikvision': 'Hikvision',
      'hanwha': 'Hanwha / Samsung',
      'annke': 'ANNKE',
      'uniview': 'Uniview (UNV)',
      'axis': 'Axis',
      'reolink': 'Reolink',
      'amcrest': 'Amcrest',
      'vivotek': 'VIVOTEK',
      'bosch': 'Bosch',
      'foscam': 'Foscam',
      'vigi': 'TP-Link VIGI',
      'ezviz': 'EZVIZ',
      'generic_onvif': 'Generic ONVIF',
      'generic_rtsp': 'Generic RTSP',
    };
    return names[value] ?? value;
  }

'''
    if helper_anchor not in s:
        raise SystemExit('V108: onboarding helper anchor missing')
    s = s.replace(helper_anchor, helper + helper_anchor, 1)

manufacturer_field = '''            _field(
              manufacturer,
              _dt(context, 'Manufacturer (optional)', 'الشركة المصنعة (اختياري)', 'Fabrikant (optioneel)'),
              Icons.factory_outlined,
              hintText: 'Dahua, Hikvision, Uniview, Axis…',
            ),
            const SizedBox(height: 12),
'''
vendor_dropdown = r'''            DropdownButtonFormField<String>(
              value: cameraVendor,
              decoration: InputDecoration(
                labelText: _dt(context, 'Camera brand / profile', 'ماركة / نظام الكاميرا', 'Cameramerk / profiel'),
                prefixIcon: const Icon(Icons.precision_manufacturing_outlined),
              ),
              items: [
                DropdownMenuItem(
                  value: 'auto',
                  child: Text(_dt(context, 'Auto detect (recommended)', 'تحديد تلقائي (موصى به)', 'Automatisch detecteren (aanbevolen)')),
                ),
                const DropdownMenuItem(value: 'dahua', child: Text('Dahua')),
                const DropdownMenuItem(value: 'hikvision', child: Text('Hikvision')),
                const DropdownMenuItem(value: 'hanwha', child: Text('Hanwha / Samsung')),
                const DropdownMenuItem(value: 'annke', child: Text('ANNKE')),
                const DropdownMenuItem(value: 'uniview', child: Text('Uniview (UNV)')),
                const DropdownMenuItem(value: 'axis', child: Text('Axis')),
                const DropdownMenuItem(value: 'reolink', child: Text('Reolink')),
                const DropdownMenuItem(value: 'amcrest', child: Text('Amcrest')),
                const DropdownMenuItem(value: 'vivotek', child: Text('VIVOTEK')),
                const DropdownMenuItem(value: 'bosch', child: Text('Bosch')),
                const DropdownMenuItem(value: 'foscam', child: Text('Foscam')),
                const DropdownMenuItem(value: 'vigi', child: Text('TP-Link VIGI')),
                const DropdownMenuItem(value: 'ezviz', child: Text('EZVIZ')),
                const DropdownMenuItem(value: 'generic_onvif', child: Text('Generic ONVIF')),
                const DropdownMenuItem(value: 'generic_rtsp', child: Text('Generic RTSP')),
              ],
              onChanged: busy
                  ? null
                  : (v) {
                      final next = v ?? 'auto';
                      setState(() {
                        cameraVendor = next;
                        if (next != 'auto' && next != 'generic_onvif' && next != 'generic_rtsp') {
                          manufacturer.text = _vendorDisplayName(next);
                        } else if (next == 'auto') {
                          manufacturer.clear();
                        }
                        if (next == 'generic_rtsp') protocol = 'RTSP';
                      });
                      _invalidateTest();
                    },
            ),
            const SizedBox(height: 12),
'''
if manufacturer_field in s:
    s = s.replace(manufacturer_field, vendor_dropdown, 1)
elif "Camera brand / profile" not in s:
    raise SystemExit('V108: manufacturer UI anchor missing')

protocol_block_tail = '''            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: purpose,
'''
if "Custom RTSP path / URL (optional)" not in s:
    custom_ui = r'''            const SizedBox(height: 12),
            _field(
              rtspPath,
              _dt(
                context,
                'Custom RTSP path / URL (optional)',
                'مسار / رابط RTSP مخصص (اختياري)',
                'Aangepast RTSP-pad / URL (optioneel)',
              ),
              Icons.route_outlined,
              keyboardType: TextInputType.url,
              hintText: '/cam/realmonitor?channel=1&subtype=0',
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: purpose,
'''
    if protocol_block_tail not in s:
        raise SystemExit('V108: RTSP custom path UI anchor missing')
    s = s.replace(protocol_block_tail, custom_ui, 1)

p.write_text(s, encoding='utf-8')

# ---------------- Vendor-aware camera connection ----------------
p = Path('lib/monitoring/camera_connection_service.dart')
s = p.read_text(encoding='utf-8')

if "String vendorHint = 'auto'," not in s:
    s = s.replace(
        "    required bool useRtsp,\n  }) async {",
        "    required bool useRtsp,\n"
        "    String vendorHint = 'auto',\n"
        "    String? customRtspPath,\n"
        "  }) async {",
        1,
    )

old_candidates = '''        final candidates = streamUri != null
            ? <String>[streamUri]
            : _rtspCandidateUris(host, rtspPort);
'''
new_candidates = '''        final candidates = <String>{
          if (streamUri != null && streamUri.trim().isNotEmpty) streamUri,
          ..._rtspCandidateUris(
            host,
            rtspPort,
            vendorHint: vendorHint,
            customRtspPath: customRtspPath,
          ),
        }.toList();
'''
if old_candidates in s:
    s = s.replace(old_candidates, new_candidates, 1)
else:
    s = s.replace(
        "          ..._rtspCandidateUris(host, rtspPort),\n",
        "          ..._rtspCandidateUris(\n"
        "            host,\n"
        "            rtspPort,\n"
        "            vendorHint: vendorHint,\n"
        "            customRtspPath: customRtspPath,\n"
        "          ),\n",
        1,
    )
if "vendorHint: vendorHint" not in s:
    raise SystemExit('V108: vendor RTSP candidate wiring missing')

start = s.find('  List<String> _rtspCandidateUris(')
end = s.find('  Future<void> _probeRtsp({', start)
if start < 0 or end < 0:
    raise SystemExit('V108: RTSP candidate method block missing')

candidate_method = r'''  List<String> _rtspCandidateUris(
    String host,
    int port, {
    String vendorHint = 'auto',
    String? customRtspPath,
  }) {
    final base = 'rtsp://$host:$port';
    final result = <String>[];

    void add(String value) {
      final v = value.trim();
      if (v.isNotEmpty && !result.contains(v)) result.add(v);
    }

    final custom = customRtspPath?.trim() ?? '';
    if (custom.isNotEmpty) {
      if (custom.toLowerCase().startsWith('rtsp://')) {
        add(custom);
      } else {
        add('$base/${custom.replaceFirst(RegExp(r'^/+'), '')}');
      }
    }

    void addDahua() {
      add('$base/cam/realmonitor?channel=1&subtype=0');
      add('$base/cam/realmonitor?channel=1&subtype=1');
    }

    void addHikvision() {
      add('$base/Streaming/Channels/101');
      add('$base/Streaming/Channels/102');
      add('$base/h264/ch1/main/av_stream');
      add('$base/h264/ch1/sub/av_stream');
    }

    switch (vendorHint.toLowerCase()) {
      case 'dahua':
      case 'amcrest':
        addDahua();
        break;
      case 'hikvision':
      case 'annke':
      case 'ezviz':
        addHikvision();
        break;
      case 'hanwha':
        add('$base/profile1/media.smp');
        add('$base/profile2/media.smp');
        add('$base/LIVE/profile1/media.smp');
        add('$base/LIVE/profile2/media.smp');
        break;
      case 'uniview':
        add('$base/media/video1');
        add('$base/media/video2');
        add('$base/live/ch00_0');
        add('$base/live/ch00_1');
        break;
      case 'axis':
        add('$base/axis-media/media.amp');
        add('$base/axis-media/media.amp?videocodec=h264');
        break;
      case 'reolink':
        add('$base/h264Preview_01_main');
        add('$base/h264Preview_01_sub');
        break;
      case 'vivotek':
        add('$base/live.sdp');
        add('$base/live2.sdp');
        break;
      case 'foscam':
        add('$base/videoMain');
        add('$base/videoSub');
        break;
      case 'vigi':
        add('$base/stream1');
        add('$base/stream2');
        break;
      case 'generic_rtsp':
      case 'generic_onvif':
      case 'bosch':
      case 'auto':
      default:
        break;
    }

    addDahua();
    addHikvision();
    add('$base/profile1/media.smp');
    add('$base/profile2/media.smp');
    add('$base/media/video1');
    add('$base/media/video2');
    add('$base/axis-media/media.amp');
    add('$base/h264Preview_01_main');
    add('$base/h264Preview_01_sub');
    add('$base/live/ch00_0');
    add('$base/live/ch00_1');
    add('$base/live.sdp');
    add('$base/videoMain');
    add('$base/videoSub');
    add('$base/stream1');
    add('$base/stream2');
    add('$base/live');
    add('$base/');

    return result;
  }

'''
s = s[:start] + candidate_method + s[end:]

start = s.find('  Future<void> _probeRtsp({')
end = s.find('  String _digestAuthorization({', start)
if start < 0 or end < 0:
    raise SystemExit('V108: RTSP probe block missing')

probe = r'''  Future<void> _probeRtsp({
    required String uri,
    required String username,
    required String password,
  }) async {
    final parsed = Uri.parse(uri);
    final host = parsed.host;
    final port = parsed.hasPort ? parsed.port : 554;
    if (host.isEmpty) throw const FormatException('Invalid RTSP URI');

    final digestTargets = <String>[
      uri,
      parsed.path.isEmpty
          ? '/'
          : (parsed.hasQuery ? '${parsed.path}?${parsed.query}' : parsed.path),
    ];
    final uniqueDigestTargets = <String>[];
    for (final value in digestTargets) {
      if (!uniqueDigestTargets.contains(value)) uniqueDigestTargets.add(value);
    }

    Object? lastError;
    for (final method in const <String>['OPTIONS', 'DESCRIBE']) {
      try {
        final first = await _rtspRequestOnce(
          host: host,
          port: port,
          requestUri: uri,
          method: method,
        );
        if (first.statusCode >= 200 && first.statusCode < 400) return;
        if (first.statusCode != 401) {
          lastError = HttpException('RTSP ${first.statusCode}');
          continue;
        }

        final auth = first.headers['www-authenticate'];
        if (auth == null || auth.isEmpty) {
          lastError = const HttpException('RTSP authentication challenge missing');
          continue;
        }

        if (auth.toLowerCase().contains('digest')) {
          var challenge = auth.substring(auth.toLowerCase().indexOf('digest'));
          for (final digestUri in uniqueDigestTargets) {
            for (var attempt = 0; attempt < 2; attempt++) {
              try {
                final authorization = _digestAuthorization(
                  challenge: challenge,
                  username: username,
                  password: password,
                  method: method,
                  uri: digestUri,
                );
                final second = await _rtspRequestOnce(
                  host: host,
                  port: port,
                  requestUri: uri,
                  method: method,
                  authorization: authorization,
                );
                if (second.statusCode >= 200 && second.statusCode < 400) return;
                lastError = HttpException(
                  'RTSP authentication failed (${second.statusCode}) — verify camera username/password and RTSP permission',
                );
                final nextChallenge = second.headers['www-authenticate'];
                if (second.statusCode == 401 &&
                    nextChallenge != null &&
                    nextChallenge.toLowerCase().contains('digest') &&
                    nextChallenge != challenge) {
                  challenge = nextChallenge.substring(
                    nextChallenge.toLowerCase().indexOf('digest'),
                  );
                  continue;
                }
                break;
              } catch (e) {
                lastError = e;
                break;
              }
            }
          }
        }

        try {
          final basic = 'Basic ${base64Encode(utf8.encode('$username:$password'))}';
          final basicResponse = await _rtspRequestOnce(
            host: host,
            port: port,
            requestUri: uri,
            method: method,
            authorization: basic,
          );
          if (basicResponse.statusCode >= 200 && basicResponse.statusCode < 400) return;
          lastError = HttpException(
            'RTSP authentication failed (${basicResponse.statusCode}) — verify camera username/password and RTSP permission',
          );
        } catch (e) {
          lastError = e;
        }
      } catch (e) {
        lastError = e;
      }
    }

    throw lastError ?? const HttpException('RTSP connection failed');
  }

  Future<_RtspResponse> _rtspRequestOnce({
    required String host,
    required int port,
    required String requestUri,
    required String method,
    String? authorization,
  }) async {
    Socket? socket;
    StreamSubscription<List<int>>? sub;
    try {
      socket = await Socket.connect(host, port, timeout: const Duration(seconds: 5));
      final lines = <String>[
        '$method $requestUri RTSP/1.0',
        'CSeq: 1',
        'User-Agent: VetAI/0.6.29',
        'Connection: close',
        if (method == 'DESCRIBE') 'Accept: application/sdp',
        if (authorization != null) 'Authorization: $authorization',
        '',
        '',
      ];
      socket.write(lines.join('\r\n'));
      await socket.flush();

      final completer = Completer<String>();
      final buffer = StringBuffer();
      sub = socket.listen((data) {
        buffer.write(latin1.decode(data, allowInvalid: true));
        if (buffer.toString().contains('\r\n\r\n') && !completer.isCompleted) {
          completer.complete(buffer.toString());
        }
      }, onError: (Object e) {
        if (!completer.isCompleted) completer.completeError(e);
      }, onDone: () {
        if (!completer.isCompleted) completer.complete(buffer.toString());
      });

      final raw = await completer.future.timeout(const Duration(seconds: 6));
      final rows = raw.split('\r\n');
      final status = rows.isEmpty
          ? null
          : RegExp(r'RTSP/\d\.\d\s+(\d{3})').firstMatch(rows.first);
      if (status == null) throw const FormatException('Invalid RTSP response');
      final headers = <String, String>{};
      for (final row in rows.skip(1)) {
        final i = row.indexOf(':');
        if (i > 0) {
          final key = row.substring(0, i).trim().toLowerCase();
          final value = row.substring(i + 1).trim();
          headers[key] = headers.containsKey(key) ? '${headers[key]}, $value' : value;
        }
      }
      return _RtspResponse(int.parse(status.group(1)!), headers);
    } finally {
      await sub?.cancel();
      await socket?.close();
    }
  }

'''
s = s[:start] + probe + s[end:]
p.write_text(s, encoding='utf-8')

# ---------------- Hide engineering gateway UI ----------------
p = Path('lib/v5_app.dart')
s = p.read_text(encoding='utf-8')
s = s.replace("import 'monitoring/camera_gateway_page.dart';\n", '')
anchor = 'builder: (_) => CameraGatewayPage(farmId: farmId),'
idx = s.find(anchor)
if idx >= 0:
    start = s.rfind('OutlinedButton.icon(', 0, idx)
    marker = 'const SizedBox(height: 10),'
    end = s.find(marker, idx)
    if start >= 0 and end >= 0:
        end += len(marker)
        if end < len(s) and s[end] == '\n':
            end += 1
        s = s[:start] + s[end:]
if 'CameraGatewayPage(' in s:
    raise SystemExit('V108: customer gateway UI still present in v5_app.dart')
p.write_text(s, encoding='utf-8')

p = Path('lib/monitoring/camera_center_page.dart')
s = p.read_text(encoding='utf-8')
s = s.replace("import 'camera_gateway_page.dart';\n", '')
anchor = 'CameraGatewayPage(farmId: widget.farmId)'
idx = s.find(anchor)
if idx >= 0:
    start = s.rfind('IconButton(', 0, idx)
    next_button = s.find('IconButton(onPressed: _load', idx)
    if start >= 0 and next_button >= 0:
        s = s[:start] + s[next_button:]
if 'CameraGatewayPage(' in s:
    raise SystemExit('V108: gateway action still present in camera_center_page.dart')
p.write_text(s, encoding='utf-8')

# ---------------- Restore approved Vet AI iOS icon ----------------
def restore_ios_icon() -> None:
    svg = Path('assets/vet_ai_app_icon.svg')
    appicon_dir = Path('ios/Runner/Assets.xcassets/AppIcon.appiconset')
    if not svg.exists() or not appicon_dir.exists():
        raise SystemExit('V108: Vet AI icon source or iOS AppIcon directory missing')

    rendered = Path('assets/vet_ai_app_icon.png')
    rendered.unlink(missing_ok=True)
    try:
        subprocess.run(
            ['sips', '-s', 'format', 'png', str(svg), '--out', str(rendered)],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except Exception:
        pass

    if not rendered.exists() or rendered.stat().st_size == 0:
        try:
            import cairosvg  # type: ignore
        except Exception:
            subprocess.run(
                [sys.executable, '-m', 'pip', 'install', '--quiet',
                 '--break-system-packages', 'cairosvg'],
                check=True,
            )
            import cairosvg  # type: ignore
        cairosvg.svg2png(
            url=str(svg),
            write_to=str(rendered),
            output_width=1024,
            output_height=1024,
        )

    from PIL import Image
    with Image.open(rendered) as source_image:
        rgba = source_image.convert('RGBA')
    background = Image.new('RGBA', rgba.size, (7, 24, 27, 255))
    background.alpha_composite(rgba)
    source = background.convert('RGB')
    source.save(rendered, 'PNG')

    replaced = 0
    for target in sorted(appicon_dir.glob('*.png')):
        try:
            with Image.open(target) as current:
                size = current.size
        except Exception:
            continue
        source.resize(size, Image.Resampling.LANCZOS).save(target, 'PNG')
        replaced += 1
    if replaced == 0:
        raise SystemExit('V108: no generated iOS AppIcon PNG files were replaced')
    print(f'V108: restored approved Vet AI iOS icon in {replaced} launcher assets')

restore_ios_icon()

onboarding = Path('lib/monitoring/dahua_thermal_camera_onboarding_page.dart').read_text(encoding='utf-8')
connection = Path('lib/monitoring/camera_connection_service.dart').read_text(encoding='utf-8')
for token in ['cameraVendor', 'ANNKE', 'Hanwha / Samsung', 'Custom RTSP path / URL (optional)', 'vendorHint: cameraVendor']:
    if token not in onboarding:
        raise SystemExit(f'V108 onboarding verification missing: {token}')
for token in ['vendorHint', 'profile1/media.smp', 'axis-media/media.amp', 'h264Preview_01_main', 'Streaming/Channels/101']:
    if token not in connection:
        raise SystemExit(f'V108 connection verification missing: {token}')

print('V108 vendor-aware camera profiles + V107 recovery applied')
