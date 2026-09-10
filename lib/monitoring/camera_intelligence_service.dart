import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

class CameraIntelligenceCapabilities {
  const CameraIntelligenceCapabilities({
    required this.manufacturer,
    required this.model,
    required this.firmwareVersion,
    required this.serialNumber,
    required this.onvifAnalytics,
    required this.onvifEvents,
    required this.videoAnalyticsConfigurationToken,
    required this.thermalSupported,
    required this.realtimeThermometry,
    required this.faceThermometry,
    required this.fireDetection,
    required this.clickToThermometry,
    this.thermalMode,
  });

  final String manufacturer;
  final String model;
  final String firmwareVersion;
  final String serialNumber;
  final bool onvifAnalytics;
  final bool onvifEvents;
  final String? videoAnalyticsConfigurationToken;
  final bool thermalSupported;
  final bool realtimeThermometry;
  final bool faceThermometry;
  final bool fireDetection;
  final bool clickToThermometry;
  final String? thermalMode;
}

class ThermalRuleTemperature {
  const ThermalRuleTemperature({
    required this.maxCelsius,
    required this.minCelsius,
    required this.averageCelsius,
    this.maxPointX,
    this.maxPointY,
  });

  final double maxCelsius;
  final double minCelsius;
  final double averageCelsius;
  final double? maxPointX;
  final double? maxPointY;
}

class CameraIntelligenceService {
  const CameraIntelligenceService({
    required this.host,
    required this.httpPort,
    required this.username,
    required this.password,
    this.vendorHint,
  });

  final String host;
  final int httpPort;
  final String username;
  final String password;
  final String? vendorHint;

  Uri get _deviceUri => Uri.parse('http://$host:$httpPort/onvif/device_service');
  Uri _httpUri(String path) => Uri.parse('http://$host:$httpPort$path');

  Future<CameraIntelligenceCapabilities> readCapabilities() async {
    String manufacturer = vendorHint?.trim() ?? '';
    String model = '';
    String firmware = '';
    String serial = '';
    bool onvifAnalytics = false;
    bool onvifEvents = false;
    String? videoAnalyticsToken;

    try {
      final infoXml = await _soap(
        _deviceUri,
        'http://www.onvif.org/ver10/device/wsdl/GetDeviceInformation',
        '<tds:GetDeviceInformation xmlns:tds="http://www.onvif.org/ver10/device/wsdl"/>',
      );
      manufacturer = _xmlValue(infoXml, 'Manufacturer')?.trim() ?? manufacturer;
      model = _xmlValue(infoXml, 'Model')?.trim() ?? '';
      firmware = _xmlValue(infoXml, 'FirmwareVersion')?.trim() ?? '';
      serial = _xmlValue(infoXml, 'SerialNumber')?.trim() ?? '';
    } catch (_) {}

    try {
      final capsXml = await _soap(
        _deviceUri,
        'http://www.onvif.org/ver10/device/wsdl/GetCapabilities',
        '<tds:GetCapabilities xmlns:tds="http://www.onvif.org/ver10/device/wsdl"><tds:Category>All</tds:Category></tds:GetCapabilities>',
      );
      onvifAnalytics = _serviceXAddr(capsXml, 'Analytics') != null;
      onvifEvents = _serviceXAddr(capsXml, 'Events') != null;

      final mediaXAddr = _serviceXAddr(capsXml, 'Media') ?? _serviceXAddr(capsXml, 'Media2');
      if (mediaXAddr != null) {
        final profilesXml = await _soap(
          Uri.parse(_xmlUnescape(mediaXAddr)),
          'http://www.onvif.org/ver10/media/wsdl/GetProfiles',
          '<trt:GetProfiles xmlns:trt="http://www.onvif.org/ver10/media/wsdl"/>',
        );
        videoAnalyticsToken = _firstMatch(
          profilesXml,
          RegExp(r'''<(?:\w+:)?VideoAnalyticsConfiguration\b[^>]*\btoken=["']([^"']+)["']''', caseSensitive: false),
        );
        if (videoAnalyticsToken != null && videoAnalyticsToken.isNotEmpty) {
          onvifAnalytics = true;
        }
      }
    } catch (_) {}

    bool thermalSupported = false;
    bool realtimeThermometry = false;
    bool faceThermometry = false;
    bool fireDetection = false;
    bool clickToThermometry = false;
    String? thermalMode;

    final vendor = manufacturer.toLowerCase();
    final hint = (vendorHint ?? '').toLowerCase();
    final mayBeHikvision = vendor.contains('hikvision') || vendor.contains('hikmicro') || hint.contains('hikvision') || hint.contains('hikmicro');

    if (mayBeHikvision) {
      try {
        final thermalXml = await _get(_httpUri('/ISAPI/Thermal/capabilities'));
        thermalSupported = _xmlBool(thermalXml, 'isSupportThermometry') ||
            _xmlBool(thermalXml, 'isSupportRealtimeThermometry') ||
            thermalXml.contains('ThermalCap');
        realtimeThermometry = _xmlBool(thermalXml, 'isSupportRealtimeThermometry');
        faceThermometry = _xmlBool(thermalXml, 'isSupportFaceThermometry');
        fireDetection = _xmlBool(thermalXml, 'isSupportFireDetection');
        clickToThermometry = _xmlBool(thermalXml, 'isSupportClickToThermometry');

        if (thermalSupported) {
          try {
            final modeXml = await _get(_httpUri('/ISAPI/Thermal/channels/1/thermometryMode'));
            thermalMode = _xmlValue(modeXml, 'mode')?.trim();
          } catch (_) {}
        }
      } catch (_) {}
    }

    return CameraIntelligenceCapabilities(
      manufacturer: manufacturer,
      model: model,
      firmwareVersion: firmware,
      serialNumber: serial,
      onvifAnalytics: onvifAnalytics,
      onvifEvents: onvifEvents,
      videoAnalyticsConfigurationToken: videoAnalyticsToken,
      thermalSupported: thermalSupported,
      realtimeThermometry: realtimeThermometry,
      faceThermometry: faceThermometry,
      fireDetection: fireDetection,
      clickToThermometry: clickToThermometry,
      thermalMode: thermalMode,
    );
  }

