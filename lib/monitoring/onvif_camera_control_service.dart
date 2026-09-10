import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

class OnvifCameraCapabilities {
  const OnvifCameraCapabilities({
    required this.profileToken,
    required this.mediaXAddr,
    this.ptzXAddr,
    this.imagingXAddr,
    this.eventsXAddr,
    this.ptzNodeToken,
    this.videoSourceToken,
    this.supportsContinuousMove = false,
    this.supportsRelativeMove = false,
    this.supportsAbsoluteMove = false,
    this.supportsPresets = false,
    this.imagingSupported = false,
  });

  final String profileToken;
  final Uri mediaXAddr;
  final Uri? ptzXAddr;
  final Uri? imagingXAddr;
  final Uri? eventsXAddr;
  final String? ptzNodeToken;
  final String? videoSourceToken;
  final bool supportsContinuousMove;
  final bool supportsRelativeMove;
  final bool supportsAbsoluteMove;
  final bool supportsPresets;
  final bool imagingSupported;

  bool get supportsPtz => ptzXAddr != null;
}

class OnvifPreset {
  const OnvifPreset({required this.token, required this.name});
  final String token;
  final String name;
}

class OnvifImagingSettings {
  const OnvifImagingSettings({
    this.brightness,
    this.contrast,
    this.colorSaturation,
    this.sharpness,
  });

  final double? brightness;
  final double? contrast;
  final double? colorSaturation;
  final double? sharpness;
}

