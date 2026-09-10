from pathlib import Path

# V95: adaptive professional camera wall performance.
# - discovers real ONVIF main/sub streams and persists them
# - AUTO/HIGH/LOW wall quality selection
# - prefers substreams for 6/8/12/16/32 layouts
# - keeps fullscreen on the main stream
# - pauses the wall while fullscreen/backgrounded
# - disables GridView keep-alives/cache so off-screen VLC decoders are released
# - only the selected camera can output audio

onboarding_path = Path('lib/monitoring/dahua_thermal_camera_onboarding_page.dart')
onboarding = onboarding_path.read_text(encoding='utf-8')

profile_import = "import 'camera_stream_profile_service.dart';\n"
connection_import = "import 'camera_connection_service.dart';\n"
if profile_import not in onboarding:
    assert connection_import in onboarding, 'V95 onboarding camera connection import missing'
    onboarding = onboarding.replace(connection_import, connection_import + profile_import, 1)

if 'String? discoveredSubStreamUri;' not in onboarding:
    anchor = '  String? discoveredStreamUri;\n'
    assert anchor in onboarding, 'V95 onboarding stream state anchor missing'
    onboarding = onboarding.replace(
        anchor,
        anchor + '  String? discoveredSubStreamUri;\n  int discoveredProfileCount = 0;\n',
        1,
    )

# Every connection invalidation must also invalidate discovered profile metadata.
onboarding = onboarding.replace(
    '      discoveredStreamUri = null;\n      testDetails = null;',
    '      discoveredStreamUri = null;\n      discoveredSubStreamUri = null;\n      discoveredProfileCount = 0;\n      testDetails = null;',
)

if 'CameraStreamProfiles? discoveredProfiles;' not in onboarding:
    anchor = "      final info = result.deviceInformation ?? const <String, String>{};\n"
    assert anchor in onboarding, 'V95 onboarding connection result anchor missing'
    discovery = """      CameraStreamProfiles? discoveredProfiles;
      if (result.success && protocol.contains('ONVIF')) {
        try {
          discoveredProfiles = await CameraStreamProfileService(
            host: endpoint.host,
            httpPort: endpoint.httpPort,
            username: username.text.trim(),
            password: password.text,
          ).discover();
        } catch (_) {
          // A verified camera remains usable even when it exposes only one
          // stream or refuses optional profile enumeration.
        }
      }

"""
    onboarding = onboarding.replace(anchor, discovery + anchor, 1)

old_assign = """        testedSuccessfully = result.success;
        discoveredStreamUri = result.streamUri;
        testDetails = result.message;
"""
new_assign = """        testedSuccessfully = result.success;
        discoveredStreamUri = discoveredProfiles?.mainStreamUri ?? result.streamUri;
        discoveredSubStreamUri = discoveredProfiles?.subStreamUri;
        discoveredProfileCount = discoveredProfiles?.profiles.length ?? 0;
        testDetails = result.message;
"""
if old_assign in onboarding:
    onboarding = onboarding.replace(old_assign, new_assign, 1)
assert 'discoveredProfiles?.mainStreamUri ?? result.streamUri' in onboarding, 'V95 onboarding profile assignment missing'

old_save = """            'stream_uri': discoveredStreamUri,
            'credentials_storage': 'platform_secure_storage',
"""
new_save = """            'stream_uri': discoveredStreamUri,
            'substream_uri': discoveredSubStreamUri,
            'stream_profile_count': discoveredProfileCount,
            'adaptive_wall_streams': discoveredSubStreamUri != null,
            'credentials_storage': 'platform_secure_storage',
"""
if old_save in onboarding:
    onboarding = onboarding.replace(old_save, new_save, 1)
assert "'substream_uri': discoveredSubStreamUri" in onboarding, 'V95 onboarding substream persistence missing'

onboarding_path.write_text(onboarding, encoding='utf-8')

camera_path = Path('lib/monitoring/camera_center_page.dart')
s = camera_path.read_text(encoding='utf-8')

imp = "import 'camera_stream_profile_service.dart';\n"
if imp not in s:
    anchor = "import '../services/vet_backend.dart';\n"
    assert anchor in s, 'V95 Camera Center backend import missing'
    s = s.replace(anchor, anchor + imp, 1)

