import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';

import '../services/vet_backend.dart';
import 'camera_stream_profile_service.dart';
import 'camera_alert_center_page.dart';
import 'camera_gateway_page.dart';
import 'camera_control_page.dart';
import 'camera_intelligence_page.dart';

class CameraCenterPage extends StatefulWidget {
  const CameraCenterPage({super.key, required this.farmId});

  final String farmId;

  @override
  State<CameraCenterPage> createState() => _CameraCenterPageState();
}

class _CameraCenterPageState extends State<CameraCenterPage> with WidgetsBindingObserver {
  static const _secureStorage = FlutterSecureStorage();
  static const _layouts = <int>[1, 4, 6, 8, 12, 16, 32];

  bool loading = true;
  String? loadError;
  int layout = 4;
  int page = 0;
  int? selectedIndex;
  bool audioEnabled = false;
  String qualityMode = 'auto';
  bool wallActive = true;
  bool appActive = true;
  List<_CameraDevice> cameras = const [];

  int get pageCount => cameras.isEmpty ? 1 : ((cameras.length + layout - 1) ~/ layout);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final active = state == AppLifecycleState.resumed;
    if (appActive == active || !mounted) return;
    setState(() => appActive = active);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      loadError = null;
    });
    try {
      final rows = await VetBackend.instance.client
          .from('sensor_devices')
          .select('device_uid,device_type,controller_model,capabilities,active')
          .eq('farm_id', widget.farmId)
          .eq('active', true);
      final result = <_CameraDevice>[];
      for (final row in List<Map<String, dynamic>>.from(rows)) {
        final type = (row['device_type'] ?? '').toString();
        if (type != 'ip_camera' && type != 'thermal_camera') continue;
        final caps = Map<String, dynamic>.from(row['capabilities'] as Map? ?? const {});
        final stream = (caps['stream_uri'] ?? '').toString().trim();
        if (stream.isEmpty) continue;
        final uid = (row['device_uid'] ?? '').toString();
        final configuredKey = (caps['credential_key'] ?? '').toString().trim();
        final key = configuredKey.isEmpty ? 'vetai.camera.$uid.password' : configuredKey;
        final password = await _secureStorage.read(key: key) ?? '';
        result.add(
          _CameraDevice(
            uid: uid,
            name: (caps['camera_name'] ?? row['controller_model'] ?? 'IP Camera').toString(),
            vendor: (caps['vendor'] ?? 'IP Camera').toString(),
            model: (row['controller_model'] ?? '').toString(),
            streamUri: stream,
            username: (caps['username'] ?? '').toString(),
            password: password,
            thermal: type == 'thermal_camera' || caps['thermal'] == true,
            host: (caps['host'] ?? '').toString(),
            httpPort: int.tryParse((caps['http_port'] ?? '80').toString()) ?? 80,
            subStreamUri: (caps['substream_uri'] ?? '').toString().trim(),
            onvif: caps['onvif'] == true,
            capabilities: caps,
          ),
        );
      }
      if (!mounted) return;
      setState(() {
        cameras = result;
        loading = false;
        page = 0;
        selectedIndex = result.isEmpty ? null : 0;
      });
      unawaited(_discoverMissingStreamProfiles());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        loadError = e.toString();
      });
    }
  }

  Future<void> _discoverMissingStreamProfiles() async {
    final snapshot = List<_CameraDevice>.from(cameras);
    for (final camera in snapshot) {
      if (!mounted) return;
      if (!camera.onvif ||
          camera.subStreamUri.isNotEmpty ||
          camera.host.isEmpty ||
          camera.username.isEmpty) {
        continue;
      }
      try {
        final profiles = await CameraStreamProfileService(
          host: camera.host,
          httpPort: camera.httpPort,
          username: camera.username,
          password: camera.password,
        ).discover();
        final sub = profiles.subStreamUri?.trim() ?? '';
        if (sub.isEmpty || sub == profiles.mainStreamUri) continue;

        final updatedCapabilities = <String, dynamic>{
          ...camera.capabilities,
          'stream_uri': profiles.mainStreamUri,
          'substream_uri': sub,
          'stream_profile_count': profiles.profiles.length,
          'adaptive_wall_streams': true,
        };
        try {
          await VetBackend.instance.client
              .from('sensor_devices')
              .update({'capabilities': updatedCapabilities})
              .eq('farm_id', widget.farmId)
              .eq('device_uid', camera.uid);
        } catch (_) {
          // The in-memory substream is still useful when this account cannot
          // persist camera metadata.
        }

        if (!mounted) return;
        final index = cameras.indexWhere((value) => value.uid == camera.uid);
        if (index < 0) continue;
        final updated = List<_CameraDevice>.from(cameras);
        updated[index] = camera.copyWith(
          streamUri: profiles.mainStreamUri,
          subStreamUri: sub,
          capabilities: updatedCapabilities,
        );
        setState(() => cameras = updated);
      } catch (_) {
        // Keep the verified main stream. AUTO mode truthfully falls back to
        // MAIN when a camera does not expose a distinct ONVIF substream.
      }
    }
  }

  List<_CameraDevice> get _visible {
    final start = page * layout;
    if (start >= cameras.length) return const [];
    final end = (start + layout).clamp(0, cameras.length);
    return cameras.sublist(start, end);
  }

  int _columnsFor(int count, double width) {
    if (count <= 1) return 1;
    if (count <= 4) return 2;
    if (count <= 9) return width > 760 ? 3 : 2;
    if (count <= 16) return width > 900 ? 4 : 3;
    return width > 1100 ? 6 : 4;
  }

  bool get _autoUsesSubstream => layout >= 6;

  String _gridStreamFor(_CameraDevice camera) {
    if (qualityMode == 'high') return camera.streamUri;
    if (qualityMode == 'low') {
      return camera.subStreamUri.isNotEmpty ? camera.subStreamUri : camera.streamUri;
    }
    if (_autoUsesSubstream && camera.subStreamUri.isNotEmpty) {
      return camera.subStreamUri;
    }
    return camera.streamUri;
  }

  String _gridQualityLabel(_CameraDevice camera) {
    final chosen = _gridStreamFor(camera);
    if (chosen == camera.subStreamUri && camera.subStreamUri.isNotEmpty) return 'SUB';
    if ((qualityMode == 'low' || _autoUsesSubstream) && camera.subStreamUri.isEmpty) {
      return 'MAIN*';
    }
    return 'MAIN';
  }

  int get _gridCacheMs {
    if (layout >= 32) return 180;
    if (layout >= 12) return 220;
    if (layout >= 6) return 260;
    return 350;
  }

  void _chooseLayout() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 20),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _layouts.map((value) {
              final selected = layout == value;
              return ChoiceChip(
                selected: selected,
                label: Text('$value'),
                avatar: Icon(
                  value == 1 ? Icons.crop_square_rounded : Icons.grid_view_rounded,
                  size: 18,
                ),
                onSelected: (_) {
                  Navigator.pop(context);
                  setState(() {
                    layout = value;
                    page = 0;
                    selectedIndex = cameras.isEmpty ? null : 0;
                  });
                },
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Future<void> _openFullscreen(_CameraDevice camera) async {
    if (mounted) setState(() => wallActive = false);
    try {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => _FullscreenCameraPage(camera: camera),
        ),
      );
    } finally {
      if (mounted) setState(() => wallActive = true);
    }
  }

  Future<void> _cameraIntelligence(_CameraDevice camera) async {
    if (camera.host.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera host is missing. Verify this camera again.')),
      );
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => CameraIntelligencePage(
          farmId: widget.farmId,
          deviceUid: camera.uid,
          cameraName: camera.name,
          host: camera.host,
          httpPort: camera.httpPort,
          username: camera.username,
          password: camera.password,
          vendor: camera.vendor,
        ),
      ),
    );
  }

  Future<void> _cameraControls(_CameraDevice camera) async {
    if (camera.host.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera host is missing. Verify this camera again.')),
      );
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => CameraControlPage(
          cameraName: camera.name,
          host: camera.host,
          httpPort: camera.httpPort,
          username: camera.username,
          password: camera.password,
        ),
      ),
    );
  }

  void _cameraInfo(_CameraDevice camera) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(camera.name, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 14),
              _infoRow('Vendor', camera.vendor),
              _infoRow('Model', camera.model.isEmpty ? '—' : camera.model),
              _infoRow('Address', camera.host.isEmpty ? '—' : camera.host),
              _infoRow('Thermal', camera.thermal ? 'Yes' : 'No'),
              _infoRow('Main stream', camera.streamUri),
              _infoRow('Substream', camera.subStreamUri.isEmpty ? 'Not reported' : camera.subStreamUri),
              _infoRow('Wall quality', _gridQualityLabel(camera)),
              const SizedBox(height: 12),
              const Text(
                'Camera image, PTZ and thermal controls are exposed only when the connected model reports those capabilities. Vet AI does not simulate unsupported controls.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 76, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
            Expanded(child: Text(value)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0D10),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111419),
        foregroundColor: Colors.white,
        title: const Text('Camera Center'),
        actions: [
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => CameraAlertCenterPage(farmId: widget.farmId)),
            ),
            icon: const Icon(Icons.notifications_active_rounded),
            tooltip: 'Camera alerts',
          ),
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => CameraGatewayPage(farmId: widget.farmId)),
            ),
            icon: const Icon(Icons.hub_rounded),
            tooltip: 'Local camera gateway',
          ),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded), tooltip: 'Refresh'),
          IconButton(onPressed: _chooseLayout, icon: const Icon(Icons.grid_view_rounded), tooltip: 'Layout'),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : loadError != null
              ? _errorState()
              : cameras.isEmpty
                  ? _emptyState()
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final items = _visible;
                        final columns = _columnsFor(layout, constraints.maxWidth);
                        return Column(
                          children: [
                            _toolbar(),
                            Expanded(
                              child: GridView.builder(
                                padding: const EdgeInsets.all(6),
                                cacheExtent: 0,
                                addAutomaticKeepAlives: false,
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  crossAxisSpacing: 5,
                                  mainAxisSpacing: 5,
                                  childAspectRatio: 16 / 10.5,
                                ),
                                itemCount: layout,
                                itemBuilder: (context, slot) {
                                  if (slot >= items.length) return _emptyTile(slot);
                                  final globalIndex = page * layout + slot;
                                  final selected = selectedIndex == globalIndex;
                                  final camera = items[slot];
                                  final wallStream = _gridStreamFor(camera);
                                  return _CameraTile(
                                    key: ValueKey('${camera.uid}-$layout-$page-$qualityMode-$wallStream'),
                                    camera: camera,
                                    streamUri: wallStream,
                                    qualityLabel: _gridQualityLabel(camera),
                                    networkCachingMs: _gridCacheMs,
                                    active: wallActive && appActive,
                                    selected: selected,
                                    audioEnabled: selected && audioEnabled && wallActive && appActive,
                                    onTap: () => setState(() => selectedIndex = globalIndex),
                                    onDoubleTap: () => _openFullscreen(camera),
                                    onInfo: () => _cameraInfo(camera),
                                  );
                                },
                              ),
                            ),
                            if (pageCount > 1) _pager(),
                          ],
                        );
                      },
                    ),
    );
  }

  Widget _toolbar() {
    final selected = selectedIndex != null && selectedIndex! < cameras.length ? cameras[selectedIndex!] : null;
    return Material(
      color: const Color(0xFF161A20),
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            const SizedBox(width: 8),
            IconButton(
              onPressed: selected == null ? null : () => setState(() => audioEnabled = !audioEnabled),
              color: Colors.white,
              disabledColor: Colors.white24,
              icon: Icon(audioEnabled ? Icons.volume_up_rounded : Icons.volume_off_rounded),
              tooltip: audioEnabled ? 'Mute' : 'Listen',
            ),
            IconButton(
              onPressed: selected == null ? null : () => _openFullscreen(selected),
              color: Colors.white,
              disabledColor: Colors.white24,
              icon: const Icon(Icons.fullscreen_rounded),
              tooltip: 'Fullscreen',
            ),
            IconButton(
              onPressed: selected == null ? null : () => _cameraControls(selected),
              color: Colors.white,
              disabledColor: Colors.white24,
              icon: const Icon(Icons.control_camera_rounded),
              tooltip: 'Camera controls',
            ),
            IconButton(
              onPressed: selected == null ? null : () => _cameraIntelligence(selected),
              color: Colors.white,
              disabledColor: Colors.white24,
              icon: const Icon(Icons.psychology_alt_rounded),
              tooltip: 'Capabilities / Thermal / AI',
            ),
            PopupMenuButton<String>(
              tooltip: 'Wall stream quality',
              initialValue: qualityMode,
              icon: const Icon(Icons.high_quality_rounded, color: Colors.white),
              onSelected: (value) => setState(() => qualityMode = value),
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'auto', child: Text('Auto — main up to 4, substream from 6+')),
                PopupMenuItem(value: 'high', child: Text('High — main stream')),
                PopupMenuItem(value: 'low', child: Text('Low — substream when available')),
              ],
            ),
            Text(qualityMode.toUpperCase(), style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w800)),
            const Spacer(),
            Text('$layout view', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }

  Widget _pager() => Container(
        color: const Color(0xFF111419),
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: page == 0 ? null : () => setState(() => page--),
              color: Colors.white,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Text('${page + 1} / $pageCount', style: const TextStyle(color: Colors.white70)),
            IconButton(
              onPressed: page + 1 >= pageCount ? null : () => setState(() => page++),
              color: Colors.white,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
      );

  Widget _emptyTile(int slot) => Container(
        decoration: BoxDecoration(
          color: const Color(0xFF12151A),
          border: Border.all(color: Colors.white10),
        ),
        child: Center(
          child: Text('${page * layout + slot + 1}', style: const TextStyle(color: Colors.white24, fontSize: 22)),
        ),
      );

  Widget _emptyState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam_off_outlined, color: Colors.white54, size: 54),
              const SizedBox(height: 14),
              const Text('No verified cameras yet', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text('Add and verify a camera first. Only real saved RTSP streams appear here.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white60)),
              const SizedBox(height: 16),
              FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Refresh')),
            ],
          ),
        ),
      );

  Widget _errorState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 52),
              const SizedBox(height: 12),
              Text(loadError ?? 'Could not load cameras', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 14),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
}

