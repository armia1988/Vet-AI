import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

class CameraStreamProfile {
  const CameraStreamProfile({
    required this.token,
    required this.name,
    required this.width,
    required this.height,
    required this.streamUri,
  });

  final String token;
  final String name;
  final int? width;
  final int? height;
  final String streamUri;

  int get pixels => (width ?? 0) * (height ?? 0);
}

class CameraStreamProfiles {
  const CameraStreamProfiles({
    required this.profiles,
    required this.main,
    required this.sub,
  });

  final List<CameraStreamProfile> profiles;
  final CameraStreamProfile main;
  final CameraStreamProfile? sub;

  String get mainStreamUri => main.streamUri;
  String? get subStreamUri => sub?.streamUri;
}

class CameraStreamProfileService {
  const CameraStreamProfileService({
    required this.host,
    required this.httpPort,
    required this.username,
    required this.password,
  });

  final String host;
  final int httpPort;
  final String username;
  final String password;

  Uri get _deviceUri => Uri.parse('http://$host:$httpPort/onvif/device_service');

  Future<CameraStreamProfiles> discover() async {
    final capabilities = await _soap(
      _deviceUri,
      'http://www.onvif.org/ver10/device/wsdl/GetCapabilities',
      '<tds:GetCapabilities xmlns:tds="http://www.onvif.org/ver10/device/wsdl"><tds:Category>Media</tds:Category></tds:GetCapabilities>',
    );

    final mediaAddress = _firstMatch(
          capabilities,
          RegExp(
            r'<(?:\w+:)?Media\b[^>]*>.*?<(?:\w+:)?XAddr>(.*?)</(?:\w+:)?XAddr>',
            dotAll: true,
            caseSensitive: false,
          ),
        ) ??
        _firstMatch(
          capabilities,
          RegExp(
            r'<(?:\w+:)?XAddr>(https?://[^<]+)</(?:\w+:)?XAddr>',
            caseSensitive: false,
          ),
        );
    final mediaUri = mediaAddress == null
        ? _deviceUri
        : Uri.parse(_xmlUnescape(mediaAddress.trim()));

    final profilesXml = await _soap(
      mediaUri,
      'http://www.onvif.org/ver10/media/wsdl/GetProfiles',
      '<trt:GetProfiles xmlns:trt="http://www.onvif.org/ver10/media/wsdl"/>',
    );

    final descriptors = _parseProfiles(profilesXml);
    if (descriptors.isEmpty) {
      throw const FormatException('No ONVIF media profiles returned');
    }

    final resolved = <CameraStreamProfile>[];
    for (final descriptor in descriptors) {
      try {
        final streamUri = await _streamUri(mediaUri, descriptor.token);
        if (streamUri.isEmpty) continue;
        resolved.add(
          CameraStreamProfile(
            token: descriptor.token,
            name: descriptor.name,
            width: descriptor.width,
            height: descriptor.height,
            streamUri: streamUri,
          ),
        );
      } catch (_) {
        // Some cameras expose profiles that cannot be streamed by the current
        // account. Keep evaluating the remaining camera-reported profiles.
      }
    }

    if (resolved.isEmpty) {
      throw const FormatException('No usable RTSP URI returned by ONVIF profiles');
    }

    CameraStreamProfile main = resolved.first;
    CameraStreamProfile? sub;

    final withResolution = resolved.where((p) => p.pixels > 0).toList();
    if (withResolution.isNotEmpty) {
      withResolution.sort((a, b) => a.pixels.compareTo(b.pixels));
      main = withResolution.last;
      if (withResolution.length > 1) {
        final candidate = withResolution.first;
        if (candidate.token != main.token && candidate.streamUri != main.streamUri) {
          sub = candidate;
        }
      }
    }

    if (sub == null && resolved.length > 1) {
      for (final candidate in resolved.reversed) {
        if (candidate.token != main.token && candidate.streamUri != main.streamUri) {
          sub = candidate;
          break;
        }
      }
    }

    return CameraStreamProfiles(
      profiles: List.unmodifiable(resolved),
      main: main,
      sub: sub,
    );
  }

