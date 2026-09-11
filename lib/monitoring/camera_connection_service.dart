import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

class CameraConnectionResult {
  const CameraConnectionResult({
    required this.success,
    required this.onvifOk,
    required this.rtspOk,
    this.streamUri,
    this.deviceInformation,
    this.message,
  });

  final bool success;
  final bool onvifOk;
  final bool rtspOk;
  final String? streamUri;
  final Map<String, String>? deviceInformation;
  final String? message;
}

class CameraConnectionService {
  const CameraConnectionService();

  Future<CameraConnectionResult> test({
    required String host,
    required int httpPort,
    required int rtspPort,
    required String username,
    required String password,
    required bool useOnvif,
    required bool useRtsp,
  }) async {
    bool onvifOk = false;
    bool rtspOk = false;
    String? streamUri;
    Map<String, String>? deviceInfo;
    final notes = <String>[];

    if (useOnvif) {
      try {
        final onvif = await _probeOnvif(
          host: host,
          port: httpPort,
          username: username,
          password: password,
        );
        onvifOk = true;
        streamUri = onvif.streamUri;
        deviceInfo = onvif.deviceInfo;
      } catch (e) {
        notes.add('ONVIF: ${_cleanError(e)}');
      }
    }

    if (useRtsp) {
      try {
        final uri = streamUri ?? 'rtsp://$host:$rtspPort/';
        await _probeRtsp(
          uri: uri,
          username: username,
          password: password,
        );
        rtspOk = true;
        streamUri ??= uri;
      } catch (e) {
        notes.add('RTSP: ${_cleanError(e)}');
      }
    }

    final success = (!useOnvif || onvifOk) && (!useRtsp || rtspOk);
    return CameraConnectionResult(
      success: success,
      onvifOk: onvifOk,
      rtspOk: rtspOk,
      streamUri: streamUri,
      deviceInformation: deviceInfo,
      message: notes.isEmpty ? null : notes.join('\n'),
    );
  }

  Future<_OnvifProbeResult> _probeOnvif({
    required String host,
    required int port,
    required String username,
    required String password,
  }) async {
    final deviceUri = Uri.parse('http://$host:$port/onvif/device_service');

    final deviceInfoBody = _soapEnvelope(
      username: username,
      password: password,
      body: '<tds:GetDeviceInformation xmlns:tds="http://www.onvif.org/ver10/device/wsdl"/>',
    );
    final infoResponse = await _postSoap(
      deviceUri,
      deviceInfoBody,
      'http://www.onvif.org/ver10/device/wsdl/GetDeviceInformation',
      username,
      password,
    );
    _throwOnSoapFault(infoResponse);

    final info = <String, String>{};
    for (final key in ['Manufacturer', 'Model', 'FirmwareVersion', 'SerialNumber', 'HardwareId']) {
      final value = _xmlValue(infoResponse, key);
      if (value != null && value.isNotEmpty) info[key] = value;
    }

    final capsBody = _soapEnvelope(
      username: username,
      password: password,
      body: '<tds:GetCapabilities xmlns:tds="http://www.onvif.org/ver10/device/wsdl"><tds:Category>Media</tds:Category></tds:GetCapabilities>',
    );
    final capsResponse = await _postSoap(
      deviceUri,
      capsBody,
      'http://www.onvif.org/ver10/device/wsdl/GetCapabilities',
      username,
      password,
    );
    _throwOnSoapFault(capsResponse);

    final mediaXAddr = _firstMatch(
          capsResponse,
          RegExp(r'<(?:\w+:)?Media[^>]*>.*?<\w*:XAddr>(.*?)</\w*:XAddr>', dotAll: true, caseSensitive: false),
        ) ??
        _firstMatch(
          capsResponse,
          RegExp(r'<(?:\w+:)?XAddr>(https?://[^<]+)</(?:\w+:)?XAddr>', caseSensitive: false),
        );
    final mediaUri = mediaXAddr == null ? deviceUri : Uri.parse(_xmlUnescape(mediaXAddr.trim()));

    final profilesBody = _soapEnvelope(
      username: username,
      password: password,
      body: '<trt:GetProfiles xmlns:trt="http://www.onvif.org/ver10/media/wsdl"/>',
    );
    final profilesResponse = await _postSoap(
      mediaUri,
      profilesBody,
      'http://www.onvif.org/ver10/media/wsdl/GetProfiles',
      username,
      password,
    );
    _throwOnSoapFault(profilesResponse);

    final token = _firstMatch(
      profilesResponse,
      RegExp(
        r'''<(?:\w+:)?Profiles\b[^>]*\btoken=["']([^"']+)["']''',
        caseSensitive: false,
      ),
    );
    if (token == null || token.isEmpty) {
      throw const FormatException('No ONVIF media profile returned');
    }

    final streamBody = _soapEnvelope(
      username: username,
      password: password,
      body: '<trt:GetStreamUri xmlns:trt="http://www.onvif.org/ver10/media/wsdl"><trt:StreamSetup><tt:Stream xmlns:tt="http://www.onvif.org/ver10/schema">RTP-Unicast</tt:Stream><tt:Transport xmlns:tt="http://www.onvif.org/ver10/schema"><tt:Protocol>RTSP</tt:Protocol></tt:Transport></trt:StreamSetup><trt:ProfileToken>${_xmlEscape(token)}</trt:ProfileToken></trt:GetStreamUri>',
    );
    final streamResponse = await _postSoap(
      mediaUri,
      streamBody,
      'http://www.onvif.org/ver10/media/wsdl/GetStreamUri',
      username,
      password,
    );
    _throwOnSoapFault(streamResponse);

    final streamUri = _xmlValue(streamResponse, 'Uri');
    return _OnvifProbeResult(
      streamUri: streamUri == null ? null : _xmlUnescape(streamUri.trim()),
      deviceInfo: info,
    );
  }

