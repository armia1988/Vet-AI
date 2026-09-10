import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/vet_backend.dart';

class CameraGatewayPage extends StatefulWidget {
  const CameraGatewayPage({super.key, required this.farmId});

  final String farmId;

  @override
  State<CameraGatewayPage> createState() => _CameraGatewayPageState();
}

class _CameraGatewayPageState extends State<CameraGatewayPage> {
  static const _supabaseUrl = 'https://mzqwjyantyvizwbzetwf.supabase.co';

  bool loading = true;
  String? error;
  List<Map<String, dynamic>> gateways = const [];
  Map<String, Map<String, dynamic>> statusByDeviceId = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final client = VetBackend.instance.client;
      final deviceRows = await client
          .from('sensor_devices')
          .select('id,device_uid,display_name,controller_model,active,last_seen_at,created_at,capabilities')
          .eq('farm_id', widget.farmId)
          .eq('device_type', 'camera_gateway')
          .order('created_at', ascending: false);
      final statusRows = await client
          .from('camera_gateway_status')
          .select()
          .eq('farm_id', widget.farmId)
          .order('last_heartbeat_at', ascending: false);
      final devices = List<Map<String, dynamic>>.from(
        deviceRows.map((e) => Map<String, dynamic>.from(e)),
      );
      final byId = <String, Map<String, dynamic>>{};
      for (final raw in statusRows) {
        final row = Map<String, dynamic>.from(raw);
        byId[(row['gateway_device_id'] ?? '').toString()] = row;
      }
      if (!mounted) return;
      setState(() {
        gateways = devices;
        statusByDeviceId = byId;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  String _randomToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  String _randomSuffix() {
    final random = Random.secure();
    return List<String>.generate(
      5,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Future<void> _createGateway() async {
    final nameController = TextEditingController(text: 'Farm Camera Gateway');
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add local camera gateway'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Gateway name',
            helperText: 'Example: Barn office gateway',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = nameController.text.trim();
              if (value.isNotEmpty) Navigator.pop(context, value);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
    nameController.dispose();
    if (name == null || !mounted) return;

    final token = _randomToken();
    final tokenHash = sha256.convert(utf8.encode(token)).toString();
    final uid = 'camera-gateway-${DateTime.now().millisecondsSinceEpoch}-${_randomSuffix()}';

    try {
      await VetBackend.instance.client.from('sensor_devices').insert({
        'farm_id': widget.farmId,
        'device_uid': uid,
        'device_type': 'camera_gateway',
        'controller_model': 'Vet AI Local Camera Gateway',
        'display_name': name,
        'sensor_models': <String>[],
        'device_secret_hash': tokenHash,
        'active': true,
        'capabilities': {
          'gateway': true,
          'protocol': 'vet_ai_camera_gateway_v1',
          'onvif_pullpoint': true,
          'thermal_forwarding': true,
          'local_agent_required': true,
        },
      });
      if (!mounted) return;
      await _showProvisioning(uid: uid, token: token, name: name);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create gateway: $e')),
        );
      }
    }
  }

  Future<void> _showProvisioning({
    required String uid,
    required String token,
    required String name,
  }) async {
    final identityConfig = const JsonEncoder.withIndent('  ').convert({
      'supabase_url': _supabaseUrl,
      'gateway_device_uid': uid,
      'gateway_device_token': token,
    });
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            18,
            4,
            18,
            18 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Save this token now. Vet AI stores only its SHA-256 hash, so the original token cannot be shown again.',
                ),
                const SizedBox(height: 14),
                _copyField(context, 'Gateway UID', uid),
                const SizedBox(height: 10),
                _copyField(context, 'One-time gateway token', token),
                const SizedBox(height: 10),
                _copyField(context, 'Agent identity JSON', identityConfig),
                const SizedBox(height: 16),
                const Text(
                  'Run tools/vet_ai_camera_gateway.py on an always-on Raspberry Pi, mini PC, server or NVR-side computer inside the same LAN as the cameras. Add each saved Vet AI camera UID, local IP and camera credentials to camera_gateway_config.json.',
                ),
                const SizedBox(height: 8),
                const Text(
                  'After the agent starts, the phone can be closed. The gateway renews ONVIF subscriptions, reconnects failed camera links and forwards supported thermal readings to Vet AI.',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _copyField(BuildContext context, String label, String value) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 5),
                  SelectableText(value),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Copy',
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: value));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$label copied')),
                );
              },
              icon: const Icon(Icons.copy_rounded),
            ),
          ],
        ),
      );

  Future<void> _setActive(Map<String, dynamic> gateway, bool active) async {
    final id = (gateway['id'] ?? '').toString();
    if (id.isEmpty) return;
    try {
      await VetBackend.instance.client
          .from('sensor_devices')
          .update({'active': active})
          .eq('id', id)
          .eq('farm_id', widget.farmId);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not ${active ? 'enable' : 'disable'} gateway: $e'),
          ),
        );
      }
    }
  }

  bool _online(Map<String, dynamic>? status, bool active) {
    if (!active || status == null) return false;
    final parsed = DateTime.tryParse(
      (status['last_heartbeat_at'] ?? '').toString(),
    );
    if (parsed == null) return false;
    return DateTime.now().toUtc().difference(parsed.toUtc()) <
        const Duration(seconds: 90);
  }

  String _time(dynamic raw) {
    final value = DateTime.tryParse((raw ?? '').toString());
    if (value == null) return 'Never';
    final local = value.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }

  Map<String, dynamic> _map(dynamic raw) => raw is Map
      ? Map<String, dynamic>.from(raw)
      : <String, dynamic>{};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0D10),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111419),
        foregroundColor: Colors.white,
        title: const Text('Local Camera Gateway'),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createGateway,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add gateway'),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? _errorState()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 100),
                    children: [
                      _explanation(),
                      const SizedBox(height: 14),
                      if (gateways.isEmpty)
                        _emptyState()
                      else
                        ...gateways.map(_gatewayCard),
                    ],
                  ),
                ),
    );
  }

  Widget _explanation() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF15191F),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white10),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.hub_rounded, color: Colors.lightBlueAccent),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                '24/7 camera monitoring needs an always-on device inside the camera LAN. The V94 gateway renews PullPoint subscriptions before expiry, reconnects after network loss and reports separate event/thermal health for every camera.',
                style: TextStyle(color: Colors.white70, height: 1.35),
              ),
            ),
          ],
        ),
      );

  Widget _gatewayCard(Map<String, dynamic> gateway) {
    final id = (gateway['id'] ?? '').toString();
    final status = statusByDeviceId[id];
    final active = gateway['active'] == true;
    final online = _online(status, active);
    final name = (gateway['display_name'] ??
            gateway['controller_model'] ??
            'Camera Gateway')
        .toString();
    final uid = (gateway['device_uid'] ?? '').toString();
    final camerasOnline = status?['cameras_online'] ?? 0;
    final camerasConfigured = status?['cameras_configured'] ?? 0;
    final events = status?['events_forwarded'] ?? 0;
    final thermal = status?['thermal_samples'] ?? 0;
    final lastError = (status?['last_error'] ?? '').toString().trim();
    final runtime = _map(status?['runtime']);

    return Card(
      color: const Color(0xFF15191F),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  online
                      ? Icons.check_circle_rounded
                      : Icons.cloud_off_rounded,
                  color: online ? Colors.greenAccent : Colors.orangeAccent,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        online
                            ? 'ONLINE — 24/7 agent heartbeat received'
                            : active
                                ? 'OFFLINE — no heartbeat in the last 90 seconds'
                                : 'DISABLED',
                        style: TextStyle(
                          color: online
                              ? Colors.greenAccent
                              : Colors.orangeAccent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: active,
                  onChanged: (value) => _setActive(gateway, value),
                ),
              ],
            ),
            const Divider(color: Colors.white12, height: 24),
            _row('Gateway UID', uid),
            _row(
              'Last heartbeat',
              _time(status?['last_heartbeat_at'] ?? gateway['last_seen_at']),
            ),
            _row('Agent version', (status?['agent_version'] ?? '—').toString()),
            _row('Host', (status?['hostname'] ?? '—').toString()),
            _row('Cameras online', '$camerasOnline / $camerasConfigured'),
            _row('Events forwarded', '$events'),
            _row('Thermal samples', '$thermal'),
            _row('Last camera event', _time(status?['last_event_at'])),
            if (runtime.isNotEmpty) ...[
              const Divider(color: Colors.white12, height: 26),
              const Text(
                'Per-camera health',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              ...runtime.entries.map(
                (entry) => _cameraHealthCard(entry.key, _map(entry.value)),
              ),
            ],
            if (lastError.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  lastError,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _cameraHealthCard(String cameraUid, Map<String, dynamic> data) {
    final online = data['online'] == true;
    final eventsEnabled = data['events_enabled'] == true;
    final eventsOk = data['events_ok'] == true;
    final thermalEnabled = data['thermal_enabled'] == true;
    final thermalOk = data['thermal_ok'] == true;
    final lastError = (data['last_error'] ?? '').toString().trim();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 7),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF20252C),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(
              online ? Icons.videocam_rounded : Icons.videocam_off_rounded,
              color: online ? Colors.greenAccent : Colors.orangeAccent,
              size: 19,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: SelectableText(
                cameraUid,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ]),
          const SizedBox(height: 7),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              if (eventsEnabled) _healthChip('Events', eventsOk),
              if (thermalEnabled) _healthChip('Thermal', thermalOk),
              _countChip('Renewals', data['subscription_renewals']),
              _countChip('Reconnects', data['reconnects']),
              _countChip('Deduped', data['deduped_events']),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Last success: ${_time(data['last_success_at'])}',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          if (lastError.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                lastError,
                style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _healthChip(String label, bool ok) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: (ok ? Colors.greenAccent : Colors.orangeAccent)
              .withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
              size: 14,
              color: ok ? Colors.greenAccent : Colors.orangeAccent,
            ),
            const SizedBox(width: 4),
            Text(
              '$label ${ok ? 'OK' : 'DOWN'}',
              style: TextStyle(
                color: ok ? Colors.greenAccent : Colors.orangeAccent,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );

  Widget _countChip(String label, dynamic raw) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          '$label ${raw ?? 0}',
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      );

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 130,
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white54,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(
              child: SelectableText(
                value,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      );

  Widget _emptyState() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 54, horizontal: 24),
        child: Column(
          children: [
            Icon(Icons.hub_outlined, size: 58, color: Colors.white38),
            SizedBox(height: 14),
            Text(
              'No local gateway yet',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Create one, install the agent on an always-on device in the farm LAN, then add your saved camera UIDs to its configuration.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white60),
            ),
          ],
        ),
      );

  Widget _errorState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: Colors.redAccent,
                size: 52,
              ),
              const SizedBox(height: 12),
              Text(
                error ?? 'Could not load gateway status',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 14),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
}