class OnvifCameraControlService {
  const OnvifCameraControlService({
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

  Future<OnvifCameraCapabilities> readCapabilities() async {
    final capsXml = await _soap(
      _deviceUri,
      'http://www.onvif.org/ver10/device/wsdl/GetCapabilities',
      '<tds:GetCapabilities xmlns:tds="http://www.onvif.org/ver10/device/wsdl"><tds:Category>All</tds:Category></tds:GetCapabilities>',
    );

    final media = _serviceXAddr(capsXml, 'Media') ?? _serviceXAddr(capsXml, 'Media2') ?? _firstHttpXAddr(capsXml);
    if (media == null) throw const FormatException('Camera did not report an ONVIF Media service');
    final mediaUri = Uri.parse(_xmlUnescape(media));

    final profilesXml = await _soap(
      mediaUri,
      'http://www.onvif.org/ver10/media/wsdl/GetProfiles',
      '<trt:GetProfiles xmlns:trt="http://www.onvif.org/ver10/media/wsdl"/>',
    );
    final profileToken = _firstMatch(profilesXml, RegExp(r'''<(?:\w+:)?Profiles\b[^>]*\btoken=["']([^"']+)["']''', caseSensitive: false));
    if (profileToken == null || profileToken.isEmpty) throw const FormatException('Camera did not report an ONVIF media profile');

    final videoSourceToken = _firstMatch(
          profilesXml,
          RegExp(r'''<(?:\w+:)?VideoSourceConfiguration\b[^>]*\btoken=["']([^"']+)["'][^>]*>''', caseSensitive: false),
        ) ??
        _xmlValue(profilesXml, 'SourceToken');

    final ptzUri = _parseOptionalUri(_serviceXAddr(capsXml, 'PTZ'));
    final imagingUri = _parseOptionalUri(_serviceXAddr(capsXml, 'Imaging'));
    final eventsUri = _parseOptionalUri(_serviceXAddr(capsXml, 'Events'));

    String? ptzNodeToken;
    bool continuous = false;
    bool relative = false;
    bool absolute = false;
    bool presets = false;

    if (ptzUri != null) {
      try {
        final configXml = await _soap(
          ptzUri,
          'http://www.onvif.org/ver20/ptz/wsdl/GetConfiguration',
          '<tptz:GetConfiguration xmlns:tptz="http://www.onvif.org/ver20/ptz/wsdl"><tptz:PTZConfigurationToken>${_xmlEscape(profileToken)}</tptz:PTZConfigurationToken></tptz:GetConfiguration>',
          tolerateFault: true,
        );
        ptzNodeToken = _xmlValue(configXml, 'NodeToken');
      } catch (_) {}
      try {
        final nodesXml = await _soap(ptzUri, 'http://www.onvif.org/ver20/ptz/wsdl/GetNodes', '<tptz:GetNodes xmlns:tptz="http://www.onvif.org/ver20/ptz/wsdl"/>', tolerateFault: true);
        ptzNodeToken ??= _firstMatch(nodesXml, RegExp(r'''<(?:\w+:)?PTZNode\b[^>]*\btoken=["']([^"']+)["']''', caseSensitive: false));
        continuous = nodesXml.contains('ContinuousPanTiltVelocitySpace') || nodesXml.contains('ContinuousZoomVelocitySpace');
        relative = nodesXml.contains('RelativePanTiltTranslationSpace') || nodesXml.contains('RelativeZoomTranslationSpace');
        absolute = nodesXml.contains('AbsolutePanTiltPositionSpace') || nodesXml.contains('AbsoluteZoomPositionSpace');
        final fixedHome = _xmlValue(nodesXml, 'FixedHomePosition');
        presets = RegExp(r'<(?:\w+:)?MaximumNumberOfPresets\b[^>]*>([1-9]\d*)</', caseSensitive: false).hasMatch(nodesXml) || (fixedHome != null && fixedHome.toLowerCase() == 'true');
      } catch (_) {
        continuous = true;
      }
      try {
        final presetsXml = await _soap(
          ptzUri,
          'http://www.onvif.org/ver20/ptz/wsdl/GetPresets',
          '<tptz:GetPresets xmlns:tptz="http://www.onvif.org/ver20/ptz/wsdl"><tptz:ProfileToken>${_xmlEscape(profileToken)}</tptz:ProfileToken></tptz:GetPresets>',
          tolerateFault: true,
        );
        presets = presets || RegExp(r'<(?:\w+:)?Preset\b', caseSensitive: false).hasMatch(presetsXml);
      } catch (_) {}
    }

    bool imagingSupported = false;
    if (imagingUri != null && videoSourceToken != null && videoSourceToken.isNotEmpty) {
      try {
        imagingSupported = (await getImagingSettingsRaw(imagingUri, videoSourceToken)).isNotEmpty;
      } catch (_) {}
    }

    return OnvifCameraCapabilities(
      profileToken: profileToken,
      mediaXAddr: mediaUri,
      ptzXAddr: ptzUri,
      imagingXAddr: imagingUri,
      eventsXAddr: eventsUri,
      ptzNodeToken: ptzNodeToken,
      videoSourceToken: videoSourceToken,
      supportsContinuousMove: continuous,
      supportsRelativeMove: relative,
      supportsAbsoluteMove: absolute,
      supportsPresets: presets,
      imagingSupported: imagingSupported,
    );
  }

  Future<void> continuousMove({required OnvifCameraCapabilities capabilities, double pan = 0, double tilt = 0, double zoom = 0}) async {
    final uri = capabilities.ptzXAddr;
    if (uri == null || !capabilities.supportsContinuousMove) {
      throw UnsupportedError('Continuous PTZ is not reported by this camera');
    }
    final body = StringBuffer()
      ..write('<tptz:ContinuousMove xmlns:tptz="http://www.onvif.org/ver20/ptz/wsdl"><tptz:ProfileToken>')
      ..write(_xmlEscape(capabilities.profileToken))
      ..write('</tptz:ProfileToken><tptz:Velocity>')
      ..write('<tt:PanTilt xmlns:tt="http://www.onvif.org/ver10/schema" x="${pan.clamp(-1.0, 1.0)}" y="${tilt.clamp(-1.0, 1.0)}"/>')
      ..write('<tt:Zoom xmlns:tt="http://www.onvif.org/ver10/schema" x="${zoom.clamp(-1.0, 1.0)}"/>')
      ..write('</tptz:Velocity></tptz:ContinuousMove>');
    await _soap(uri, 'http://www.onvif.org/ver20/ptz/wsdl/ContinuousMove', body.toString());
  }

  Future<void> stop(OnvifCameraCapabilities capabilities) async {
    final uri = capabilities.ptzXAddr;
    if (uri == null) return;
    await _soap(uri, 'http://www.onvif.org/ver20/ptz/wsdl/Stop', '<tptz:Stop xmlns:tptz="http://www.onvif.org/ver20/ptz/wsdl"><tptz:ProfileToken>${_xmlEscape(capabilities.profileToken)}</tptz:ProfileToken><tptz:PanTilt>true</tptz:PanTilt><tptz:Zoom>true</tptz:Zoom></tptz:Stop>');
  }

  Future<List<OnvifPreset>> getPresets(OnvifCameraCapabilities capabilities) async {
    final uri = capabilities.ptzXAddr;
    if (uri == null) return const [];
    final xml = await _soap(uri, 'http://www.onvif.org/ver20/ptz/wsdl/GetPresets', '<tptz:GetPresets xmlns:tptz="http://www.onvif.org/ver20/ptz/wsdl"><tptz:ProfileToken>${_xmlEscape(capabilities.profileToken)}</tptz:ProfileToken></tptz:GetPresets>', tolerateFault: true);
    final out = <OnvifPreset>[];
    final pattern = RegExp(r'''<(?:\w+:)?Preset\b[^>]*\btoken=["']([^"']+)["'][^>]*>(.*?)</(?:\w+:)?Preset>''', dotAll: true, caseSensitive: false);
    for (final m in pattern.allMatches(xml)) {
      final token = m.group(1) ?? '';
      final block = m.group(2) ?? '';
      final name = _xmlValue(block, 'Name')?.trim();
      if (token.isNotEmpty) out.add(OnvifPreset(token: token, name: name?.isNotEmpty == true ? name! : token));
    }
    return out;
  }

  Future<void> gotoPreset(OnvifCameraCapabilities capabilities, String presetToken) async {
    final uri = capabilities.ptzXAddr;
    if (uri == null) throw UnsupportedError('PTZ is not available');
    await _soap(uri, 'http://www.onvif.org/ver20/ptz/wsdl/GotoPreset', '<tptz:GotoPreset xmlns:tptz="http://www.onvif.org/ver20/ptz/wsdl"><tptz:ProfileToken>${_xmlEscape(capabilities.profileToken)}</tptz:ProfileToken><tptz:PresetToken>${_xmlEscape(presetToken)}</tptz:PresetToken></tptz:GotoPreset>');
  }

  Future<OnvifImagingSettings?> getImagingSettings(OnvifCameraCapabilities capabilities) async {
    final uri = capabilities.imagingXAddr;
    final token = capabilities.videoSourceToken;
    if (uri == null || token == null || token.isEmpty) return null;
    final xml = await getImagingSettingsRaw(uri, token);
    return OnvifImagingSettings(
      brightness: _xmlDouble(xml, 'Brightness'),
      contrast: _xmlDouble(xml, 'Contrast'),
      colorSaturation: _xmlDouble(xml, 'ColorSaturation'),
      sharpness: _xmlDouble(xml, 'Sharpness'),
    );
  }

  Future<String> getImagingSettingsRaw(Uri uri, String sourceToken) => _soap(uri, 'http://www.onvif.org/ver20/imaging/wsdl/GetImagingSettings', '<timg:GetImagingSettings xmlns:timg="http://www.onvif.org/ver20/imaging/wsdl"><timg:VideoSourceToken>${_xmlEscape(sourceToken)}</timg:VideoSourceToken></timg:GetImagingSettings>');

  Future<String> _soap(Uri uri, String action, String body, {bool tolerateFault = false}) async {
    final envelope = _envelope(body);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    client.authenticate = (url, scheme, realm) async {
      client.addCredentials(url, realm ?? '', HttpClientBasicCredentials(username, password));
      return true;
    };
    try {
      final request = await client.postUrl(uri).timeout(const Duration(seconds: 7));
      request.headers.contentType = ContentType('application', 'soap+xml', charset: 'utf-8');
      request.headers.set('SOAPAction', action);
      request.write(envelope);
      final response = await request.close().timeout(const Duration(seconds: 8));
      final xml = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) throw HttpException('ONVIF HTTP ${response.statusCode}', uri: uri);
      if (!tolerateFault && RegExp(r'<(?:\w+:)?Fault\b', caseSensitive: false).hasMatch(xml)) {
        throw HttpException(_xmlValue(xml, 'Text') ?? _xmlValue(xml, 'faultstring') ?? 'ONVIF SOAP fault', uri: uri);
      }
      return xml;
    } finally {
      client.close(force: true);
    }
  }

  String _envelope(String body) {
    final created = DateTime.now().toUtc().toIso8601String();
    final nonceBytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final digest = base64Encode(sha1.convert(<int>[...nonceBytes, ...utf8.encode(created), ...utf8.encode(password)]).bytes);
    final nonce = base64Encode(nonceBytes);
    return '<?xml version="1.0" encoding="UTF-8"?>'
        '<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope" xmlns:wsse="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd" xmlns:wsu="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd">'
        '<s:Header><wsse:Security s:mustUnderstand="1"><wsse:UsernameToken><wsse:Username>${_xmlEscape(username)}</wsse:Username><wsse:Password Type="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-username-token-profile-1.0#PasswordDigest">$digest</wsse:Password><wsse:Nonce EncodingType="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-soap-message-security-1.0#Base64Binary">$nonce</wsse:Nonce><wsu:Created>$created</wsu:Created></wsse:UsernameToken></wsse:Security></s:Header><s:Body>$body</s:Body></s:Envelope>';
  }

  String? _serviceXAddr(String xml, String serviceName) => _firstMatch(xml, RegExp('<(?:\\w+:)?$serviceName\\b[^>]*>.*?<(?:\\w+:)?XAddr>(.*?)</(?:\\w+:)?XAddr>', dotAll: true, caseSensitive: false));
  String? _firstHttpXAddr(String xml) => _firstMatch(xml, RegExp(r'<(?:\w+:)?XAddr>(https?://[^<]+)</(?:\w+:)?XAddr>', caseSensitive: false));
  Uri? _parseOptionalUri(String? value) => value == null || value.trim().isEmpty ? null : Uri.tryParse(_xmlUnescape(value.trim()));
  double? _xmlDouble(String xml, String name) { final value = _xmlValue(xml, name); return value == null ? null : double.tryParse(value.trim()); }
  String? _xmlValue(String xml, String localName) => _firstMatch(xml, RegExp('<(?:\\w+:)?$localName\\b[^>]*>(.*?)</(?:\\w+:)?$localName>', dotAll: true, caseSensitive: false));
  String? _firstMatch(String input, RegExp pattern) => pattern.firstMatch(input)?.group(1);
  String _xmlEscape(String value) => value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll("'", '&apos;');
  String _xmlUnescape(String value) => value.replaceAll('&amp;', '&').replaceAll('&lt;', '<').replaceAll('&gt;', '>').replaceAll('&quot;', '"').replaceAll('&apos;', "'");
}