s = s.replace(
    'class _CameraCenterPageState extends State<CameraCenterPage> {',
    'class _CameraCenterPageState extends State<CameraCenterPage> with WidgetsBindingObserver {',
    1,
)
assert 'with WidgetsBindingObserver' in s, 'V95 lifecycle observer mixin missing'

if "String qualityMode = 'auto';" not in s:
    anchor = '  bool audioEnabled = false;\n'
    assert anchor in s, 'V95 Camera Center audio state anchor missing'
    s = s.replace(
        anchor,
        anchor + "  String qualityMode = 'auto';\n  bool wallActive = true;\n  bool appActive = true;\n",
        1,
    )

old_init = """  @override
  void initState() {
    super.initState();
    _load();
  }
"""
new_init = """  @override
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
"""
if old_init in s:
    s = s.replace(old_init, new_init, 1)
assert 'WidgetsBinding.instance.addObserver(this);' in s, 'V95 lifecycle registration missing'

# Add real substream metadata to each saved camera after the V85 httpPort patch.
old_camera_load = """            thermal: type == 'thermal_camera' || caps['thermal'] == true,
            host: (caps['host'] ?? '').toString(),
            httpPort: int.tryParse((caps['http_port'] ?? '80').toString()) ?? 80,
"""
new_camera_load = """            thermal: type == 'thermal_camera' || caps['thermal'] == true,
            host: (caps['host'] ?? '').toString(),
            httpPort: int.tryParse((caps['http_port'] ?? '80').toString()) ?? 80,
            subStreamUri: (caps['substream_uri'] ?? '').toString().trim(),
            onvif: caps['onvif'] == true,
            capabilities: caps,
"""
if old_camera_load in s:
    s = s.replace(old_camera_load, new_camera_load, 1)
assert 'subStreamUri:' in s and 'capabilities: caps' in s, 'V95 camera load metadata missing'

# Upgrade cameras saved before V95 in the background. Passwords remain local;
# only RTSP profile URIs are persisted to Supabase.
load_end = """      setState(() {
        cameras = result;
        loading = false;
        page = 0;
        selectedIndex = result.isEmpty ? null : 0;
      });
"""
if 'unawaited(_discoverMissingStreamProfiles());' not in s:
    assert load_end in s, 'V95 Camera Center load completion anchor missing'
    s = s.replace(load_end, load_end + '      unawaited(_discoverMissingStreamProfiles());\n', 1)

if 'Future<void> _discoverMissingStreamProfiles() async {' not in s:
    anchor = '  List<_CameraDevice> get _visible {\n'
    assert anchor in s, 'V95 visible cameras anchor missing'
    method = """  Future<void> _discoverMissingStreamProfiles() async {
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

"""
    s = s.replace(anchor, method + anchor, 1)

if 'String _gridStreamFor(_CameraDevice camera)' not in s:
    anchor = '  void _chooseLayout() {\n'
    assert anchor in s, 'V95 choose layout anchor missing'
    helpers = """  bool get _autoUsesSubstream => layout >= 6;

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

"""
    s = s.replace(anchor, helpers + anchor, 1)

# Pause all wall streams while fullscreen is open. The fullscreen page always
# uses the verified main stream for maximum detail.
old_fullscreen = """  Future<void> _openFullscreen(_CameraDevice camera) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => _FullscreenCameraPage(camera: camera),
      ),
    );
  }
"""
new_fullscreen = """  Future<void> _openFullscreen(_CameraDevice camera) async {
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
"""
if old_fullscreen in s:
    s = s.replace(old_fullscreen, new_fullscreen, 1)
assert 'setState(() => wallActive = false)' in s, 'V95 fullscreen wall pause missing'

# Show stream selection truthfully in camera info.
old_info = """              _infoRow('Thermal', camera.thermal ? 'Yes' : 'No'),
              _infoRow('Stream', camera.streamUri),
"""
new_info = """              _infoRow('Thermal', camera.thermal ? 'Yes' : 'No'),
              _infoRow('Main stream', camera.streamUri),
              _infoRow('Substream', camera.subStreamUri.isEmpty ? 'Not reported' : camera.subStreamUri),
              _infoRow('Wall quality', _gridQualityLabel(camera)),
"""
if old_info in s:
    s = s.replace(old_info, new_info, 1)
