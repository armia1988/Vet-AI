from pathlib import Path

p = Path('lib/monitoring/camera_connection_service.dart')
s = p.read_text(encoding='utf-8')

old = '''  String _digestAuthorization({
    required String challenge,
    required String username,
    required String password,
    required String method,
    required String uri,
  }) {
    final params = <String, String>{};
    for (final match in RegExp(r'(\\w+)=(?:"([^"]*)"|([^,\\s]+))').allMatches(challenge)) {
      params[match.group(1)!.toLowerCase()] = match.group(2) ?? match.group(3) ?? '';
    }
    final realm = params['realm'] ?? '';
    final nonce = params['nonce'];
    if (nonce == null || nonce.isEmpty) throw const HttpException('RTSP digest nonce missing');
    final ha1 = md5.convert(utf8.encode('$username:$realm:$password')).toString();
    final ha2 = md5.convert(utf8.encode('$method:$uri')).toString();
    final response = md5.convert(utf8.encode('$ha1:$nonce:$ha2')).toString();
    return 'Digest username="$username", realm="$realm", nonce="$nonce", uri="$uri", response="$response"';
  }
'''

new = '''  String _digestAuthorization({
    required String challenge,
    required String username,
    required String password,
    required String method,
    required String uri,
  }) {
    final params = <String, String>{};
    for (final match in RegExp(r'(\\w+)=(?:"([^"]*)"|([^,\\s]+))').allMatches(challenge)) {
      params[match.group(1)!.toLowerCase()] = match.group(2) ?? match.group(3) ?? '';
    }

    final realm = params['realm'] ?? '';
    final nonce = params['nonce'];
    if (nonce == null || nonce.isEmpty) {
      throw const HttpException('RTSP digest nonce missing');
    }

    final algorithm = (params['algorithm'] ?? 'MD5').toUpperCase();
    if (algorithm != 'MD5' && algorithm != 'MD5-SESS') {
      throw HttpException('Unsupported RTSP digest algorithm: $algorithm');
    }

    final cnonce = List<int>.generate(12, (_) => Random.secure().nextInt(256))
        .map((e) => e.toRadixString(16).padLeft(2, '0'))
        .join();
    final baseHa1 = md5.convert(utf8.encode('$username:$realm:$password')).toString();
    final ha1 = algorithm == 'MD5-SESS'
        ? md5.convert(utf8.encode('$baseHa1:$nonce:$cnonce')).toString()
        : baseHa1;
    final ha2 = md5.convert(utf8.encode('$method:$uri')).toString();

    final qopRaw = params['qop'];
    final qops = qopRaw
        ?.split(',')
        .map((e) => e.trim().replaceAll('"', '').toLowerCase())
        .where((e) => e.isNotEmpty)
        .toList();
    final opaque = params['opaque'];
    final algorithmPart = params.containsKey('algorithm') ? ', algorithm=$algorithm' : '';
    final opaquePart = opaque == null || opaque.isEmpty ? '' : ', opaque="$opaque"';

    if (qops != null && qops.contains('auth')) {
      const nc = '00000001';
      final response = md5
          .convert(utf8.encode('$ha1:$nonce:$nc:$cnonce:auth:$ha2'))
          .toString();
      return 'Digest username="$username", realm="$realm", nonce="$nonce", uri="$uri", response="$response", qop=auth, nc=$nc, cnonce="$cnonce"$algorithmPart$opaquePart';
    }

    final response = md5.convert(utf8.encode('$ha1:$nonce:$ha2')).toString();
    return 'Digest username="$username", realm="$realm", nonce="$nonce", uri="$uri", response="$response"$algorithmPart$opaquePart';
  }
'''

if old in s:
    s = s.replace(old, new, 1)
elif 'Unsupported RTSP digest algorithm' not in s:
    raise SystemExit('V104b RTSP digest anchor not found')

# Improve the user-visible 401 message so a real bad password is distinguishable
# from an unsupported authentication negotiation.
old_401 = "throw HttpException('RTSP authentication failed (${second.statusCode})');"
new_401 = "throw HttpException('RTSP authentication failed (${second.statusCode}) — verify camera username/password and RTSP permission');"
if old_401 in s:
    s = s.replace(old_401, new_401, 1)

p.write_text(s, encoding='utf-8')
print('V104b applied: RTSP Digest qop=auth, MD5-sess and opaque support')