  Future<ThermalRuleTemperature> readThermalRuleTemperature({
    int channelId = 1,
    int sceneId = 1,
    int ruleId = 1,
  }) async {
    final uri = _httpUri('/ISAPI/Thermal/channels/$channelId/thermometry/$sceneId/rulesTemperatureInfo/$ruleId?format=json');
    final text = await _get(uri);
    final decoded = jsonDecode(text);
    if (decoded is! Map) throw const FormatException('Thermal response is not a JSON object');
    final root = Map<String, dynamic>.from(decoded.cast<String, dynamic>());
    final value = root['ThermometryRulesTemperatureInfo'];
    if (value is! Map) throw const FormatException('ThermometryRulesTemperatureInfo missing');
    final data = Map<String, dynamic>.from(value.cast<String, dynamic>());

    double requiredNumber(String key) {
      final raw = data[key];
      final parsed = raw is num ? raw.toDouble() : double.tryParse(raw?.toString() ?? '');
      if (parsed == null) throw FormatException('$key missing from thermal result');
      return parsed;
    }

    double? nestedNumber(String objectKey, String key) {
      final obj = data[objectKey];
      if (obj is! Map) return null;
      final raw = obj[key];
      return raw is num ? raw.toDouble() : double.tryParse(raw?.toString() ?? '');
    }

    return ThermalRuleTemperature(
      maxCelsius: requiredNumber('maxTemperature'),
      minCelsius: requiredNumber('minTemperature'),
      averageCelsius: requiredNumber('averageTemperature'),
      maxPointX: nestedNumber('MaxTemperaturePoint', 'positionX'),
      maxPointY: nestedNumber('MaxTemperaturePoint', 'positionY'),
    );
  }

  Future<String> _get(Uri uri) => _request(uri: uri, method: 'GET');

  Future<String> _soap(Uri uri, String action, String body) {
    final envelope = _soapEnvelope(body);
    return _request(
      uri: uri,
      method: 'POST',
      body: envelope,
      soapAction: action,
      contentType: 'application/soap+xml; charset=utf-8',
    );
  }

  Future<String> _request({
    required Uri uri,
    required String method,
    String? body,
    String? soapAction,
    String? contentType,
  }) async {
    final first = await _rawRequest(
      uri: uri,
      method: method,
      body: body,
      soapAction: soapAction,
      contentType: contentType,
    );
    if (first.statusCode >= 200 && first.statusCode < 300) return first.body;
    if (first.statusCode != 401) throw HttpException('HTTP ${first.statusCode}', uri: uri);

    final challenge = first.wwwAuthenticate;
    if (challenge == null || challenge.isEmpty) throw HttpException('Authentication challenge missing', uri: uri);
    final lower = challenge.toLowerCase();
    String auth;
    if (lower.startsWith('basic')) {
      auth = 'Basic ${base64Encode(utf8.encode('$username:$password'))}';
    } else if (lower.startsWith('digest')) {
      auth = _httpDigestAuthorization(
        challenge: challenge,
        username: username,
        password: password,
        method: method,
        uri: uri,
      );
    } else {
      throw HttpException('Unsupported HTTP authentication', uri: uri);
    }

    final second = await _rawRequest(
      uri: uri,
      method: method,
      body: body,
      soapAction: soapAction,
      contentType: contentType,
      authorization: auth,
    );
    if (second.statusCode < 200 || second.statusCode >= 300) {
      throw HttpException('HTTP ${second.statusCode}', uri: uri);
    }
    return second.body;
  }