assert "_infoRow('Substream'" in s, 'V95 camera info substream row missing'

# Release off-screen grid children instead of keeping many VLC decoders alive.
old_grid = """                              child: GridView.builder(
                                padding: const EdgeInsets.all(6),
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
"""
new_grid = """                              child: GridView.builder(
                                padding: const EdgeInsets.all(6),
                                cacheExtent: 0,
                                addAutomaticKeepAlives: false,
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
"""
if old_grid in s:
    s = s.replace(old_grid, new_grid, 1)
assert 'addAutomaticKeepAlives: false' in s, 'V95 GridView decoder release settings missing'

old_tile = """                                  return _CameraTile(
                                    key: ValueKey('${items[slot].uid}-$layout-$page'),
                                    camera: items[slot],
                                    selected: selected,
                                    audioEnabled: selected && audioEnabled,
                                    onTap: () => setState(() => selectedIndex = globalIndex),
                                    onDoubleTap: () => _openFullscreen(items[slot]),
                                    onInfo: () => _cameraInfo(items[slot]),
                                  );
"""
new_tile = """                                  final camera = items[slot];
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
"""
if old_tile in s:
    s = s.replace(old_tile, new_tile, 1)
assert 'qualityLabel: _gridQualityLabel(camera)' in s, 'V95 adaptive tile wiring missing'

# Add AUTO / HIGH / LOW quality control without disturbing V87 controls.
quality_control = """            PopupMenuButton<String>(
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
"""
if "tooltip: 'Wall stream quality'" not in s:
    anchor = '            const Spacer(),\n            Text(\'$layout view\''
    if anchor not in s:
        # Keep matching independent of quoting/formatting from older patches.
        anchor = '            const Spacer(),\n            Text(\'$layout view\', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),\n'
        assert anchor in s, 'V95 toolbar spacer anchor missing'
        s = s.replace(anchor, quality_control + anchor, 1)
    else:
        s = s.replace('            const Spacer(),\n', quality_control + '            const Spacer(),\n', 1)
assert "tooltip: 'Wall stream quality'" in s, 'V95 quality selector missing'

# Extend the camera model with persisted ONVIF profile metadata and a safe URI
# authenticator reusable for main and sub streams.
old_ctor_tail = """    required this.host,
    required this.httpPort,
  });
"""
new_ctor_tail = """    required this.host,
    required this.httpPort,
    required this.subStreamUri,
    required this.onvif,
    required this.capabilities,
  });
"""
if old_ctor_tail in s:
    s = s.replace(old_ctor_tail, new_ctor_tail, 1)
assert 'required this.subStreamUri' in s, 'V95 camera model constructor missing'

old_fields = """  final String host;
  final int httpPort;

  String get authenticatedUri {
    final parsed = Uri.parse(streamUri);
    if (parsed.scheme.toLowerCase() != 'rtsp' || username.isEmpty) return streamUri;
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
"""
new_fields = """  final String host;
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
"""
if old_fields in s:
    s = s.replace(old_fields, new_fields, 1)
assert 'String authenticated(String rawStreamUri)' in s and '_CameraDevice copyWith' in s, 'V95 camera model stream helpers missing'

# Extend each tile with its chosen stream and lifecycle state.
old_tile_ctor = """    required this.camera,
    required this.selected,
    required this.audioEnabled,
"""
new_tile_ctor = """    required this.camera,
    required this.streamUri,
    required this.qualityLabel,
    required this.networkCachingMs,
    required this.active,
    required this.selected,
    required this.audioEnabled,
"""
if old_tile_ctor in s:
    s = s.replace(old_tile_ctor, new_tile_ctor, 1)

old_tile_fields = """  final _CameraDevice camera;
  final bool selected;
  final bool audioEnabled;
"""
new_tile_fields = """  final _CameraDevice camera;
  final String streamUri;
  final String qualityLabel;
  final int networkCachingMs;
  final bool active;
  final bool selected;
  final bool audioEnabled;
"""
if old_tile_fields in s:
    s = s.replace(old_tile_fields, new_tile_fields, 1)