  Future<String> _postSoap(
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

  Future<void> _probeRtsp({
    required String uri,
    required String username,
    required String password,
  }) async {
    final parsed = Uri.parse(uri);
    final host = parsed.host;
    final port = parsed.hasPort ? parsed.port : 554;
    if (host.isEmpty) throw const FormatException('Invalid RTSP URI');

    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: const Duration(seconds: 5));
      final first = await _rtspRequest(socket, uri, null);
      if (first.statusCode >= 200 && first.statusCode < 400) return;
      if (first.statusCode != 401) {
        throw HttpException('RTSP ${first.statusCode}');
      }

      final auth = first.headers['www-authenticate'];
      if (auth == null || auth.isEmpty) throw const HttpException('RTSP authentication challenge missing');

      await socket.close();
      socket = await Socket.connect(host, port, timeout: const Duration(seconds: 5));
      String authorization;
      if (auth.toLowerCase().startsWith('digest')) {
        authorization = _digestAuthorization(
          challenge: auth,
          username: username,
          password: password,
          method: 'OPTIONS',
          uri: uri,
        );
      } else if (auth.toLowerCase().startsWith('basic')) {
        authorization = 'Basic ${base64Encode(utf8.encode('$username:$password'))}';
      } else {
        throw const HttpException('Unsupported RTSP authentication');
      }

      final second = await _rtspRequest(socket, uri, authorization);
      if (second.statusCode < 200 || second.statusCode >= 400) {
        throw HttpException('RTSP authentication failed (${second.statusCode}) — verify camera username/password and RTSP permission');
      }
    } finally {
      await socket?.close();
    }
  }

  Future<_RtspResponse> _rtspRequest(Socket socket, String uri, String? authorization) async {
    final lines = <String>[
      'OPTIONS $uri RTSP/1.0',
      'CSeq: 1',
      'User-Agent: VetAI/0.6.29',
      if (authorization != null) 'Authorization: $authorization',
      '',
      '',
    ];
    socket.write(lines.join('\r\n'));
    await socket.flush();

    final completer = Completer<String>();
    final buffer = StringBuffer();
    late StreamSubscription<List<int>> sub;
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

    final raw = await completer.future.timeout(const Duration(seconds: 5));
    await sub.cancel();
    final rows = raw.split('\r\n');
    final status = rows.isEmpty ? null : RegExp(r'RTSP/\d\.\d\s+(\d{3})').firstMatch(rows.first);
    if (status == null) throw const FormatException('Invalid RTSP response');
    final headers = <String, String>{};
    for (final row in rows.skip(1)) {
      final i = row.indexOf(':');
      if (i > 0) headers[row.substring(0, i).trim().toLowerCase()] = row.substring(i + 1).trim();
    }
    return _RtspResponse(int.parse(status.group(1)!), headers);
  }

  String _digestAuthorization({
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

  String _soapEnvelope({
    required String username,
    required String password,
    required String body,
  }) {
    final created = DateTime.now().toUtc().toIso8601String();
    final nonceBytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final digestInput = <int>[...nonceBytes, ...utf8.encode(created), ...utf8.encode(password)];
    final passwordDigest = base64Encode(sha1.convert(digestInput).bytes);
    final nonce = base64Encode(nonceBytes);
    return '<?xml version="1.0" encoding="UTF-8"?>'
        '<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope" xmlns:wsse="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd" xmlns:wsu="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd">'
        '<s:Header><wsse:Security s:mustUnderstand="1"><wsse:UsernameToken>'
        '<wsse:Username>${_xmlEscape(username)}</wsse:Username>'
        '<wsse:Password Type="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-username-token-profile-1.0#PasswordDigest">$passwordDigest</wsse:Password>'
        '<wsse:Nonce EncodingType="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-soap-message-security-1.0#Base64Binary">$nonce</wsse:Nonce>'
        '<wsu:Created>$created</wsu:Created>'
        '</wsse:UsernameToken></wsse:Security></s:Header><s:Body>$body</s:Body></s:Envelope>';
  }

  void _throwOnSoapFault(String xml) {
    if (RegExp(r'<(?:\w+:)?Fault\b', caseSensitive: false).hasMatch(xml)) {
      final reason = _xmlValue(xml, 'Text') ?? _xmlValue(xml, 'faultstring') ?? 'ONVIF SOAP fault';
      throw HttpException(reason);
    }
  }

  String? _xmlValue(String xml, String localName) => _firstMatch(
        xml,
        RegExp('<(?:\\w+:)?$localName\\b[^>]*>(.*?)</(?:\\w+:)?$localName>', dotAll: true, caseSensitive: false),
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

  String _cleanError(Object error) => error.toString().replaceFirst(RegExp(r'^\w+Exception:\s*'), '');
}

class _OnvifProbeResult {
  const _OnvifProbeResult({this.streamUri, required this.deviceInfo});
  final String? streamUri;
  final Map<String, String> deviceInfo;
}

class _RtspResponse {
  const _RtspResponse(this.statusCode, this.headers);
  final int statusCode;
  final Map<String, String> headers;
}


class _HttpSoapResponse {
  const _HttpSoapResponse(this.statusCode, this.body, this.wwwAuthenticate);
  final int statusCode;
  final String body;
  final String? wwwAuthenticate;
}
