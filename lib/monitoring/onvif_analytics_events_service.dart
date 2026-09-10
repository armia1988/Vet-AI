import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

class OnvifAnalyticsModule {
  const OnvifAnalyticsModule({required this.name, required this.type});
  final String name;
  final String type;
}

class OnvifCameraEvent {
  const OnvifCameraEvent({
    required this.topic,
    required this.utcTime,
    required this.values,
    this.operation,
  });

  final String topic;
  final DateTime? utcTime;
  final Map<String, String> values;
  final String? operation;

  String get summary {
    if (values.isEmpty) return topic;
    final preferred = <String>[
      'State',
      'IsMotion',
      'Motion',
      'Rule',
      'RuleName',
      'ObjectId',
      'Temperature',
      'MaxTemperature',
      'Alarm',
    ];
    for (final key in preferred) {
      final value = values[key];
      if (value != null && value.isNotEmpty) return '$key: $value';
    }
    final first = values.entries.first;
    return '${first.key}: ${first.value}';
  }
}

class OnvifEventSession {
  const OnvifEventSession({
    required this.pullPointUri,
    required this.terminationTime,
  });

  final Uri pullPointUri;
  final DateTime? terminationTime;
}

class OnvifAnalyticsEventsService {
  const OnvifAnalyticsEventsService({
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

  Future<_ServiceAddresses> readServiceAddresses() async {
    final xml = await _soap(
      _deviceUri,
      'http://www.onvif.org/ver10/device/wsdl/GetCapabilities',
      '<tds:GetCapabilities xmlns:tds="http://www.onvif.org/ver10/device/wsdl"><tds:Category>All</tds:Category></tds:GetCapabilities>',
    );
    return _ServiceAddresses(
      analytics: _parseUri(_serviceXAddr(xml, 'Analytics')),
      events: _parseUri(_serviceXAddr(xml, 'Events')),
    );
  }

  Future<List<OnvifAnalyticsModule>> getAnalyticsModules(String configurationToken) async {
    final addresses = await readServiceAddresses();
    final uri = addresses.analytics;
    if (uri == null) throw UnsupportedError('Camera did not report an ONVIF Analytics service');
    if (configurationToken.trim().isEmpty) {
      throw const FormatException('Video analytics configuration token is missing');
    }
    final xml = await _soap(
      uri,
      'http://www.onvif.org/ver20/analytics/wsdl/GetAnalyticsModules',
      '<tan:GetAnalyticsModules xmlns:tan="http://www.onvif.org/ver20/analytics/wsdl"><tan:ConfigurationToken>${_xmlEscape(configurationToken)}</tan:ConfigurationToken></tan:GetAnalyticsModules>',
    );
    final modules = <OnvifAnalyticsModule>[];
    final pattern = RegExp(
      r'''<(?:\w+:)?AnalyticsModule\b[^>]*\bName=["']([^"']*)["'][^>]*\bType=["']([^"']*)["'][^>]*>''',
      caseSensitive: false,
    );
    for (final match in pattern.allMatches(xml)) {
      modules.add(OnvifAnalyticsModule(
        name: _xmlUnescape(match.group(1) ?? '').trim(),
        type: _xmlUnescape(match.group(2) ?? '').trim(),
      ));
    }
    return modules;
  }

  Future<List<String>> getEventTopics() async {
    final addresses = await readServiceAddresses();
    final uri = addresses.events;
    if (uri == null) throw UnsupportedError('Camera did not report an ONVIF Events service');
    final xml = await _soap(
      uri,
      'http://www.onvif.org/ver10/events/wsdl/EventPortType/GetEventPropertiesRequest',
      '<tev:GetEventProperties xmlns:tev="http://www.onvif.org/ver10/events/wsdl"/>',
    );
    final topics = <String>{};
    final elementPattern = RegExp(r'<(?:\w+:)?(\w+)\b[^>]*wstop:topic=["']true["'][^>]*>', caseSensitive: false);
    for (final match in elementPattern.allMatches(xml)) {
      final value = match.group(1)?.trim();
      if (value != null && value.isNotEmpty) topics.add(value);
    }
    final messageDescriptions = RegExp(
      r'''<(?:\w+:)?MessageDescription\b[^>]*\bIsProperty=["'](?:true|false)["'][^>]*>''',
      caseSensitive: false,
    ).allMatches(xml).length;
    if (messageDescriptions > 0) topics.add('MessageDescription x$messageDescriptions');
    return topics.toList()..sort();
  }

  Future<OnvifEventSession> createPullPointSubscription() async {
    final addresses = await readServiceAddresses();
    final uri = addresses.events;
    if (uri == null) throw UnsupportedError('Camera did not report an ONVIF Events service');
    final xml = await _soap(
      uri,
      'http://www.onvif.org/ver10/events/wsdl/EventPortType/CreatePullPointSubscriptionRequest',
      '<tev:CreatePullPointSubscription xmlns:tev="http://www.onvif.org/ver10/events/wsdl"><tev:InitialTerminationTime>PT10M</tev:InitialTerminationTime></tev:CreatePullPointSubscription>',
    );
    final address = _xmlValue(xml, 'Address');
    if (address == null || address.trim().isEmpty) {
      throw const FormatException('PullPoint subscription address missing');
    }
    final termination = _xmlValue(xml, 'TerminationTime');
    return OnvifEventSession(
      pullPointUri: Uri.parse(_xmlUnescape(address.trim())),
      terminationTime: termination == null ? null : DateTime.tryParse(termination.trim()),
    );
  }

  Future<List<OnvifCameraEvent>> pullMessages(
    OnvifEventSession session, {
    Duration timeout = const Duration(seconds: 5),
    int messageLimit = 20,
  }) async {
    final seconds = timeout.inSeconds.clamp(1, 30);
    final limit = messageLimit.clamp(1, 100);
    final xml = await _soap(
      session.pullPointUri,
      'http://www.onvif.org/ver10/events/wsdl/PullPointSubscription/PullMessagesRequest',
      '<tev:PullMessages xmlns:tev="http://www.onvif.org/ver10/events/wsdl"><tev:Timeout>PT${seconds}S</tev:Timeout><tev:MessageLimit>$limit</tev:MessageLimit></tev:PullMessages>',
      timeout: Duration(seconds: seconds + 6),
    );
    return _parseNotificationMessages(xml);
  }

  Future<void> unsubscribe(OnvifEventSession session) async {
    try {
      await _soap(
        session.pullPointUri,
        'http://docs.oasis-open.org/wsn/bw-2/SubscriptionManager/UnsubscribeRequest',
        '<wsnt:Unsubscribe xmlns:wsnt="http://docs.oasis-open.org/wsn/b-2"/>',
      );
    } catch (_) {
      // Subscription may already have expired or the camera may not expose unsubscribe.
    }
  }

  List<OnvifCameraEvent> _parseNotificationMessages(String xml) {
    final out = <OnvifCameraEvent>[];
    final pattern = RegExp(
      r'<(?:\w+:)?NotificationMessage\b[^>]*>(.*?)</(?:\w+:)?NotificationMessage>',
      dotAll: true,
      caseSensitive: false,
    );
    for (final match in pattern.allMatches(xml)) {
      final block = match.group(1) ?? '';
      final topicRaw = _xmlValue(block, 'Topic')?.trim() ?? 'ONVIF event';
      final topic = _stripXml(topicRaw);
      final messageMatch = RegExp(r'<(?:\w+:)?Message\b([^>]*)>(.*?)</(?:\w+:)?Message>', dotAll: true, caseSensitive: false).firstMatch(block);
      final attrs = messageMatch?.group(1) ?? '';
      final messageBody = messageMatch?.group(2) ?? block;
      final utcRaw = _attribute(attrs, 'UtcTime');
      final operation = _attribute(attrs, 'PropertyOperation');
      final values = <String, String>{};
      final simple = RegExp(
        r'''<(?:\w+:)?SimpleItem\b[^>]*\bName=["']([^"']+)["'][^>]*\bValue=["']([^"']*)["'][^>]*/?>''',
        caseSensitive: false,
      );
      for (final item in simple.allMatches(messageBody)) {
        final name = _xmlUnescape(item.group(1) ?? '').trim();
        if (name.isEmpty) continue;
        values[name] = _xmlUnescape(item.group(2) ?? '').trim();
      }
      out.add(OnvifCameraEvent(
        topic: _xmlUnescape(topic),
        utcTime: utcRaw == null ? null : DateTime.tryParse(utcRaw),
        values: values,
        operation: operation,
      ));
    }
    return out;
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
    if (first.statusCode != 401) throw HttpException('ONVIF HTTP ${first.statusCode}', uri: uri);
    final challenge = first.wwwAuthenticate;
    if (challenge == null || challenge.isEmpty) throw HttpException('Authentication challenge missing', uri: uri);
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

  Future<_HttpResult> _rawRequest(Uri uri, String action, String body, String? auth, Duration timeout) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.postUrl(uri).timeout(const Duration(seconds: 7));
      request.headers.contentType = ContentType('application', 'soap+xml', charset: 'utf-8');
      request.headers.set('SOAPAction', action);
      if (auth != null) request.headers.set(HttpHeaders.authorizationHeader, auth);
      request.write(body);
      final response = await request.close().timeout(timeout);
      final text = await utf8.decoder.bind(response).join();
      return _HttpResult(response.statusCode, text, response.headers.value(HttpHeaders.wwwAuthenticateHeader));
    } finally {
      client.close(force: true);
    }
  }

  void _throwOnSoapFault(String xml, Uri uri) {
    if (!RegExp(r'<(?:\w+:)?Fault\b', caseSensitive: false).hasMatch(xml)) return;
    throw HttpException(_xmlValue(xml, 'Text') ?? _xmlValue(xml, 'faultstring') ?? 'ONVIF SOAP fault', uri: uri);
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
    final digestUri = uri.path.isEmpty ? '/' : (uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path);
    final ha1 = md5.convert(utf8.encode('$username:$realm:$password')).toString();
    final ha2 = md5.convert(utf8.encode('$method:$digestUri')).toString();
    final qopValues = (params['qop'] ?? '').split(',').map((e) => e.trim().toLowerCase()).toList();
    final useAuth = qopValues.contains('auth');
    String response;
    String suffix = '';
    if (useAuth) {
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
    final digest = base64Encode(sha1.convert(<int>[...nonceBytes, ...utf8.encode(created), ...utf8.encode(password)]).bytes);
    final nonce = base64Encode(nonceBytes);
    return '<?xml version="1.0" encoding="UTF-8"?>'
        '<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope" xmlns:wsse="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd" xmlns:wsu="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd">'
        '<s:Header><wsse:Security s:mustUnderstand="1"><wsse:UsernameToken>'
        '<wsse:Username>${_xmlEscape(username)}</wsse:Username>'
        '<wsse:Password Type="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-username-token-profile-1.0#PasswordDigest">$digest</wsse:Password>'
        '<wsse:Nonce EncodingType="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-soap-message-security-1.0#Base64Binary">$nonce</wsse:Nonce>'
        '<wsu:Created>$created</wsu:Created></wsse:UsernameToken></wsse:Security></s:Header><s:Body>$body</s:Body></s:Envelope>';
  }

  String? _serviceXAddr(String xml, String serviceName) => _firstMatch(
        xml,
        RegExp('<(?:\\w+:)?$serviceName\\b[^>]*>.*?<(?:\\w+:)?XAddr>(.*?)</(?:\\w+:)?XAddr>', dotAll: true, caseSensitive: false),
      );
  Uri? _parseUri(String? value) => value == null || value.trim().isEmpty ? null : Uri.tryParse(_xmlUnescape(value.trim()));
  String? _xmlValue(String xml, String localName) => _firstMatch(
        xml,
        RegExp('<(?:\\w+:)?$localName\\b[^>]*>(.*?)</(?:\\w+:)?$localName>', dotAll: true, caseSensitive: false),
      );
  String? _firstMatch(String input, RegExp pattern) => pattern.firstMatch(input)?.group(1);
  String? _attribute(String attrs, String name) => _firstMatch(attrs, RegExp('\\b$name=["\']([^"\']*)["\']', caseSensitive: false));
  String _stripXml(String value) => value.replaceAll(RegExp(r'<[^>]+>'), '').trim();
  String _xmlEscape(String value) => value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll("'", '&apos;');
  String _xmlUnescape(String value) => value.replaceAll('&amp;', '&').replaceAll('&lt;', '<').replaceAll('&gt;', '>').replaceAll('&quot;', '"').replaceAll('&apos;', "'");
}

class _ServiceAddresses {
  const _ServiceAddresses({this.analytics, this.events});
  final Uri? analytics;
  final Uri? events;
}

class _HttpResult {
  const _HttpResult(this.statusCode, this.body, this.wwwAuthenticate);
  final int statusCode;
  final String body;
  final String? wwwAuthenticate;
}