assert 'final String qualityLabel;' in s and 'final bool active;' in s, 'V95 tile fields missing'

old_controller = """    controller = _makeController();
    controller.addListener(_playerChanged);
  }

  VlcPlayerController _makeController() => VlcPlayerController.network(
        widget.camera.authenticatedUri,
        hwAcc: HwAcc.full,
        autoPlay: true,
        allowBackgroundPlayback: false,
        options: VlcPlayerOptions(
          advanced: VlcAdvancedOptions([VlcAdvancedOptions.networkCaching(350)]),
"""
new_controller = """    controller = _makeController();
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
"""
if old_controller in s:
    s = s.replace(old_controller, new_controller, 1)
assert 'autoPlay: widget.active' in s, 'V95 lifecycle-aware VLC controller missing'

old_did_update = """    if (oldWidget.audioEnabled != widget.audioEnabled) {
      controller.setVolume(widget.audioEnabled ? 100 : 0);
    }
"""
new_did_update = """    if (oldWidget.active != widget.active) {
      if (widget.active) {
        unawaited(controller.play());
      } else {
        unawaited(controller.stop());
      }
    }
    if (oldWidget.audioEnabled != widget.audioEnabled || oldWidget.active != widget.active) {
      unawaited(controller.setVolume(widget.active && widget.audioEnabled ? 100 : 0));
    }
"""
if old_did_update in s:
    s = s.replace(old_did_update, new_did_update, 1)
assert 'oldWidget.active != widget.active' in s, 'V95 tile lifecycle update missing'

# Render a lightweight paused tile whenever the app/wall is inactive.
old_player = """            VlcPlayer(
              controller: controller,
              aspectRatio: 16 / 9,
              placeholder: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
"""
new_player = """            if (widget.active)
              VlcPlayer(
                controller: controller,
                aspectRatio: 16 / 9,
                placeholder: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else
              const Center(child: Icon(Icons.pause_circle_outline_rounded, color: Colors.white38, size: 34)),
"""
if old_player in s:
    s = s.replace(old_player, new_player, 1)

# Put the actual stream tier on each tile. MAIN* means AUTO/LOW had to fall
# back because the camera did not report a distinct substream.
thermal_anchor = """            if (widget.camera.thermal)
              const Positioned(right: 7, top: 7, child: Icon(Icons.thermostat_rounded, color: Colors.orangeAccent, size: 20)),
"""
if 'widget.qualityLabel' not in s:
    assert thermal_anchor in s, 'V95 tile thermal badge anchor missing'
    badge = """            Positioned(
              right: 7,
              top: widget.camera.thermal ? 31 : 7,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(5)),
                child: Text(widget.qualityLabel, style: const TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.w800)),
              ),
            ),
"""
    s = s.replace(thermal_anchor, thermal_anchor + badge, 1)

s = s.replace(
    'IconButton(onPressed: _reconnect, icon: reconnecting ?',
    'IconButton(onPressed: widget.active ? _reconnect : null, icon: reconnecting ?',
    1,
)

camera_path.write_text(s, encoding='utf-8')

checks = {
    'lib/monitoring/camera_stream_profile_service.dart': [
        'class CameraStreamProfileService',
        'GetProfiles',
        'GetStreamUri',
        'subStreamUri',
    ],
    'lib/monitoring/dahua_thermal_camera_onboarding_page.dart': [
        "import 'camera_stream_profile_service.dart';",
        'discoveredSubStreamUri',
        "'substream_uri': discoveredSubStreamUri",
        'adaptive_wall_streams',
    ],
    'lib/monitoring/camera_center_page.dart': [
        "qualityMode = 'auto'",
        '_discoverMissingStreamProfiles',
        '_gridStreamFor',
        'addAutomaticKeepAlives: false',
        'autoPlay: widget.active',
        "tooltip: 'Wall stream quality'",
        'setState(() => wallActive = false)',
        'widget.qualityLabel',
    ],
}
for path, markers in checks.items():
    text = Path(path).read_text(encoding='utf-8')
    for marker in markers:
        if marker not in text:
            raise SystemExit(f'V95 verification missing in {path}: {marker}')

print('Vet AI V95 applied: real ONVIF substreams, adaptive camera wall quality, decoder lifecycle control and main-stream fullscreen')