  List<_ProfileDescriptor> _parseProfiles(String xml) {
    final profiles = <_ProfileDescriptor>[];
    final pattern = RegExp(
      r'''<(?:\w+:)?Profiles\b([^>]*)>(.*?)</(?:\w+:)?Profiles>''',
      dotAll: true,
      caseSensitive: false,
    );
    for (final match in pattern.allMatches(xml)) {
      final attrs = match.group(1) ?? '';
      final block = match.group(2) ?? '';
      final token = _attribute(attrs, 'token')?.trim() ?? '';
      if (token.isEmpty) continue;
      final name = _xmlUnescape(_xmlValue(block, 'Name')?.trim() ?? '');
      final width = int.tryParse(_xmlValue(block, 'Width')?.trim() ?? '');
      final height = int.tryParse(_xmlValue(block, 'Height')?.trim() ?? '');
      profiles.add(
        _ProfileDescriptor(
          token: _xmlUnescape(token),
          name: name,
          width: width,
          height: height,
        ),
      );
    }

    if (profiles.isEmpty) {
      final tokenPattern = RegExp(
        r'''<(?:\w+:)?Profiles\b[^>]*\btoken=["']([^"']+)["']''',
        caseSensitive: false,
      );
      for (final match in tokenPattern.allMatches(xml)) {
        final token = _xmlUnescape(match.group(1) ?? '').trim();
        if (token.isNotEmpty) {
          profiles.add(_ProfileDescriptor(token: token, name: '', width: null, height: null));
        }
      }
    }

    final seen = <String>{};
    return profiles.where((p) => seen.add(p.token)).toList();
  }

  Future<String> _streamUri(Uri mediaUri, String token) async {
    final xml = await _soap(
      mediaUri,
      'http://www.onvif.org/ver10/media/wsdl/GetStreamUri',
      '<trt:GetStreamUri xmlns:trt="http://www.onvif.org/ver10/media/wsdl"><trt:StreamSetup><tt:Stream xmlns:tt="http://www.onvif.org/ver10/schema">RTP-Unicast</tt:Stream><tt:Transport xmlns:tt="http://www.onvif.org/ver10/schema"><tt:Protocol>RTSP</tt:Protocol></tt:Transport></trt:StreamSetup><trt:ProfileToken>${_xmlEscape(token)}</trt:ProfileToken></trt:GetStreamUri>',
    );
    final value = _xmlValue(xml, 'Uri');
    if (value == null || value.trim().isEmpty) return '';
    return _xmlUnescape(value.trim());
  }

  Future<String> _soap(
    Uri uri,
    String action,
    String body, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final envelope = _soapEnvelope(body);
    final first = await _rawRequest(uri, action, envelope, null, timeout);
    if (first.statusCode >= 200 && first.statusCode < 300) {
      _throwOnSoapFault(first.body, uri);
      return first.body;
    }
    if (first.statusCode != HttpStatus.unauthorized) {
      throw HttpException('ONVIF HTTP ${first.statusCode}', uri: uri);
    }

    final challenge = first.wwwAuthenticate;
    if (challenge == null || challenge.isEmpty) {
      throw HttpException('Authentication challenge missing', uri: uri);
    }
    final lower = challenge.toLowerCase();
    final authorization = lower.startsWith('basic')
        ? 'Basic ${base64Encode(utf8.encode('$username:$password'))}'
        : lower.startsWith('digest')
            ? _digestAuthorization(challenge, 'POST', uri)
            : throw HttpException('Unsupported HTTP authentication', uri: uri);

    final second = await _rawRequest(uri, action, envelope, authorization, timeout);
    if (second.statusCode < 200 || second.statusCode >= 300) {
      throw HttpException('ONVIF HTTP ${second.statusCode}', uri: uri);
    }
    _throwOnSoapFault(second.body, uri);
    return second.body;
  }

