from pathlib import Path
import plistlib

# V82: production-grade camera connectivity improvements.
# - ONVIF HTTP Basic + Digest authentication retry
# - RTSP live preview through VLC
# - iOS local-network + non-HTTPS media permissions

service_path = Path('lib/monitoring/camera_connection_service.dart')
service = service_path.read_text(encoding='utf-8')

start = service.index('  Future<String> _postSoap(')
end = service.index('  Future<void> _probeRtsp(', start)
replacement = r'''  Future<String> _postSoap(
    Uri uri,
    String body,
    String soapAction,
    String username,
    String password,
  ) async {
    Future<_HttpSoapResponse> send(String? authorization) async {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      try {
        final request = await client.postUrl(uri).timeout(const Duration(seconds: 7));
        request.headers.contentType = ContentType('application', 'soap+xml', charset: 'utf-8');
        request.headers.set('SOAPAction', soapAction);
        if (authorization != null) {
          request.headers.set(HttpHeaders.authorizationHeader, authorization);
        }
        request.write(body);
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
      final challenge = response.wwwAuthenticate;
      if (challenge == null || challenge.isEmpty) {
        throw HttpException('HTTP 401 authentication challenge missing', uri: uri);
      }

      final lower = challenge.toLowerCase();
      String authorization;
      if (lower.startsWith('digest')) {
        final digestUri = uri.path.isEmpty
            ? '/'
            : (uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path);
        authorization = _httpDigestAuthorization(
          challenge: challenge,
          username: username,
          password: password,
          method: 'POST',
          uri: digestUri,
        );
      } else if (lower.startsWith('basic')) {
        authorization = 'Basic ${base64Encode(utf8.encode('$username:$password'))}';
      } else {
        throw HttpException('Unsupported HTTP authentication scheme', uri: uri);
      }
      response = await send(authorization);
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('HTTP ${response.statusCode}', uri: uri);
    }
    return response.body;
  }

  String _httpDigestAuthorization({
    required String challenge,
    required String username,
    required String password,
    required String method,
    required String uri,
  }) {
    final params = <String, String>{};
    for (final match in RegExp(r'(\w+)=(?:"([^"]*)"|([^,\s]+))').allMatches(challenge)) {
      params[match.group(1)!.toLowerCase()] = match.group(2) ?? match.group(3) ?? '';
    }
    final realm = params['realm'] ?? '';
    final nonce = params['nonce'];
    if (nonce == null || nonce.isEmpty) {
      throw const HttpException('HTTP digest nonce missing');
    }
    final algorithm = (params['algorithm'] ?? 'MD5').toUpperCase();
    if (algorithm != 'MD5') {
      throw HttpException('Unsupported HTTP digest algorithm: $algorithm');
    }

    final ha1 = md5.convert(utf8.encode('$username:$realm:$password')).toString();
    final ha2 = md5.convert(utf8.encode('$method:$uri')).toString();
    final qopRaw = params['qop'];
    final qops = qopRaw
        ?.split(',')
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toList();

    if (qops != null && qops.contains('auth')) {
      const nc = '00000001';
      final cnonce = List<int>.generate(8, (_) => Random.secure().nextInt(256))
          .map((e) => e.toRadixString(16).padLeft(2, '0'))
          .join();
      final digest = md5
          .convert(utf8.encode('$ha1:$nonce:$nc:$cnonce:auth:$ha2'))
          .toString();
      return 'Digest username="$username", realm="$realm", nonce="$nonce", uri="$uri", response="$digest", qop=auth, nc=$nc, cnonce="$cnonce"';
    }

    final digest = md5.convert(utf8.encode('$ha1:$nonce:$ha2')).toString();
    return 'Digest username="$username", realm="$realm", nonce="$nonce", uri="$uri", response="$digest"';
  }

'''
service = service[:start] + replacement + service[end:]

if 'class _HttpSoapResponse' not in service:
    service += r'''

class _HttpSoapResponse {
  const _HttpSoapResponse(this.statusCode, this.body, this.wwwAuthenticate);
  final int statusCode;
  final String body;
  final String? wwwAuthenticate;
}
'''
service_path.write_text(service, encoding='utf-8')

onboarding_path = Path('lib/monitoring/dahua_thermal_camera_onboarding_page.dart')
onboarding = onboarding_path.read_text(encoding='utf-8')
import_line = "import 'camera_live_view_page.dart';\n"
anchor_import = "import 'camera_connection_service.dart';\n"
if import_line not in onboarding:
    if anchor_import not in onboarding:
        raise SystemExit('V82: camera service import anchor missing')
    onboarding = onboarding.replace(anchor_import, anchor_import + import_line, 1)

if 'CameraLiveViewPage(' not in onboarding:
    body_anchor = '      body: SafeArea(\n'
    if body_anchor not in onboarding:
        raise SystemExit('V82: onboarding Scaffold body anchor missing')
    fab = '''      floatingActionButton: testedSuccessfully && discoveredStreamUri != null\n          ? FloatingActionButton.extended(\n              onPressed: busy\n                  ? null\n                  : () => Navigator.push(\n                        context,\n                        MaterialPageRoute(\n                          builder: (_) => CameraLiveViewPage(\n                            streamUri: discoveredStreamUri!,\n                            username: username.text.trim(),\n                            password: password.text,\n                            cameraName: name.text.trim().isEmpty ? 'IP Camera' : name.text.trim(),\n                          ),\n                        ),\n                      ),\n              icon: const Icon(Icons.play_circle_fill_rounded),\n              label: Text(_dt(context, 'Live view', 'عرض مباشر', 'Livebeeld')),\n            )\n          : null,\n'''
    onboarding = onboarding.replace(body_anchor, fab + body_anchor, 1)
onboarding_path.write_text(onboarding, encoding='utf-8')

plist_path = Path('ios/Runner/Info.plist')
if plist_path.exists():
    with plist_path.open('rb') as f:
        plist = plistlib.load(f)
    plist['NSLocalNetworkUsageDescription'] = (
        'Vet AI connects to IP cameras on your local network for live monitoring and veterinary alerts.'
    )
    ats = dict(plist.get('NSAppTransportSecurity') or {})
    ats['NSAllowsArbitraryLoads'] = True
    plist['NSAppTransportSecurity'] = ats
    with plist_path.open('wb') as f:
        plistlib.dump(plist, f)

checks = {
    'lib/monitoring/camera_connection_service.dart': [
        '_httpDigestAuthorization',
        'HttpHeaders.wwwAuthenticateHeader',
        'qop=auth',
        'class _HttpSoapResponse',
    ],
    'lib/monitoring/dahua_thermal_camera_onboarding_page.dart': [
        "import 'camera_live_view_page.dart';",
        'CameraLiveViewPage(',
        "'Live view'",
    ],
    'lib/monitoring/camera_live_view_page.dart': [
        'VlcPlayerController.network',
        'VlcPlayer(',
        'HwAcc.full',
    ],
}
for path, markers in checks.items():
    text = Path(path).read_text(encoding='utf-8')
    for marker in markers:
        if marker not in text:
            raise SystemExit(f'V82 verification missing in {path}: {marker}')

print('Vet AI V82 applied: HTTP Digest ONVIF, authenticated RTSP live view, and iOS local-network media permissions')