class _CameraDevice {
  const _CameraDevice({
    required this.uid,
    required this.name,
    required this.vendor,
    required this.model,
    required this.streamUri,
    required this.username,
    required this.password,
    required this.thermal,
    required this.host,
    required this.httpPort,
    required this.subStreamUri,
    required this.onvif,
    required this.capabilities,
  });

  final String uid;
  final String name;
  final String vendor;
  final String model;
  final String streamUri;
  final String username;
  final String password;
  final bool thermal;
  final String host;
  final int httpPort;
  final String subStreamUri;
  final bool onvif;
  final Map<String, dynamic> capabilities;

  String authenticated(String rawStreamUri) {
    final parsed = Uri.parse(rawStreamUri);
    if (parsed.scheme.toLowerCase() != 'rtsp' || username.isEmpty) return rawStreamUri;
    return Uri(
      scheme: parsed.scheme,
      userInfo: '${Uri.encodeComponent(username)}:${Uri.encodeComponent(password)}',
      host: parsed.host,
      port: parsed.hasPort ? parsed.port : null,
      path: parsed.path,
      query: parsed.hasQuery ? parsed.query : null,
      fragment: parsed.hasFragment ? parsed.fragment : null,
    ).toString();
  }

  String get authenticatedUri => authenticated(streamUri);

