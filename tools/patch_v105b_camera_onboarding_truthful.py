from pathlib import Path
import subprocess
import sys

# Keep the truthful V105b onboarding behavior.
p = Path('lib/monitoring/dahua_thermal_camera_onboarding_page.dart')
s = p.read_text(encoding='utf-8')

old = """  String? testDetails;\n"""
new = """  String? testDetails;\n  bool verifiedOnvif = false;\n  bool verifiedRtsp = false;\n"""
if old in s and 'bool verifiedOnvif' not in s:
    s = s.replace(old, new, 1)

old = """      testDetails = null;\n    });\n  }\n"""
new = """      testDetails = null;\n      verifiedOnvif = false;\n      verifiedRtsp = false;\n    });\n  }\n"""
if old in s and 'verifiedOnvif = false;' not in s[s.find(old):s.find(old)+len(new)+100]:
    s = s.replace(old, new, 1)

old = """      testDetails = null;\n    });\n\n    try {\n      final result = await _connector.test("""
new = """      testDetails = null;\n      verifiedOnvif = false;\n      verifiedRtsp = false;\n    });\n\n    try {\n      final result = await _connector.test("""
if old in s:
    s = s.replace(old, new, 1)

old = """      setState(() {\n        testedSuccessfully = result.success;\n        discoveredStreamUri = discoveredProfiles?.mainStreamUri ?? result.streamUri;\n        discoveredSubStreamUri = discoveredProfiles?.subStreamUri;\n        discoveredProfileCount = discoveredProfiles?.profiles.length ?? 0;\n        testDetails = result.message;\n      });\n"""
new = """      final usableStream = discoveredProfiles?.mainStreamUri ?? result.streamUri;\n      final connectionUsable = result.success || (result.rtspOk && usableStream != null);\n      setState(() {\n        verifiedOnvif = result.onvifOk;\n        verifiedRtsp = result.rtspOk;\n        testedSuccessfully = connectionUsable;\n        discoveredStreamUri = usableStream;\n        discoveredSubStreamUri = discoveredProfiles?.subStreamUri;\n        discoveredProfileCount = discoveredProfiles?.profiles.length ?? 0;\n        testDetails = result.message;\n        if (result.rtspOk && !result.onvifOk) protocol = 'RTSP';\n        if (result.onvifOk && !result.rtspOk) protocol = 'ONVIF';\n      });\n"""
if old in s:
    s = s.replace(old, new, 1)
elif 'final connectionUsable = result.success || (result.rtspOk && usableStream != null);' not in s:
    raise SystemExit('V105b: result state anchor missing')

if 'final connectionUsable =' in s:
    s = s.replace('      if (result.success) {\n', '      if (connectionUsable) {\n', 1)

s = s.replace("            'onvif': protocol.contains('ONVIF'),\n            'rtsp': protocol.contains('RTSP'),\n            'connection_verified': true,\n",
              "            'onvif': verifiedOnvif,\n            'rtsp': verifiedRtsp,\n            'connection_verified': testedSuccessfully,\n", 1)

needle = "            'camera_type': cameraType,\n"
insert = "            'camera_type': cameraType,\n            'serial_number': serial.text.trim().isEmpty ? null : serial.text.trim(),\n"
if needle in s and "'serial_number': serial.text" not in s:
    s = s.replace(needle, insert, 1)

p.write_text(s, encoding='utf-8')

# V107 camera recovery: an ONVIF-reported stream is only the first RTSP
# candidate. If that URI is incomplete or vendor-specific, continue through
# the known Dahua/Hikvision/Reolink/generic paths instead of failing early.
p = Path('lib/monitoring/camera_connection_service.dart')
s = p.read_text(encoding='utf-8')
old = """        final candidates = streamUri != null\n            ? <String>[streamUri]\n            : _rtspCandidateUris(host, rtspPort);\n"""
new = """        final candidates = <String>{\n          if (streamUri != null && streamUri.trim().isNotEmpty) streamUri,\n          ..._rtspCandidateUris(host, rtspPort),\n        }.toList();\n"""
if old in s:
    s = s.replace(old, new, 1)
elif "..._rtspCandidateUris(host, rtspPort)" not in s:
    raise SystemExit('V107: RTSP candidate anchor missing')

start = s.find('  Future<void> _probeRtsp({')
end = s.find('  String _digestAuthorization({', start)
if start < 0 or end < 0:
    raise SystemExit('V107: RTSP probe block missing')

replacement = r'''  Future<void> _probeRtsp({
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

        // Some cameras expose both schemes inconsistently. A Basic retry is
        // harmless for Digest-only devices and fixes older NVR firmware that
        // advertises a malformed Digest challenge.
        try {
          final basic = 'Basic ${base64Encode(utf8.encode('$username:$password'))}';
          final basicResponse = await _rtspRequestOnce(
            host: host,
            port: port,
            requestUri: uri,
            method: method,
            authorization: basic,
          );
          if (basicResponse.statusCode >= 200 && basicResponse.statusCode < 400) {
            return;
          }
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
      socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 5),
      );
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
          if (headers.containsKey(key)) {
            headers[key] = '${headers[key]}, $value';
          } else {
            headers[key] = value;
          }
        }
      }
      return _RtspResponse(int.parse(status.group(1)!), headers);
    } finally {
      await sub?.cancel();
      await socket?.close();
    }
  }

'''
s = s[:start] + replacement + s[end:]
p.write_text(s, encoding='utf-8')

# The local gateway was an engineering/always-on relay surface, not something
# the normal customer camera flow should expose. Hide it from the app UI while
# keeping the backend code available for a future managed remote-relay feature.
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
    raise SystemExit('V107: customer gateway UI still present in v5_app.dart')
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
    raise SystemExit('V107: gateway action still present in camera_center_page.dart')
p.write_text(s, encoding='utf-8')

# flutter create regenerates the default Flutter launcher icon. Restore the
# approved Vet AI icon after project generation, before Xcode archives it.
def restore_ios_icon() -> None:
    svg = Path('assets/vet_ai_app_icon.svg')
    appicon_dir = Path('ios/Runner/Assets.xcassets/AppIcon.appiconset')
    if not svg.exists() or not appicon_dir.exists():
        raise SystemExit('V107: Vet AI icon source or iOS AppIcon directory missing')

    rendered = Path('assets/vet_ai_app_icon.png')
    rendered.unlink(missing_ok=True)

    # Prefer macOS native rasterization. Fall back to CairoSVG if needed.
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
                [
                    sys.executable,
                    '-m',
                    'pip',
                    'install',
                    '--quiet',
                    '--break-system-packages',
                    'cairosvg',
                ],
                check=True,
            )
            import cairosvg  # type: ignore
        cairosvg.svg2png(
            url=str(svg),
            write_to=str(rendered),
            output_width=1024,
            output_height=1024,
        )

    if not rendered.exists() or rendered.stat().st_size == 0:
        raise SystemExit('V107: failed to rasterize approved Vet AI app icon')

    from PIL import Image

    with Image.open(rendered) as source_image:
        rgba = source_image.convert('RGBA')
    # iOS App Store icons cannot contain alpha. Flatten any rounded SVG corner
    # transparency onto the approved dark Vet AI background.
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
        raise SystemExit('V107: no generated iOS AppIcon PNG files were replaced')
    print(f'V107: restored approved Vet AI iOS icon in {replaced} launcher assets')

restore_ios_icon()
print('V107 camera recovery + truthful onboarding applied')
