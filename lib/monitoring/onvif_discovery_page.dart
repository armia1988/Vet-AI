import 'package:flutter/material.dart';

import 'onvif_discovery_service.dart';

class OnvifDiscoveryPage extends StatefulWidget {
  const OnvifDiscoveryPage({super.key});

  @override
  State<OnvifDiscoveryPage> createState() => _OnvifDiscoveryPageState();
}

class _OnvifDiscoveryPageState extends State<OnvifDiscoveryPage> {
  static const _service = OnvifDiscoveryService();
  bool scanning = false;
  String? error;
  List<OnvifDiscoveredDevice> devices = const [];

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    if (scanning) return;
    setState(() {
      scanning = true;
      error = null;
    });
    try {
      final found = await _service.discover();
      if (!mounted) return;
      setState(() => devices = found);
    } catch (e) {
      if (!mounted) return;
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => scanning = false);
    }
  }

  void _select(OnvifDiscoveredDevice device) {
    final xaddr = device.preferredXAddr;
    Navigator.pop<Map<String, dynamic>>(context, {
      'host': xaddr?.host ?? device.sourceAddress.address,
      'httpPort': xaddr?.hasPort == true
          ? xaddr!.port
          : (xaddr?.scheme == 'https' ? 443 : 80),
      'name': device.displayName,
      'hardware': device.hardware,
      'endpoint': device.endpoint,
      'xaddr': xaddr?.toString(),
      'discoveryMethod': device.discoveryMethod,
      'onvifConfirmed': device.onvifConfirmed,
      'openPorts': device.openPorts,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Find cameras'),
        actions: [
          IconButton(
            onPressed: scanning ? null : _scan,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Scan again',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.radar_rounded, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          scanning
                              ? 'Searching with ONVIF discovery and a direct LAN camera scan…'
                              : 'ONVIF discovery + direct LAN scan',
                          style: const TextStyle(
                            height: 1.35,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Keep the phone on the same Wi‑Fi/LAN as the cameras. The direct scan can still find camera/NVR candidates when multicast discovery is blocked.',
                          style: TextStyle(height: 1.35),
                        ),
                      ],
                    ),
                  ),
                  if (scanning) ...[
                    const SizedBox(width: 12),
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (error != null && devices.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded, size: 48),
              const SizedBox(height: 12),
              const Text(
                'Camera search could not start',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _scan,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }

    if (!scanning && devices.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam_off_outlined, size: 52),
              const SizedBox(height: 12),
              const Text(
                'No reachable camera endpoints found',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Check that Local Network access is allowed for Vet AI, the phone is on the camera LAN, and ONVIF/RTSP is enabled. Cameras behind an isolated NVR PoE network may not be directly reachable from the phone.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _scan,
                icon: const Icon(Icons.radar),
                label: const Text('Scan again'),
              ),
            ],
          ),
        ),
      );
    }

    if (scanning && devices.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 18),
              Text(
                'Scanning ONVIF multicast and local IP addresses…',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: devices.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final device = devices[index];
        final uri = device.preferredXAddr;
        final address = uri?.host ?? device.sourceAddress.address;
        final ports = device.openPorts.isEmpty
            ? null
            : 'Ports ${device.openPorts.join(', ')}';
        final method = device.onvifConfirmed
            ? '${device.discoveryMethod} · ONVIF confirmed'
            : '${device.discoveryMethod} · verify credentials';

        return ListTile(
          leading: CircleAvatar(
            child: Icon(
              device.onvifConfirmed
                  ? Icons.videocam_rounded
                  : Icons.lan_rounded,
            ),
          ),
          title: Text(
            device.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            [
              if (device.hardware != null && device.hardware!.trim().isNotEmpty)
                device.hardware!,
              address,
              method,
              if (ports != null) ports,
            ].join('  •  '),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => _select(device),
        );
      },
    );
  }
}
