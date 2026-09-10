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

class OnvifSupportedAnalyticsModule {
  const OnvifSupportedAnalyticsModule({
    required this.name,
    required this.type,
    required this.maxInstances,
    required this.parameters,
  });

  final String name;
  final String type;
  final int? maxInstances;
  final List<String> parameters;
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
    const preferred = <String>[
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

  String get stableFingerprint {
    final ordered = values.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    final valuesPart = ordered.map((e) => '${e.key}=${e.value}').join(';');
    return '${utcTime?.toUtc().toIso8601String() ?? ''}|$topic|${operation ?? ''}|$valuesPart';
  }
}

class OnvifEventSession {
  const OnvifEventSession({
    required this.pullPointUri,
    required this.terminationTime,
    required this.currentTime,
    required this.createdAt,
  });

  final Uri pullPointUri;
  final DateTime? terminationTime;
  final DateTime? currentTime;
  final DateTime createdAt;

  bool shouldRenew({
    Duration margin = const Duration(seconds: 90),
    Duration fallbackAge = const Duration(minutes: 8),
  }) {
    final now = DateTime.now().toUtc();
    final termination = terminationTime?.toUtc();
    if (termination != null) return !now.isBefore(termination.subtract(margin));
    return now.difference(createdAt.toUtc()) >= fallbackAge;
  }
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
    final uri = (await readServiceAddresses()).analytics;
    if (uri == null) {
      throw UnsupportedError('Camera did not report an ONVIF Analytics service');
    }
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
      r'''<(?:\w+:)?AnalyticsModule\b([^>]*)>''',
      caseSensitive: false,
    );
    for (final match in pattern.allMatches(xml)) {
      final attrs = match.group(1) ?? '';
      final name = _attribute(attrs, 'Name') ?? '';
      final type = _attribute(attrs, 'Type') ?? '';
      modules.add(OnvifAnalyticsModule(
        name: _xmlUnescape(name).trim(),
        type: _xmlUnescape(type).trim(),
      ));
    }
    return modules;
  }

  Future<List<OnvifSupportedAnalyticsModule>> getSupportedAnalyticsModules(
    String configurationToken,
  ) async {
    final uri = (await readServiceAddresses()).analytics;
    if (uri == null) {
      throw UnsupportedError('Camera did not report an ONVIF Analytics service');
    }
    if (configurationToken.trim().isEmpty) {
      throw const FormatException('Video analytics configuration token is missing');
    }
    final xml = await _soap(
      uri,
      'http://www.onvif.org/ver20/analytics/wsdl/GetSupportedAnalyticsModules',
      '<tan:GetSupportedAnalyticsModules xmlns:tan="http://www.onvif.org/ver20/analytics/wsdl"><tan:ConfigurationToken>${_xmlEscape(configurationToken)}</tan:ConfigurationToken></tan:GetSupportedAnalyticsModules>',
    );

    final modules = <OnvifSupportedAnalyticsModule>[];
    final pattern = RegExp(
      r'''<(?:\w+:)?AnalyticsModuleDescription\b([^>]*)>(.*?)</(?:\w+:)?AnalyticsModuleDescription>''',
      dotAll: true,
      caseSensitive: false,
    );
    for (final match in pattern.allMatches(xml)) {
      final attrs = match.group(1) ?? '';
      final block = match.group(2) ?? '';
      final name = _xmlUnescape(_attribute(attrs, 'Name') ?? '').trim();
      final type = _xmlUnescape(_attribute(attrs, 'Type') ?? '').trim();
      final maxInstances = int.tryParse(
        _attribute(attrs, 'maxInstances') ??
            _attribute(attrs, 'MaxInstances') ??
            '',
      );
      final parameters = <String>{};
      final parameterPattern = RegExp(
        r'''<(?:\w+:)?(?:SimpleItemDescription|ElementItemDescription)\b([^>]*)>''',
        caseSensitive: false,
      );
      for (final parameter in parameterPattern.allMatches(block)) {
        final parameterName = _attribute(parameter.group(1) ?? '', 'Name');
        if (parameterName != null && parameterName.trim().isNotEmpty) {
          parameters.add(_xmlUnescape(parameterName).trim());
        }
      }
      modules.add(OnvifSupportedAnalyticsModule(
        name: name,
        type: type,
        maxInstances: maxInstances,
        parameters: parameters.toList()..sort(),
      ));
    }

    if (modules.isEmpty) {
      final fallback = RegExp(
        r'''<(?:\w+:)?ConfigDescription\b([^>]*)>''',
        caseSensitive: false,
      );
      for (final match in fallback.allMatches(xml)) {
        final attrs = match.group(1) ?? '';
        final name = _xmlUnescape(_attribute(attrs, 'Name') ?? '').trim();
        if (name.isEmpty) continue;
        modules.add(OnvifSupportedAnalyticsModule(
          name: name,
          type: '',
          maxInstances: int.tryParse(_attribute(attrs, 'maxInstances') ?? ''),
          parameters: const [],
        ));
      }
    }

    return modules;
  }

  Future<List<String>> getEventTopics() async {
    final uri = (await readServiceAddresses()).events;
    if (uri == null) {
      throw UnsupportedError('Camera did not report an ONVIF Events service');
    }
    final xml = await _soap(
      uri,
      'http://www.onvif.org/ver10/events/wsdl/EventPortType/GetEventPropertiesRequest',
      '<tev:GetEventProperties xmlns:tev="http://www.onvif.org/ver10/events/wsdl"/>',
    );
    final topics = <String>{};
    final elementPattern = RegExp(
      r'''<(?:\w+:)?(\w+)\b[^>]*wstop:topic=["']true["'][^>]*>''',
      caseSensitive: false,
    );
    for (final match in elementPattern.allMatches(xml)) {
      final value = match.group(1)?.trim();
      if (value != null && value.isNotEmpty) topics.add(value);
    }
    final descriptions = RegExp(
      r'''<(?:\w+:)?MessageDescription\b[^>]*\bIsProperty=["'](?:true|false)["'][^>]*>''',
      caseSensitive: false,
    ).allMatches(xml).length;
    if (descriptions > 0) topics.add('MessageDescription x$descriptions');
    return topics.toList()..sort();
  }

  Future<OnvifEventSession> createPullPointSubscription({
    Duration termination = const Duration(minutes: 10),
  }) async {
    final uri = (await readServiceAddresses()).events;
    if (uri == null) {
      throw UnsupportedError('Camera did not report an ONVIF Events service');
    }
    final minutes = max(1, termination.inMinutes);
    final xml = await _soap(
      uri,
      'http://www.onvif.org/ver10/events/wsdl/EventPortType/CreatePullPointSubscriptionRequest',
      '<tev:CreatePullPointSubscription xmlns:tev="http://www.onvif.org/ver10/events/wsdl"><tev:InitialTerminationTime>PT${minutes}M</tev:InitialTerminationTime></tev:CreatePullPointSubscription>',
    );
    final address = _xmlValue(xml, 'Address');
    if (address == null || address.trim().isEmpty) {
      throw const FormatException('PullPoint subscription address missing');
    }
    return OnvifEventSession(
      pullPointUri: Uri.parse(_xmlUnescape(address.trim())),
      terminationTime: _parseDate(_xmlValue(xml, 'TerminationTime')),
      currentTime: _parseDate(_xmlValue(xml, 'CurrentTime')),
      createdAt: DateTime.now().toUtc(),
    );
  }

  Future<OnvifEventSession> renewPullPointSubscription(
    OnvifEventSession session, {
    Duration termination = const Duration(minutes: 10),
  }) async {
    final minutes = max(1, termination.inMinutes);
    final xml = await _soap(
      session.pullPointUri,
      'http://docs.oasis-open.org/wsn/bw-2/SubscriptionManager/RenewRequest',
      '<wsnt:Renew xmlns:wsnt="http://docs.oasis-open.org/wsn/b-2"><wsnt:TerminationTime>PT${minutes}M</wsnt:TerminationTime></wsnt:Renew>',
    );
    return OnvifEventSession(
      pullPointUri: session.pullPointUri,
      terminationTime: _parseDate(_xmlValue(xml, 'TerminationTime')) ?? session.terminationTime,
      currentTime: _parseDate(_xmlValue(xml, 'CurrentTime')),
      createdAt: DateTime.now().toUtc(),
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
      // Best effort: the device also destroys expired subscription managers.
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
      final topic = _stripXml(_xmlValue(block, 'Topic')?.trim() ?? 'ONVIF event');
      final messageMatch = RegExp(
        r'<(?:\w+:)?Message\b([^>]*)>(.*?)</(?:\w+:)?Message>',
        dotAll: true,
        caseSensitive: false,
      ).firstMatch(block);
      final attrs = messageMatch?.group(1) ?? '';
      final messageBody = messageMatch?.group(2) ?? block;
      final values = <String, String>{};
      final simple = RegExp(
        r'''<(?:\w+:)?SimpleItem\b[^>]*\bName=["']([^"']+)["'][^>]*\bValue=["']([^"']*)["'][^>]*/?>''',
        caseSensitive: false,
      );
      for (final item in simple.allMatches(messageBody)) {
        final name = _xmlUnescape(item.group(1) ?? '').trim();
        if (name.isNotEmpty) {
          values[name] = _xmlUnescape(item.group(2) ?? '').trim();
        }
      }
      final utcRaw = _attribute(attrs, 'UtcTime');
      out.add(OnvifCameraEvent(
        topic: _xmlUnescape(topic),
        utcTime: utcRaw == null ? null : DateTime.tryParse(utcRaw),
        values: values,
        operation: _attribute(attrs, 'PropertyOperation'),
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
    final envelope = _soapEnvelope(uri, action, body);
    final first = await _rawRequest(uri, action, envelope, null, timeout);
    if (first.statusCode >= 200 && first.statusCode < 300) {
      _throwOnSoapFault(first.body, uri);
      return first.body;
    }
    if (first.statusCode != 401) {
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
    String? auth,
    Duration timeout,
  ) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.postUrl(uri).timeout(const Duration(seconds: 7));
      request.headers.contentType = ContentType('application', 'soap+xml', charset: 'utf-8');
      request.headers.set('SOAPAction', action);
      if (auth != null) {
        request.headers.set(HttpHeaders.authorizationHeader, auth);
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

  void _throwOnSoapFault(String xml, Uri uri) {
    if (RegExp(r'<(?:\w+:)?Fault\b', caseSensitive: false).hasMatch(xml)) {
      throw HttpException(
        _xmlValue(xml, 'Text') ??
            _xmlValue(xml, 'faultstring') ??
            'ONVIF SOAP fault',
        uri: uri,
      );
    }
  }

  String _digestAuthorization(String challenge, String method, Uri uri) {
    final params = <String, String>{};
    for (final match in RegExp(r'(\w+)=(?:"([^"]*)"|([^,\s]+))').allMatches(challenge)) {
      params[match.group(1)!.toLowerCase()] = match.group(2) ?? match.group(3) ?? '';
    }
    final realm = params['realm'] ?? '';
    final nonce = params['nonce'];
    if (nonce == null || nonce.isEmpty) {
      throw const HttpException('Digest nonce missing');
    }
    final algorithm = (params['algorithm'] ?? 'MD5').toUpperCase();
    final digestUri = uri.path.isEmpty
        ? '/'
        : (uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path);

    String hashValue(String value) {
      switch (algorithm) {
        case 'MD5':
        case 'MD5-SESS':
          return md5.convert(utf8.encode(value)).toString();
        case 'SHA-256':
        case 'SHA-256-SESS':
          return sha256.convert(utf8.encode(value)).toString();
        default:
          throw HttpException('Unsupported digest algorithm $algorithm');
      }
    }

    final qops = (params['qop'] ?? '')
        .split(',')
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toList();
    if (qops.isNotEmpty && !qops.contains('auth')) {
      throw const HttpException('Digest auth-int is not supported');
    }

    final cnonce = List<int>.generate(
      12,
      (_) => Random.secure().nextInt(256),
    ).map((e) => e.toRadixString(16).padLeft(2, '0')).join();
    var ha1 = hashValue('$username:$realm:$password');
    if (algorithm.endsWith('-SESS')) {
      ha1 = hashValue('$ha1:$nonce:$cnonce');
    }
    final ha2 = hashValue('$method:$digestUri');

    String response;
    String suffix = '';
    if (qops.contains('auth')) {
      const nc = '00000001';
      response = hashValue('$ha1:$nonce:$nc:$cnonce:auth:$ha2');
      suffix = ', qop=auth, nc=$nc, cnonce="$cnonce"';
    } else {
      response = hashValue('$ha1:$nonce:$ha2');
    }

    final opaque = params['opaque'];
    final algorithmPart = params.containsKey('algorithm') ? ', algorithm=$algorithm' : '';
    return 'Digest username="$username", realm="$realm", nonce="$nonce", uri="$digestUri", response="$response"$algorithmPart$suffix${opaque == null ? '' : ', opaque="$opaque"'}';
  }

  String _soapEnvelope(Uri uri, String action, String body) {
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
    final messageId = 'urn:uuid:${_randomHex(16)}';
    return '<?xml version="1.0" encoding="UTF-8"?>'
        '<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope" '
        'xmlns:wsa="http://www.w3.org/2005/08/addressing" '
        'xmlns:wsse="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd" '
        'xmlns:wsu="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd">'
        '<s:Header>'
        '<wsa:Action s:mustUnderstand="1">${_xmlEscape(action)}</wsa:Action>'
        '<wsa:MessageID>$messageId</wsa:MessageID>'
        '<wsa:To s:mustUnderstand="1">${_xmlEscape(uri.toString())}</wsa:To>'
        '<wsse:Security s:mustUnderstand="1"><wsse:UsernameToken>'
        '<wsse:Username>${_xmlEscape(username)}</wsse:Username>'
        '<wsse:Password Type="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-username-token-profile-1.0#PasswordDigest">$digest</wsse:Password>'
        '<wsse:Nonce EncodingType="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-soap-message-security-1.0#Base64Binary">$nonce</wsse:Nonce>'
        '<wsu:Created>$created</wsu:Created>'
        '</wsse:UsernameToken></wsse:Security>'
        '</s:Header><s:Body>$body</s:Body></s:Envelope>';
  }

  String _randomHex(int bytes) => List<int>.generate(
        bytes,
        (_) => Random.secure().nextInt(256),
      ).map((e) => e.toRadixString(16).padLeft(2, '0')).join();

  DateTime? _parseDate(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return DateTime.tryParse(_xmlUnescape(value.trim()))?.toUtc();
  }

  String? _serviceXAddr(String xml, String serviceName) => _firstMatch(
        xml,
        RegExp(
          '<(?:\\w+:)?$serviceName\\b[^>]*>.*?<(?:\\w+:)?XAddr>(.*?)</(?:\\w+:)?XAddr>',
          dotAll: true,
          caseSensitive: false,
        ),
      );
  Uri? _parseUri(String? value) => value == null || value.trim().isEmpty
      ? null
      : Uri.tryParse(_xmlUnescape(value.trim()));
  String? _xmlValue(String xml, String localName) => _firstMatch(
        xml,
        RegExp(
          '<(?:\\w+:)?$localName\\b[^>]*>(.*?)</(?:\\w+:)?$localName>',
          dotAll: true,
          caseSensitive: false,
        ),
      );
  String? _firstMatch(String input, RegExp pattern) => pattern.firstMatch(input)?.group(1);
  String? _attribute(String attrs, String name) => _firstMatch(
        attrs,
        RegExp('\\b$name=["\\\']([^"\\\']*)["\\\']', caseSensitive: false),
      );
  String _stripXml(String value) => value.replaceAll(RegExp(r'<[^>]+>'), '').trim();
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