  _CameraDevice copyWith({
    String? streamUri,
    String? subStreamUri,
    Map<String, dynamic>? capabilities,
  }) =>
      _CameraDevice(
        uid: uid,
        name: name,
        vendor: vendor,
        model: model,
        streamUri: streamUri ?? this.streamUri,
        username: username,
        password: password,
        thermal: thermal,
        host: host,
        httpPort: httpPort,
        subStreamUri: subStreamUri ?? this.subStreamUri,
        onvif: onvif,
        capabilities: capabilities ?? this.capabilities,
      );
}

class _CameraTile extends StatefulWidget {
  const _CameraTile({
    super.key,
    required this.camera,
    required this.streamUri,
    required this.qualityLabel,
    required this.networkCachingMs,
    required this.active,
    required this.selected,
    required this.audioEnabled,
    required this.onTap,
    required this.onDoubleTap,
    required this.onInfo,
  });

  final _CameraDevice camera;
  final String streamUri;
  final String qualityLabel;
  final int networkCachingMs;
  final bool active;
  final bool selected;
  final bool audioEnabled;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final VoidCallback onInfo;

  @override
  State<_CameraTile> createState() => _CameraTileState();
}

class _CameraTileState extends State<_CameraTile> {
  late VlcPlayerController controller;
  bool initialized = false;
  bool reconnecting = false;

