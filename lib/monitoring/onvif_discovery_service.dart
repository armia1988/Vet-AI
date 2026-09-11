import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

class OnvifDiscoveredDevice {
  const OnvifDiscoveredDevice({
    required this.endpoint,
    required this.xAddrs,
    required this.scopes,
    required this.types,
    required this.sourceAddress,
    this.discoveryMethod = 'WS-Discovery',
    this.onvifConfirmed = true,
    this.openPorts = const <int>[],
  });

  final String endpoint;
  final List<String> xAddrs;
  final List<String> scopes;
  final List<String> types;
  final InternetAddress sourceAddress;
  final String discoveryMethod;
  final bool onvifConfirmed;
  final List<int> openPorts;

  Uri? get preferredXAddr {
    for (final value in xAddrs) {
      final uri = Uri.tryParse(value);
      if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
        return uri;
      }
    }
    return null;
  }

  String get displayName {
    for (final scope in scopes) {
      const prefix = 'onvif://www.onvif.org/name/';
      if (scope.startsWith(prefix)) {
        return Uri.decodeComponent(scope.substring(prefix.length))
            .replaceAll('_', ' ');
      }
    }
    return sourceAddress.address;
  }

  String? get hardware {
    for (final scope in scopes) {
      const prefix = 'onvif://www.onvif.org/hardware/';
      if (scope.startsWith(prefix)) {
        return Uri.decodeComponent(scope.substring(prefix.length))
            .replaceAll('_', ' ');
      }
    }
    return null;
  }
}

class OnvifDiscoveryService {
  const OnvifDiscoveryService();

  static final InternetAddress _multicast = InternetAddress('239.255.255.250');
  static const int _port = 3702;
  static const List<int> _candidatePorts = <int>[80, 443, 554, 8000, 8080, 8899];
  static const List<int> _webPorts = <int>[80, 443, 8080, 8899];

  Future<List<OnvifDiscoveredDevice>> discover({
    Duration timeout = const Duration(seconds: 4),
    bool includeLanFallback = true,
  }) async {
    final merged = <String, OnvifDiscoveredDevice>{};

    // WS-Discovery is still the preferred path because it returns real ONVIF
    // metadata. On iOS multicast may be unavailable on some networks/builds,
    // so failure here must not abort the full search.
    try {
      final ws = await _wsDiscover(timeout: timeout);
      for (final device in ws) {
        merged[_deviceKey(device)] = device;
      }
    } catch (_) {
      // The direct LAN fallback below can still find reachable cameras.
    }

    if (includeLanFallback) {
      try {
        final lan = await _scanLocalSubnets();
        for (final device in lan) {
          final existingKey = merged.keys.cast<String?>().firstWhere(
                (key) =>
                    key != null &&
                    merged[key]?.sourceAddress.address == device.sourceAddress.address,
                orElse: () => null,
              );
          if (existingKey == null) {
            merged[_deviceKey(device)] = device;
          }
        }
      } catch (_) {
        // Discovery remains best-effort; manual camera entry always exists.
      }
    }

    return merged.values.toList()
      ..sort((a, b) {
        if (a.onvifConfirmed != b.onvifConfirmed) {
          return a.onvifConfirmed ? -1 : 1;
        }
        return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
      });
  }

  String _deviceKey(OnvifDiscoveredDevice device) {
    if (device.endpoint.isNotEmpty) return device.endpoint;
    return '${device.sourceAddress.address}|${device.xAddrs.join(',')}';
  }

  Future<List<OnvifDiscoveredDevice>> _wsDiscover({
    required Duration timeout,
  }) async {
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      0,
      reuseAddress: true,
      reusePort: false,
    );
    final results = <String, OnvifDiscoveredDevice>{};
    final done = Completer<void>();
    Timer? timer;
    StreamSubscription<RawSocketEvent>? subscription;

    try {
      socket.broadcastEnabled = true;
      socket.multicastHops = 2;
      socket.readEventsEnabled = true;

      subscription = socket.listen(
        (event) {
          if (event != RawSocketEvent.read) return;
          Datagram? datagram;
          while ((datagram = socket.receive()) != null) {
            final packet = datagram!;
            final text = utf8.decode(packet.data, allowMalformed: true);
            for (final device in _parseProbeMatches(text, packet.address)) {
              results[_deviceKey(device)] = device;
            }
          }
        },
        onError: (_) {
          if (!done.isCompleted) done.complete();
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
      );

      // Some cameras answer only a typed NVT probe while others answer only a
      // generic probe. Send both variants on every pass.
      for (var i = 0; i < 3; i++) {
        final typed = utf8.encode(_probe(_uuidUrn(), typed: true));
        final generic = utf8.encode(_probe(_uuidUrn(), typed: false));
        socket.send(typed, _multicast, _port);
        socket.send(generic, _multicast, _port);
        if (i < 2) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      }

      timer = Timer(timeout, () {
        if (!done.isCompleted) done.complete();
      });
      await done.future;
      return results.values.toList();
    } finally {
      timer?.cancel();
      await subscription?.cancel();
      socket.close();
    }
  }

