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
  });

  final String endpoint;
  final List<String> xAddrs;
  final List<String> scopes;
  final List<String> types;
  final InternetAddress sourceAddress;

  Uri? get preferredXAddr {
    for (final value in xAddrs) {
      final uri = Uri.tryParse(value);
      if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) return uri;
    }
    return null;
  }

  String get displayName {
    for (final scope in scopes) {
      const prefix = 'onvif://www.onvif.org/name/';
      if (scope.startsWith(prefix)) {
        return Uri.decodeComponent(scope.substring(prefix.length)).replaceAll('_', ' ');
      }
    }
    return sourceAddress.address;
  }

  String? get hardware {
    for (final scope in scopes) {
      const prefix = 'onvif://www.onvif.org/hardware/';
      if (scope.startsWith(prefix)) {
        return Uri.decodeComponent(scope.substring(prefix.length)).replaceAll('_', ' ');
      }
    }
    return null;
  }
}

class OnvifDiscoveryService {
  const OnvifDiscoveryService();

  static final InternetAddress _multicast = InternetAddress('239.255.255.250');
  static const int _port = 3702;

  Future<List<OnvifDiscoveredDevice>> discover({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0,
        reuseAddress: true, reusePort: false);
    final results = <String, OnvifDiscoveredDevice>{};
    final done = Completer<void>();
    Timer? timer;

    try {
      socket.broadcastEnabled = true;
      socket.multicastHops = 1;
      socket.readEventsEnabled = true;

      final messageId = _uuidUrn();
      final payload = utf8.encode(_probe(messageId));

      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        Datagram? datagram;
        while ((datagram = socket.receive()) != null) {
          final packet = datagram!;
          final text = utf8.decode(packet.data, allowMalformed: true);
          for (final device in _parseProbeMatches(text, packet.address)) {
            final key = device.endpoint.isNotEmpty
                ? device.endpoint
                : '${packet.address.address}|${device.xAddrs.join(',')}';
            results[key] = device;
          }
        }
      }, onError: (_) {
        if (!done.isCompleted) done.complete();
      }, onDone: () {
        if (!done.isCompleted) done.complete();
      });

      for (var i = 0; i < 3; i++) {
        socket.send(payload, _multicast, _port);
        if (i < 2) await Future<void>.delayed(const Duration(milliseconds: 450));
      }

      timer = Timer(timeout, () {
        if (!done.isCompleted) done.complete();
      });
      await done.future;
      return results.values.toList()
        ..sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    } finally {
      timer?.cancel();
      socket.close();
    }
  }

  String _probe(String id) => '''<?xml version="1.0" encoding="UTF-8"?>
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
    <d:Probe>
      <d:Types>dn:NetworkVideoTransmitter</d:Types>
    </d:Probe>
  </e:Body>
</e:Envelope>''';

  List<OnvifDiscoveredDevice> _parseProbeMatches(String xml, InternetAddress source) {
    final blocks = RegExp(r'<(?:\w+:)?ProbeMatch\b[^>]*>([\s\S]*?)</(?:\w+:)?ProbeMatch>', caseSensitive: false)
        .allMatches(xml);
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
      out.add(OnvifDiscoveredDevice(
        endpoint: endpoint,
        xAddrs: xaddrs,
        scopes: scopes,
        types: types,
        sourceAddress: source,
      ));
    }
    return out;
  }

  String? _first(String text, String tag) {
    final m = RegExp('<(?:\\w+:)?$tag\\b[^>]*>([\\s\\S]*?)</(?:\\w+:)?$tag>', caseSensitive: false)
        .firstMatch(text);
    return m?.group(1)?.trim();
  }

  String _uuidUrn() {
    final r = Random.secure();
    String hex(int n) => List.generate(n, (_) => r.nextInt(16).toRadixString(16)).join();
    return 'urn:uuid:${hex(8)}-${hex(4)}-4${hex(3)}-${8 + r.nextInt(4)}${hex(3)}-${hex(12)}';
  }
}