  @override
  void initState() {
    super.initState();
    controller = _makeController();
    controller.addListener(_playerChanged);
    unawaited(controller.setVolume(widget.audioEnabled ? 100 : 0));
  }

  VlcPlayerController _makeController() => VlcPlayerController.network(
        widget.camera.authenticated(widget.streamUri),
        hwAcc: HwAcc.full,
        autoPlay: widget.active,
        allowBackgroundPlayback: false,
        options: VlcPlayerOptions(
          advanced: VlcAdvancedOptions([VlcAdvancedOptions.networkCaching(widget.networkCachingMs)]),
          rtp: VlcRtpOptions([VlcRtpOptions.rtpOverRtsp(true)]),
        ),
      );

  void _playerChanged() {
    final value = controller.value;
    if (!mounted) return;
    final next = value.isInitialized;
    if (next != initialized) setState(() => initialized = next);
  }

  @override
  void didUpdateWidget(covariant _CameraTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      if (widget.active) {
        unawaited(controller.play());
      } else {
        unawaited(controller.stop());
      }
    }
    if (oldWidget.audioEnabled != widget.audioEnabled || oldWidget.active != widget.active) {
      unawaited(controller.setVolume(widget.active && widget.audioEnabled ? 100 : 0));
    }
  }

  Future<void> _reconnect() async {
    if (reconnecting) return;
    setState(() => reconnecting = true);
    try {
      await controller.stop();
      await controller.play();
    } finally {
      if (mounted) setState(() => reconnecting = false);
    }
  }

  @override
  void dispose() {
    controller.removeListener(_playerChanged);
    unawaited(controller.stop());
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onDoubleTap: widget.onDoubleTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black,
          border: Border.all(color: widget.selected ? Colors.lightBlueAccent : Colors.white12, width: widget.selected ? 2 : 1),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (widget.active)
              VlcPlayer(
                controller: controller,
                aspectRatio: 16 / 9,
                placeholder: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else
              const Center(child: Icon(Icons.pause_circle_outline_rounded, color: Colors.white38, size: 34)),
            Positioned(
              left: 7,
              top: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(5)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: initialized ? Colors.greenAccent : Colors.orangeAccent)),
                    const SizedBox(width: 5),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 160),
                      child: Text(widget.camera.name, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
            ),
            if (widget.camera.thermal)
              const Positioned(right: 7, top: 7, child: Icon(Icons.thermostat_rounded, color: Colors.orangeAccent, size: 20)),
            Positioned(
              right: 7,
              top: widget.camera.thermal ? 31 : 7,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(5)),
                child: Text(widget.qualityLabel, style: const TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.w800)),
              ),
            ),
            Positioned(
              right: 2,
              bottom: 1,
              child: Row(
                children: [
                  IconButton(onPressed: widget.active ? _reconnect : null, icon: reconnecting ? const SizedBox.square(dimension: 17, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh_rounded), color: Colors.white, iconSize: 19),
                  IconButton(onPressed: widget.onInfo, icon: const Icon(Icons.more_vert_rounded), color: Colors.white, iconSize: 19),
                ],
              ),
            ),
            if (widget.audioEnabled)
              const Positioned(left: 8, bottom: 7, child: Icon(Icons.volume_up_rounded, color: Colors.white, size: 19)),
          ],
        ),
      ),
    );
  }
}