  Future<List<OnvifDiscoveredDevice>> _scanLocalSubnets() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );

    final ownAddresses = <String>{};
    final prefixes = <String>{};
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        final value = address.address;
        if (!_isPrivateIpv4(value)) continue;
        ownAddresses.add(value);
        final parts = value.split('.');
        if (parts.length == 4) {
          prefixes.add('${parts[0]}.${parts[1]}.${parts[2]}');
        }
      }
    }

    if (prefixes.isEmpty) return const <OnvifDiscoveredDevice>[];

    // A phone normally has one active Wi-Fi private /24. Cap at two networks
    // to avoid scanning VPN/virtual interfaces indefinitely.
    final targets = <String>[];
    for (final prefix in prefixes.take(2)) {
      for (var host = 1; host <= 254; host++) {
        final ip = '$prefix.$host';
        if (!ownAddresses.contains(ip)) targets.add(ip);
      }
    }

    final found = <OnvifDiscoveredDevice>[];
    var next = 0;
    const workers = 48;

    Future<void> worker() async {
      while (true) {
        final index = next++;
        if (index >= targets.length) return;
        final device = await _scanHost(targets[index]);
        if (device != null) found.add(device);
      }
    }

    await Future.wait(List.generate(workers, (_) => worker()));
    return found;
  }

  Future<OnvifDiscoveredDevice?> _scanHost(String ip) async {
    final checks = await Future.wait(
      _candidatePorts.map((port) async => MapEntry(port, await _canConnect(ip, port))),
    );
    final open = checks.where((entry) => entry.value).map((entry) => entry.key).toList();
    if (open.isEmpty) return null;

    int? onvifPort;
    bool onvifConfirmed = false;
    for (final port in _webPorts) {
      if (!open.contains(port)) continue;
      if (await _probeOnvifDeviceService(ip, port)) {
        onvifPort = port;
        onvifConfirmed = true;
        break;
      }
    }

    // If ONVIF does not answer anonymously, keep strong camera/NVR
    // candidates such as RTSP/SDK/ONVIF-port hosts. The onboarding screen will
    // still require a real authenticated connection test before saving.
    final hasCameraSignature =
        open.contains(554) || open.contains(8000) || open.contains(8899);
    if (!onvifConfirmed && !hasCameraSignature) return null;

    onvifPort ??= open.contains(80)
        ? 80
        : open.contains(443)
            ? 443
            : open.contains(8080)
                ? 8080
                : open.contains(8899)
                    ? 8899
                    : 80;

    final secure = onvifPort == 443;
    final scheme = secure ? 'https' : 'http';
    final xaddr = '$scheme://$ip:$onvifPort/onvif/device_service';
    final name = onvifConfirmed ? 'ONVIF Camera $ip' : 'Camera candidate $ip';

    return OnvifDiscoveredDevice(
      endpoint: 'lan-scan:$ip:$onvifPort',
      xAddrs: <String>[xaddr],
      scopes: <String>[
        'onvif://www.onvif.org/name/${Uri.encodeComponent(name).replaceAll('%20', '_')}',
      ],
      types: <String>[
        if (onvifConfirmed) 'dn:NetworkVideoTransmitter',
        if (open.contains(554)) 'rtsp:554',
        'lan:ports:${open.join(',')}',
      ],
      sourceAddress: InternetAddress(ip),
      discoveryMethod: onvifConfirmed ? 'LAN ONVIF probe' : 'LAN camera scan',
      onvifConfirmed: onvifConfirmed,
      openPorts: open,
    );
  }

  Future<bool> _canConnect(String host, int port) async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(milliseconds: 260),
      );
      return true;
    } catch (_) {
      return false;
    } finally {
      socket?.destroy();
    }
  }

  Future<bool> _probeOnvifDeviceService(String host, int port) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(milliseconds: 650)
      ..badCertificateCallback = (_, __, ___) => true;
    try {
      final scheme = port == 443 ? 'https' : 'http';
      final uri = Uri.parse('$scheme://$host:$port/onvif/device_service');
      final request = await client.postUrl(uri).timeout(const Duration(milliseconds: 700));
      request.headers.contentType = ContentType('application', 'soap+xml', charset: 'utf-8');
      request.write(_getSystemDateAndTimeEnvelope());
      final response = await request.close().timeout(const Duration(milliseconds: 700));
      final body = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(milliseconds: 700), onTimeout: () => '');
      final lower = body.toLowerCase();
      if (lower.contains('getsystemdateandtimeresponse') ||
          lower.contains('onvif.org/ver10') ||
          lower.contains('soap-env') ||
          lower.contains('soap:envelope')) {
        return true;
      }
      return response.statusCode == HttpStatus.unauthorized ||
          response.statusCode == HttpStatus.forbidden ||
          response.statusCode == HttpStatus.methodNotAllowed;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  bool _isPrivateIpv4(String value) {
    final parts = value.split('.');
    if (parts.length != 4) return false;
    final nums = parts.map(int.tryParse).toList();
    if (nums.any((n) => n == null)) return false;
    final a = nums[0]!;
    final b = nums[1]!;
    if (a == 10) return true;
    if (a == 192 && b == 168) return true;
    return a == 172 && b >= 16 && b <= 31;
  }

  String _probe(String id, {required bool typed}) => '''<?xml version="1.0" encoding="UTF-8"?>
<e:Envelope xmlns:e="http://www.w3.org/2003/05/soap-envelope"
 xmlns:w="http://schemas.xmlsoap.org/ws/2004/08/addressing"
 xmlns:d="http://schemas.xmlsoap.org/ws/2005/04/discovery"
 xmlns:dn="http://www.onvif.org/ver10/network/wsdl">
  <e:Header>
    <w:MessageID>$id</w:MessageID>
    <w:To e:mustUnderstand="true">urn:schemas-xmlsoap-org:ws:2005:04:discovery</w:To>
    <w:Action e:mustUnderstand="true">http://schemas.xmlsoap.org/ws/2005/04/discovery/Probe</w:Action>
  </e:Header>
  <e:Body>
    <d:Probe>${typed ? '<d:Types>dn:NetworkVideoTransmitter</d:Types>' : ''}</d:Probe>
  </e:Body>
</e:Envelope>''';

  String _getSystemDateAndTimeEnvelope() => '''<?xml version="1.0" encoding="UTF-8"?>
<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope">
  <s:Body>
    <GetSystemDateAndTime xmlns="http://www.onvif.org/ver10/device/wsdl"/>
  </s:Body>
</s:Envelope>''';

  List<OnvifDiscoveredDevice> _parseProbeMatches(
    String xml,
    InternetAddress source,
  ) {
    final blocks = RegExp(
      r'<(?:\w+:)?ProbeMatch\b[^>]*>([\s\S]*?)</(?:\w+:)?ProbeMatch>',
      caseSensitive: false,
    ).allMatches(xml);
    final out = <OnvifDiscoveredDevice>[];
    for (final block in blocks) {
      final body = block.group(1) ?? '';
      final endpoint = _first(body, 'Address') ?? '';
      final xaddrs = (_first(body, 'XAddrs') ?? '')
          .split(RegExp(r'\s+'))
          .where((e) => e.trim().isNotEmpty)
          .toList();
      final scopes = (_first(body, 'Scopes') ?? '')
          .split(RegExp(r'\s+'))
          .where((e) => e.trim().isNotEmpty)
          .toList();
      final types = (_first(body, 'Types') ?? '')
          .split(RegExp(r'\s+'))
          .where((e) => e.trim().isNotEmpty)
          .toList();
      if (xaddrs.isEmpty && endpoint.isEmpty) continue;
      out.add(
        OnvifDiscoveredDevice(
          endpoint: endpoint,
          xAddrs: xaddrs,
          scopes: scopes,
          types: types,
          sourceAddress: source,
          discoveryMethod: 'WS-Discovery',
          onvifConfirmed: true,
        ),
      );
    }
    return out;
  }

  String? _first(String text, String tag) {
    final match = RegExp(
      '<(?:\\w+:)?$tag\\b[^>]*>([\\s\\S]*?)</(?:\\w+:)?$tag>',
      caseSensitive: false,
    ).firstMatch(text);
    return match?.group(1)?.trim();
  }

  String _uuidUrn() {
    final random = Random.secure();
    String hex(int count) => List.generate(
          count,
          (_) => random.nextInt(16).toRadixString(16),
        ).join();
    return 'urn:uuid:${hex(8)}-${hex(4)}-4${hex(3)}-${8 + random.nextInt(4)}${hex(3)}-${hex(12)}';
  }
}