  Future<_HttpResult> _rawRequest(
    Uri uri,
    String action,
    String body,
    String? authorization,
    Duration timeout,
  ) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.postUrl(uri).timeout(const Duration(seconds: 7));
      request.headers.contentType = ContentType('application', 'soap+xml', charset: 'utf-8');
      request.headers.set('SOAPAction', action);
      if (authorization != null) {
        request.headers.set(HttpHeaders.authorizationHeader, authorization);
      }
      request.write(body);
      final response = await request.close().timeout(timeout);
      final text = await utf8.decoder.bind(response).join();
      return _HttpResult(
        response.statusCode,
        text,
        response.headers.value(HttpHeaders.wwwAuthenticateHeader),
      );
    } finally {
      client.close(force: true);
    }
  }

  String _digestAuthorization(String challenge, String method, Uri uri) {
    final params = <String, String>{};
    for (final match in RegExp(r'(\w+)=(?:"([^"]*)"|([^,\s]+))').allMatches(challenge)) {
      params[match.group(1)!.toLowerCase()] = match.group(2) ?? match.group(3) ?? '';
    }
    final realm = params['realm'] ?? '';
    final nonce = params['nonce'];
    if (nonce == null || nonce.isEmpty) throw const HttpException('Digest nonce missing');
    final algorithm = (params['algorithm'] ?? 'MD5').toUpperCase();
    if (algorithm != 'MD5') throw HttpException('Unsupported digest algorithm $algorithm');

    final digestUri = uri.path.isEmpty
        ? '/'
        : (uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path);
    final ha1 = md5.convert(utf8.encode('$username:$realm:$password')).toString();
    final ha2 = md5.convert(utf8.encode('$method:$digestUri')).toString();
    final qops = (params['qop'] ?? '')
        .split(',')
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toSet();

    String response;
    String suffix = '';
    if (qops.contains('auth')) {
      const nc = '00000001';
      final cnonce = List<int>.generate(8, (_) => Random.secure().nextInt(256))
          .map((value) => value.toRadixString(16).padLeft(2, '0'))
          .join();
      response = md5.convert(utf8.encode('$ha1:$nonce:$nc:$cnonce:auth:$ha2')).toString();
      suffix = ', qop=auth, nc=$nc, cnonce="$cnonce"';
    } else {
      response = md5.convert(utf8.encode('$ha1:$nonce:$ha2')).toString();
    }

    final opaque = params['opaque'];
    return 'Digest username="$username", realm="$realm", nonce="$nonce", uri="$digestUri", response="$response"$suffix${opaque == null ? '' : ', opaque="$opaque"'}';
  }

  String _soapEnvelope(String body) {
    final created = DateTime.now().toUtc().toIso8601String();
    final nonceBytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final digest = base64Encode(
      sha1.convert(<int>[
        ...nonceBytes,
        ...utf8.encode(created),
        ...utf8.encode(password),
      ]).bytes,
    );
    final nonce = base64Encode(nonceBytes);
    return '<?xml version="1.0" encoding="UTF-8"?>'
        '<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope" xmlns:wsse="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd" xmlns:wsu="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd">'
        '<s:Header><wsse:Security s:mustUnderstand="1"><wsse:UsernameToken>'
        '<wsse:Username>${_xmlEscape(username)}</wsse:Username>'
        '<wsse:Password Type="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-username-token-profile-1.0#PasswordDigest">$digest</wsse:Password>'
        '<wsse:Nonce EncodingType="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-soap-message-security-1.0#Base64Binary">$nonce</wsse:Nonce>'
        '<wsu:Created>$created</wsu:Created>'
        '</wsse:UsernameToken></wsse:Security></s:Header><s:Body>$body</s:Body></s:Envelope>';
  }

  void _throwOnSoapFault(String xml, Uri uri) {
    if (RegExp(r'<(?:\w+:)?Fault\b', caseSensitive: false).hasMatch(xml)) {
      throw HttpException(
        _xmlValue(xml, 'Text') ?? _xmlValue(xml, 'faultstring') ?? 'ONVIF SOAP fault',
        uri: uri,
      );
    }
  }

  String? _xmlValue(String xml, String localName) => _firstMatch(
        xml,
        RegExp(
          '<(?:\\w+:)?$localName\\b[^>]*>(.*?)</(?:\\w+:)?$localName>',
          dotAll: true,
          caseSensitive: false,
        ),
      );

  String? _attribute(String attrs, String name) => _firstMatch(
        attrs,
        RegExp('\\b$name=["\\\']([^"\\\']*)["\\\']', caseSensitive: false),
      );

  String? _firstMatch(String input, RegExp pattern) => pattern.firstMatch(input)?.group(1);

  String _xmlEscape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  String _xmlUnescape(String value) => value
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'");
}

class _ProfileDescriptor {
  const _ProfileDescriptor({
    required this.token,
    required this.name,
    required this.width,
    required this.height,
  });

  final String token;
  final String name;
  final int? width;
  final int? height;
}

class _HttpResult {
  const _HttpResult(this.statusCode, this.body, this.wwwAuthenticate);

  final int statusCode;
  final String body;
  final String? wwwAuthenticate;
}