class _FullscreenCameraPage extends StatefulWidget {
  const _FullscreenCameraPage({required this.camera});
  final _CameraDevice camera;

  @override
  State<_FullscreenCameraPage> createState() => _FullscreenCameraPageState();
}

class _FullscreenCameraPageState extends State<_FullscreenCameraPage> {
  late final VlcPlayerController controller;
  bool muted = false;

  @override
  void initState() {
    super.initState();
    controller = VlcPlayerController.network(
      widget.camera.authenticatedUri,
      hwAcc: HwAcc.full,
      autoPlay: true,
      allowBackgroundPlayback: false,
      options: VlcPlayerOptions(
        advanced: VlcAdvancedOptions([VlcAdvancedOptions.networkCaching(300)]),
        rtp: VlcRtpOptions([VlcRtpOptions.rtpOverRtsp(true)]),
      ),
    );
  }

  @override
  void dispose() {
    unawaited(controller.stop());
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.camera.name),
        actions: [
          IconButton(
            onPressed: () {
              setState(() => muted = !muted);
              controller.setVolume(muted ? 0 : 100);
            },
            icon: Icon(muted ? Icons.volume_off_rounded : Icons.volume_up_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: VlcPlayer(
              controller: controller,
              aspectRatio: 16 / 9,
              placeholder: const Center(child: CircularProgressIndicator()),
            ),
          ),
        ),
      ),
    );
  }
}
