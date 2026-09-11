from pathlib import Path

p = Path('lib/monitoring/camera_connection_service.dart')
s = p.read_text(encoding='utf-8')

# 1) ONVIF: support cameras that close a SOAP 1.2 request and only answer SOAP 1.1.
old = '''    var response = await send(null);\n    if (response.statusCode == HttpStatus.unauthorized) {'''
new = '''    _HttpSoapResponse response;\n    try {\n      response = await send(null);\n    } on HttpException catch (_) {\n      response = await _sendSoap11(\n        uri,\n        body,\n        soapAction,\n        username,\n        password,\n      );\n    } on SocketException catch (_) {\n      response = await _sendSoap11(\n        uri,\n        body,\n        soapAction,\n        username,\n        password,\n      );\n    }\n    if (response.statusCode == HttpStatus.unauthorized) {'''
if old in s and '_sendSoap11(' not in s:
    s = s.replace(old, new, 1)

anchor = '''  String _httpDigestAuthorization({\n'''
if 'Future<_HttpSoapResponse> _sendSoap11(' not in s:
    method = r'''  Future<_HttpSoapResponse> _sendSoap11(
    Uri uri,
    String body,
    String soapAction,
    String username,
    String password,
  ) async {
    Future<_HttpSoapResponse> send(String? authorization) async {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5)
        ..badCertificateCallback = (_, __, ___) => true;
      try {
        final request = await client.postUrl(uri).timeout(const Duration(seconds: 7));
        request.headers.contentType = ContentType('text', 'xml', charset: 'utf-8');
        request.headers.set('SOAPAction', '"$soapAction"');
        request.headers.set(HttpHeaders.connectionHeader, 'close');
        if (authorization != null) {
          request.headers.set(HttpHeaders.authorizationHeader, authorization);
        }
        request.write(body.replaceFirst(
          'http://www.w3.org/2003/05/soap-envelope',
          'http://schemas.xmlsoap.org/soap/envelope/',
        ));
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
      if (challenge != null && challenge.isNotEmpty) {
        final lower = challenge.toLowerCase();
        String? authorization;
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
        }
        if (authorization != null) response = await send(authorization);
      }
    }
    return response;
  }

'''
    if anchor not in s:
        raise SystemExit('V105: HTTP digest anchor not found')
    s = s.replace(anchor, method + anchor, 1)

# 2) RTSP: probe common real stream paths when ONVIF URI is unavailable.
old = '''        final uri = streamUri ?? 'rtsp://$host:$rtspPort/';\n        await _probeRtsp(\n          uri: uri,\n          username: username,\n          password: password,\n        );\n        rtspOk = true;\n        streamUri ??= uri;'''
new = '''        final candidates = streamUri != null\n            ? <String>[streamUri]\n            : _rtspCandidateUris(host, rtspPort);\n        Object? lastError;\n        for (final uri in candidates) {\n          try {\n            await _probeRtsp(\n              uri: uri,\n              username: username,\n              password: password,\n            );\n            rtspOk = true;\n            streamUri = uri;\n            lastError = null;\n            break;\n          } catch (e) {\n            lastError = e;\n          }\n        }\n        if (!rtspOk && lastError != null) throw lastError;'''
if old in s:
    s = s.replace(old, new, 1)

anchor = '''  Future<void> _probeRtsp({\n'''
if 'List<String> _rtspCandidateUris(' not in s:
    method = r'''  List<String> _rtspCandidateUris(String host, int port) {
    final base = 'rtsp://$host:$port';
    return <String>[
      '$base/cam/realmonitor?channel=1&subtype=0',
      '$base/cam/realmonitor?channel=1&subtype=1',
      '$base/Streaming/Channels/101',
      '$base/Streaming/Channels/102',
      '$base/h264Preview_01_main',
      '$base/h264Preview_01_sub',
      '$base/live/ch00_0',
      '$base/live/ch00_1',
      '$base/stream1',
      '$base/stream2',
      '$base/live',
      '$base/',
    ];
  }

'''
    if anchor not in s:
        raise SystemExit('V105: RTSP probe anchor not found')
    s = s.replace(anchor, method + anchor, 1)

# 3) RTSP Digest: qop=auth, opaque and MD5-sess support.
start = s.find('  String _digestAuthorization({')
end = s.find('\n  String _soapEnvelope({', start)
if start < 0 or end < 0:
    raise SystemExit('V105: RTSP digest method not found')
new_digest = r'''  String _digestAuthorization({
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
    if (nonce == null || nonce.isEmpty) throw const HttpException('RTSP digest nonce missing');
    final algorithm = (params['algorithm'] ?? 'MD5').toUpperCase();
    if (algorithm != 'MD5' && algorithm != 'MD5-SESS') {
      throw HttpException('Unsupported RTSP digest algorithm: $algorithm');
    }

    final seedHa1 = md5.convert(utf8.encode('$username:$realm:$password')).toString();
    final cnonce = List<int>.generate(12, (_) => Random.secure().nextInt(256))
        .map((e) => e.toRadixString(16).padLeft(2, '0'))
        .join();
    final ha1 = algorithm == 'MD5-SESS'
        ? md5.convert(utf8.encode('$seedHa1:$nonce:$cnonce')).toString()
        : seedHa1;
    final ha2 = md5.convert(utf8.encode('$method:$uri')).toString();
    final qops = (params['qop'] ?? '')
        .split(',')
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toList();

    String response;
    final pieces = <String>[
      'username="$username"',
      'realm="$realm"',
      'nonce="$nonce"',
      'uri="$uri"',
    ];
    if (qops.contains('auth')) {
      const nc = '00000001';
      response = md5.convert(utf8.encode('$ha1:$nonce:$nc:$cnonce:auth:$ha2')).toString();
      pieces.addAll(<String>[
        'response="$response"',
        'qop=auth',
        'nc=$nc',
        'cnonce="$cnonce"',
      ]);
    } else {
      response = md5.convert(utf8.encode('$ha1:$nonce:$ha2')).toString();
      pieces.add('response="$response"');
      if (algorithm == 'MD5-SESS') pieces.add('cnonce="$cnonce"');
    }
    final opaque = params['opaque'];
    if (opaque != null && opaque.isNotEmpty) pieces.add('opaque="$opaque"');
    if (params['algorithm'] != null) pieces.add('algorithm=${params['algorithm']}');
    return 'Digest ${pieces.join(', ')}';
  }
'''
s = s[:start] + new_digest + s[end:]

p.write_text(s, encoding='utf-8')
print('V105 camera connection compatibility applied')