  Future<_HttpResponse> _rawRequest({
    required Uri uri,
    required String method,
    String? body,
    String? soapAction,
    String? contentType,
    String? authorization,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.openUrl(method, uri).timeout(const Duration(seconds: 7));
      if (contentType != null) request.headers.set(HttpHeaders.contentTypeHeader, contentType);
      if (soapAction != null) request.headers.set('SOAPAction', soapAction);
      if (authorization != null) request.headers.set(HttpHeaders.authorizationHeader, authorization);
      if (body != null) request.write(body);
      final response = await request.close().timeout(const Duration(seconds: 8));
      final text = await utf8.decoder.bind(response).join();
      return _HttpResponse(
        statusCode: response.statusCode,
        body: text,
        wwwAuthenticate: response.headers.value(HttpHeaders.wwwAuthenticateHeader),
      );
    } finally {
      client.close(force: true);
    }
  }

  String _httpDigestAuthorization({
    required String challenge,
    required String username,
    required String password,
    required String method,
    required Uri uri,
  }) {
    final params = <String, String>{};
    for (final match in RegExp(r'(\w+)=(?:"([^"]*)"|([^,\s]+))').allMatches(challenge)) {
      params[match.group(1)!.toLowerCase()] = match.group(2) ?? match.group(3) ?? '';
    }
    final realm = params['realm'] ?? '';
    final nonce = params['nonce'];
    if (nonce == null || nonce.isEmpty) throw const HttpException('Digest nonce missing');
    final algorithm = (params['algorithm'] ?? 'MD5').toUpperCase();
    if (algorithm != 'MD5') throw HttpException('Unsupported digest algorithm $algorithm');

    final digestUri = uri.path.isEmpty ? '/' : (uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path);
    final ha1 = md5.convert(utf8.encode('$username:$realm:$password')).toString();
    final ha2 = md5.convert(utf8.encode('$method:$digestUri')).toString();
    final qop = params['qop']?.split(',').map((e) => e.trim()).firstWhere((e) => e == 'auth', orElse: () => '');
    String response;
    String suffix = '';
    if (qop == 'auth') {
      const nc = '00000001';
      final cnonce = List<int>.generate(8, (_) => Random.secure().nextInt(256)).map((e) => e.toRadixString(16).padLeft(2, '0')).join();
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
    final digestInput = <int>[...nonceBytes, ...utf8.encode(created), ...utf8.encode(password)];
    final passwordDigest = base64Encode(sha1.convert(digestInput).bytes);
    final nonce = base64Encode(nonceBytes);
    return '<?xml version="1.0" encoding="UTF-8"?>'
        '<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope" xmlns:wsse="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd" xmlns:wsu="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd">'
        '<s:Header><wsse:Security s:mustUnderstand="1"><wsse:UsernameToken>'
        '<wsse:Username>${_xmlEscape(username)}</wsse:Username>'
        '<wsse:Password Type="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-username-token-profile-1.0#PasswordDigest">$passwordDigest</wsse:Password>'
        '<wsse:Nonce EncodingType="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-soap-message-security-1.0#Base64Binary">$nonce</wsse:Nonce>'
        '<wsu:Created>$created</wsu:Created></wsse:UsernameToken></wsse:Security></s:Header><s:Body>$body</s:Body></s:Envelope>';
  }

  String? _serviceXAddr(String xml, String serviceName) => _firstMatch(
        xml,
        RegExp('<(?:\\w+:)?$serviceName\\b[^>]*>.*?<(?:\\w+:)?XAddr>(.*?)</(?:\\w+:)?XAddr>', dotAll: true, caseSensitive: false),
      );
  bool _xmlBool(String xml, String name) => (_xmlValue(xml, name) ?? '').trim().toLowerCase() == 'true';
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
}

class _HttpResponse {
  const _HttpResponse({required this.statusCode, required this.body, required this.wwwAuthenticate});
  final int statusCode;
  final String body;
  final String? wwwAuthenticate;
}
