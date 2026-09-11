from pathlib import Path

# V112 — fix the two real defects exposed by device testing:
# 1) V111 could save a Dahua camera after native identity + open RTSP port,
#    while the player still had no media. Harden VLC for Dahua Digest/RTSP-TCP,
#    prefer the H.264-compatible sub stream on Dahua, and stop infinite spinners.
# 2) Camera controls were still ONVIF-only. Standard Dahua cameras must use the
#    native Dahua CGI PTZ API when ONVIF is disabled.

# ---------------------------------------------------------------------------
# 1) Store a real Dahua sub-stream candidate during onboarding.
# ---------------------------------------------------------------------------
p = Path('lib/monitoring/dahua_thermal_camera_onboarding_page.dart')
s = p.read_text(encoding='utf-8')
old = """        discoveredSubStreamUri = discoveredProfiles?.subStreamUri;
        discoveredProfileCount = discoveredProfiles?.profiles.length ?? 0;
"""
new = """        discoveredSubStreamUri = discoveredProfiles?.subStreamUri ??
            (((cameraVendor == 'dahua' || cameraVendor == 'amcrest') &&
                    usableStream != null &&
                    usableStream.contains('subtype=0'))
                ? usableStream.replaceFirst('subtype=0', 'subtype=1')
                : null);
        discoveredProfileCount = discoveredProfiles?.profiles.length ?? 0;
"""
if old in s:
    s = s.replace(old, new, 1)
elif "usableStream.replaceFirst('subtype=0', 'subtype=1')" not in s:
    raise SystemExit('V112: onboarding substream anchor missing')
p.write_text(s, encoding='utf-8')

# ---------------------------------------------------------------------------
# 2) Replace the single-stream endless-spinner live page with a resilient
#    RTSP player: RTSP-over-TCP, VLC credential hints, main/sub fallback,
#    explicit error state and manual retry.
# ---------------------------------------------------------------------------
p = Path('lib/monitoring/camera_live_view_page.dart')
p.write_text(r'''import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';

class CameraLiveViewPage extends StatefulWidget {
  const CameraLiveViewPage({
    super.key,
    required this.streamUri,
    required this.username,
    required this.password,
    this.cameraName = 'IP Camera',
  });

  final String streamUri;
  final String username;
  final String password;
  final String cameraName;

  @override
  State<CameraLiveViewPage> createState() => _CameraLiveViewPageState();
}

class _CameraLiveViewPageState extends State<CameraLiveViewPage> {
  late VlcPlayerController _controller;
  Timer? _startupTimer;
  late final List<String> _streams;
  int _streamIndex = 0;
  bool _playing = false;
  bool _switching = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _streams = _candidateStreams(widget.streamUri);
    _controller = _newController(_streams.first);
    _controller.addListener(_playerChanged);
    _armStartupTimeout();
  }

  List<String> _candidateStreams(String source) {
    final result = <String>[];
    void add(String value) {
      final v = value.trim();
      if (v.isNotEmpty && !result.contains(v)) result.add(v);
    }

    // Dahua main streams are often H.265/H.265+ while the substream is H.264.
    // Try the supplied stream first, then the alternate subtype automatically.
    add(source);
    if (source.contains('subtype=0')) {
      add(source.replaceFirst('subtype=0', 'subtype=1'));
    } else if (source.contains('subtype=1')) {
      add(source.replaceFirst('subtype=1', 'subtype=0'));
    }
    return result;
  }

  String _authenticated(String source) {
    final parsed = Uri.parse(source);
    if (parsed.scheme.toLowerCase() != 'rtsp' || widget.username.isEmpty) {
      return source;
    }
    return Uri(
      scheme: parsed.scheme,
      userInfo:
          '${Uri.encodeComponent(widget.username)}:${Uri.encodeComponent(widget.password)}',
      host: parsed.host,
      port: parsed.hasPort ? parsed.port : null,
      path: parsed.path,
      query: parsed.hasQuery ? parsed.query : null,
      fragment: parsed.hasFragment ? parsed.fragment : null,
    ).toString();
  }

  VlcPlayerController _newController(String stream) =>
      VlcPlayerController.network(
        _authenticated(stream),
        hwAcc: HwAcc.auto,
        autoPlay: true,
        allowBackgroundPlayback: false,
        options: VlcPlayerOptions(
          advanced: VlcAdvancedOptions([
            VlcAdvancedOptions.networkCaching(1200),
            VlcAdvancedOptions.liveCaching(1200),
          ]),
          rtp: VlcRtpOptions([VlcRtpOptions.rtpOverRtsp(true)]),
          http: VlcHttpOptions([VlcHttpOptions.httpReconnect(true)]),
          extras: [
            ':rtsp-tcp',
            ':network-caching=1200',
            ':live-caching=1200',
            ':clock-jitter=0',
            ':clock-synchro=0',
            if (widget.username.isNotEmpty) ':rtsp-user=${widget.username}',
            if (widget.username.isNotEmpty) ':rtsp-pwd=${widget.password}',
          ],
        ),
      );

  void _armStartupTimeout() {
    _startupTimer?.cancel();
    _startupTimer = Timer(const Duration(seconds: 10), () {
      if (!mounted || _playing) return;
      unawaited(_fallbackOrFail('The camera did not start sending video.'));
    });
  }

  void _playerChanged() {
    if (!mounted || _switching) return;
    final value = _controller.value;
    if (value.isPlaying) {
      _startupTimer?.cancel();
      if (!_playing || _error != null) {
        setState(() {
          _playing = true;
          _error = null;
        });
      }
      return;
    }
    if (value.hasError) {
      final message = value.errorDescription.trim().isEmpty
          ? 'RTSP playback failed.'
          : value.errorDescription.trim();
      unawaited(_fallbackOrFail(message));
    }
  }

  Future<void> _fallbackOrFail(String reason) async {
    if (_switching || _playing || !mounted) return;
    final next = _streamIndex + 1;
    if (next >= _streams.length) {
      _startupTimer?.cancel();
      setState(() => _error = reason);
      return;
    }
    await _switchTo(next);
  }

  Future<void> _switchTo(int index) async {
    if (_switching || !mounted) return;
    _switching = true;
    _startupTimer?.cancel();
    final old = _controller;
    old.removeListener(_playerChanged);
    try {
      await old.stop();
    } catch (_) {}
    old.dispose();

    _streamIndex = index;
    _playing = false;
    _error = null;
    _controller = _newController(_streams[_streamIndex]);
    _controller.addListener(_playerChanged);
    if (mounted) setState(() {});
    _switching = false;
    _armStartupTimeout();
  }

  Future<void> _retry() async {
    if (_switching) return;
    await _switchTo(0);
  }

  @override
  void dispose() {
    _startupTimer?.cancel();
    _controller.removeListener(_playerChanged);
    unawaited(_controller.stop());
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.cameraName),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Center(
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                VlcPlayer(
                  key: ValueKey('rtsp-$_streamIndex-${_streams[_streamIndex]}'),
                  controller: _controller,
                  aspectRatio: 16 / 9,
                  placeholder: const SizedBox.shrink(),
                ),
                if (!_playing && _error == null)
                  const Center(child: CircularProgressIndicator()),
                if (_error != null)
                  Container(
                    color: Colors.black87,
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.videocam_off_rounded,
                            color: Colors.orangeAccent, size: 54),
                        const SizedBox(height: 14),
                        const Text(
                          'Live video could not be started',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _error!,
                          style: const TextStyle(color: Colors.white70),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _retry,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Retry stream'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
''', encoding='utf-8')

# ---------------------------------------------------------------------------
# 3) Dahua native PTZ API. This reuses the already authenticated Dahua HTTP
#    Digest transport added in V109 instead of sending a non-ONVIF camera to
#    ONVIF control endpoints.
# ---------------------------------------------------------------------------
p = Path('lib/monitoring/camera_connection_service.dart')
s = p.read_text(encoding='utf-8')
if 'Future<void> dahuaPtz({' not in s:
    anchor = '  Future<Map<String, String>> _probeVendorIdentity({\n'
    native = r'''  Future<void> dahuaPtz({
    required String host,
    required int port,
    required String username,
    required String password,
    required String code,
    required bool stop,
    int speed = 4,
  }) async {
    final action = stop ? 'stop' : 'start';
    final safeSpeed = speed.clamp(1, 8);
    final path = '/cgi-bin/ptz.cgi?action=$action&channel=0&code=$code'
        '&arg1=0&arg2=$safeSpeed&arg3=0&arg4=0';
    await _authenticatedHttpGet(
      host: host,
      port: port,
      path: path,
      username: username,
      password: password,
    );
  }

'''
    if anchor not in s:
        raise SystemExit('V112: Dahua native API insertion anchor missing')
    s = s.replace(anchor, native + anchor, 1)
p.write_text(s, encoding='utf-8')

# ---------------------------------------------------------------------------
# 4) Camera control page: route Dahua/Amcrest to native CGI PTZ instead of the
#    ONVIF-only service. Other camera brands keep their existing ONVIF path.
# ---------------------------------------------------------------------------
p = Path('lib/monitoring/camera_control_page.dart')
s = p.read_text(encoding='utf-8')
if "import 'camera_connection_service.dart';" not in s:
    s = s.replace(
        "import 'onvif_camera_control_service.dart';\n",
        "import 'onvif_camera_control_service.dart';\nimport 'camera_connection_service.dart';\n",
        1,
    )

s = s.replace(
    "    required this.password,\n  });",
    "    required this.password,\n    this.vendor = '',\n  });",
    1,
)
s = s.replace(
    "  final String password;\n",
    "  final String password;\n  final String vendor;\n",
    1,
)
if 'final String vendor;' not in s:
    raise SystemExit('V112: CameraControlPage vendor field missing')

if 'static const nativeConnector = CameraConnectionService();' not in s:
    s = s.replace(
        "class _CameraControlPageState extends State<CameraControlPage> {\n",
        "class _CameraControlPageState extends State<CameraControlPage> {\n"
        "  static const nativeConnector = CameraConnectionService();\n"
        "  bool get _isDahua {\n"
        "    final v = widget.vendor.toLowerCase();\n"
        "    return v.contains('dahua') || v.contains('amcrest');\n"
        "  }\n",
        1,
    )

s = s.replace(
    "    service = OnvifCameraControlService(\n"
    "      host: widget.host,\n"
    "      httpPort: widget.httpPort,\n"
    "      username: widget.username,\n"
    "      password: widget.password,\n"
    "    );\n"
    "    _load();\n",
    "    if (_isDahua) {\n"
    "      loading = false;\n"
    "    } else {\n"
    "      service = OnvifCameraControlService(\n"
    "        host: widget.host,\n"
    "        httpPort: widget.httpPort,\n"
    "        username: widget.username,\n"
    "        password: widget.password,\n"
    "      );\n"
    "      _load();\n"
    "    }\n",
    1,
)

if 'Future<void> _dahuaMove(String code)' not in s:
    anchor = '  Future<void> _gotoPreset(OnvifPreset preset) async {\n'
    helper = r'''  Future<void> _dahuaMove(String code) async {
    if (moving) return;
    setState(() => moving = true);
    try {
      await nativeConnector.dahuaPtz(
        host: widget.host,
        port: widget.httpPort,
        username: widget.username,
        password: widget.password,
        code: code,
        stop: false,
      );
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await nativeConnector.dahuaPtz(
        host: widget.host,
        port: widget.httpPort,
        username: widget.username,
        password: widget.password,
        code: code,
        stop: true,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Dahua PTZ failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => moving = false);
    }
  }

'''
    if anchor not in s:
        raise SystemExit('V112: PTZ helper insertion anchor missing')
    s = s.replace(anchor, helper + anchor, 1)

s = s.replace(
    "      body: loading\n"
    "          ? const Center(child: CircularProgressIndicator())\n"
    "          : error != null\n"
    "              ? _errorState()\n"
    "              : _content(),\n",
    "      body: loading\n"
    "          ? const Center(child: CircularProgressIndicator())\n"
    "          : _isDahua\n"
    "              ? _dahuaContent()\n"
    "              : error != null\n"
    "                  ? _errorState()\n"
    "                  : _content(),\n",
    1,
)
if '? _dahuaContent()' not in s:
    raise SystemExit('V112: native Dahua control body routing missing')

if 'Widget _dahuaContent()' not in s:
    anchor = '  Widget _content() {\n'
    native_ui = r'''  Widget _dahuaContent() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _section(
          title: 'Dahua direct control',
          child: Column(
            children: [
              const Text(
                'This camera is controlled through the native Dahua authenticated device API. ONVIF is not required.',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _ptzButton(Icons.keyboard_arrow_up_rounded,
                      () => _dahuaMove('Up')),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _ptzButton(Icons.keyboard_arrow_left_rounded,
                      () => _dahuaMove('Left')),
                  const SizedBox(width: 10),
                  _ptzButton(Icons.stop_rounded, () async {}),
                  const SizedBox(width: 10),
                  _ptzButton(Icons.keyboard_arrow_right_rounded,
                      () => _dahuaMove('Right')),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _ptzButton(Icons.keyboard_arrow_down_rounded,
                      () => _dahuaMove('Down')),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: moving ? null : () => _dahuaMove('ZoomWide'),
                    icon: const Icon(Icons.zoom_out_rounded),
                    label: const Text('Zoom out'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: moving ? null : () => _dahuaMove('ZoomTele'),
                    icon: const Icon(Icons.zoom_in_rounded),
                    label: const Text('Zoom in'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _section(
          title: 'Connection',
          child: Column(
            children: [
              _textRow('Host', widget.host),
              _textRow('HTTP port', '${widget.httpPort}'),
              _textRow('Transport', 'Dahua CGI / direct RTSP'),
            ],
          ),
        ),
      ],
    );
  }

'''
    if anchor not in s:
        raise SystemExit('V112: control page content anchor missing')
    s = s.replace(anchor, native_ui + anchor, 1)
p.write_text(s, encoding='utf-8')

# ---------------------------------------------------------------------------
# 5) Live wall: prefer Dahua subtype=1 in AUTO/LOW, harden VLC transport,
#    show actual player errors, and route the control button with vendor info.
# ---------------------------------------------------------------------------
p = Path('lib/monitoring/camera_center_page.dart')
s = p.read_text(encoding='utf-8')

s = s.replace(
    "          password: camera.password,\n        ),",
    "          password: camera.password,\n          vendor: camera.vendor,\n        ),",
    1,
)
if 'vendor: camera.vendor' not in s:
    raise SystemExit('V112: camera control vendor routing missing')

old_grid = r'''  String _gridStreamFor(_CameraDevice camera) {
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
'''
new_grid = r'''  String _compatibleSubstream(_CameraDevice camera) {
    if (camera.subStreamUri.isNotEmpty) return camera.subStreamUri;
    final vendor = camera.vendor.toLowerCase();
    if ((vendor.contains('dahua') || vendor.contains('amcrest')) &&
        camera.streamUri.contains('subtype=0')) {
      return camera.streamUri.replaceFirst('subtype=0', 'subtype=1');
    }
    return '';
  }

  String _gridStreamFor(_CameraDevice camera) {
    if (qualityMode == 'high') return camera.streamUri;
    final sub = _compatibleSubstream(camera);
    if (qualityMode == 'low') return sub.isNotEmpty ? sub : camera.streamUri;
    final vendor = camera.vendor.toLowerCase();
    if ((vendor.contains('dahua') || vendor.contains('amcrest')) && sub.isNotEmpty) {
      return sub;
    }
    if (_autoUsesSubstream && sub.isNotEmpty) return sub;
    return camera.streamUri;
  }

  String _gridQualityLabel(_CameraDevice camera) {
    final chosen = _gridStreamFor(camera);
    final sub = _compatibleSubstream(camera);
    if (sub.isNotEmpty && chosen == sub) return 'SUB';
    if ((qualityMode == 'low' || _autoUsesSubstream) && sub.isEmpty) return 'MAIN*';
    return 'MAIN';
  }
'''
if old_grid in s:
    s = s.replace(old_grid, new_grid, 1)
elif 'String _compatibleSubstream(_CameraDevice camera)' not in s:
    raise SystemExit('V112: grid stream selection anchor missing')

old_make = r'''  VlcPlayerController _makeController() => VlcPlayerController.network(
        widget.camera.authenticated(widget.streamUri),
        hwAcc: HwAcc.full,
        autoPlay: widget.active,
        allowBackgroundPlayback: false,
        options: VlcPlayerOptions(
          advanced: VlcAdvancedOptions([VlcAdvancedOptions.networkCaching(widget.networkCachingMs)]),
          rtp: VlcRtpOptions([VlcRtpOptions.rtpOverRtsp(true)]),
        ),
      );
'''
new_make = r'''  VlcPlayerController _makeController() => VlcPlayerController.network(
        widget.camera.authenticated(widget.streamUri),
        hwAcc: HwAcc.auto,
        autoPlay: widget.active,
        allowBackgroundPlayback: false,
        options: VlcPlayerOptions(
          advanced: VlcAdvancedOptions([
            VlcAdvancedOptions.networkCaching(widget.networkCachingMs < 800
                ? 800
                : widget.networkCachingMs),
            VlcAdvancedOptions.liveCaching(800),
          ]),
          rtp: VlcRtpOptions([VlcRtpOptions.rtpOverRtsp(true)]),
          http: VlcHttpOptions([VlcHttpOptions.httpReconnect(true)]),
          extras: [
            ':rtsp-tcp',
            ':clock-jitter=0',
            ':clock-synchro=0',
            if (widget.camera.username.isNotEmpty)
              ':rtsp-user=${widget.camera.username}',
            if (widget.camera.username.isNotEmpty)
              ':rtsp-pwd=${widget.camera.password}',
          ],
        ),
      );
'''
if old_make in s:
    s = s.replace(old_make, new_make, 1)
elif "':rtsp-tcp'" not in s:
    raise SystemExit('V112: wall VLC options anchor missing')

s = s.replace(
    "  bool initialized = false;\n  bool reconnecting = false;\n",
    "  bool initialized = false;\n  bool playing = false;\n  bool reconnecting = false;\n  String? playerError;\n  Timer? startupTimer;\n",
    1,
)

s = s.replace(
    "    unawaited(controller.setVolume(widget.audioEnabled ? 100 : 0));\n",
    "    unawaited(controller.setVolume(widget.audioEnabled ? 100 : 0));\n"
    "    _armStartupTimer();\n",
    1,
)

old_changed = r'''  void _playerChanged() {
    final value = controller.value;
    if (!mounted) return;
    final next = value.isInitialized;
    if (next != initialized) setState(() => initialized = next);
  }
'''
new_changed = r'''  void _armStartupTimer() {
    startupTimer?.cancel();
    startupTimer = Timer(const Duration(seconds: 10), () {
      if (!mounted || playing) return;
      setState(() {
        playerError ??= 'No video received from the camera.';
      });
    });
  }

  void _playerChanged() {
    final value = controller.value;
    if (!mounted) return;
    final nextInitialized = value.isInitialized;
    final nextPlaying = value.isPlaying;
    final nextError = value.hasError ? value.errorDescription : null;
    if (nextPlaying) startupTimer?.cancel();
    if (nextInitialized != initialized || nextPlaying != playing || nextError != playerError) {
      setState(() {
        initialized = nextInitialized;
        playing = nextPlaying;
        if (nextPlaying) {
          playerError = null;
        } else if (nextError != null && nextError.trim().isNotEmpty) {
          playerError = nextError.trim();
        }
      });
    }
  }
'''
if old_changed in s:
    s = s.replace(old_changed, new_changed, 1)
elif 'void _armStartupTimer()' not in s:
    raise SystemExit('V112: player state anchor missing')

s = s.replace(
    "    setState(() => reconnecting = true);\n    try {\n",
    "    setState(() {\n      reconnecting = true;\n      playerError = null;\n      playing = false;\n    });\n    _armStartupTimer();\n    try {\n",
    1,
)

s = s.replace(
    "  void dispose() {\n    controller.removeListener(_playerChanged);\n",
    "  void dispose() {\n    startupTimer?.cancel();\n    controller.removeListener(_playerChanged);\n",
    1,
)

placeholder = """                placeholder: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
"""
replacement = """                placeholder: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
"""
# Keep VLC placeholder but add an explicit non-infinite failure overlay after it.
if "if (playerError != null)" not in s:
    marker = """            Positioned(
              left: 7,
              top: 6,
"""
    overlay = """            if (playerError != null)
              Positioned.fill(
                child: Container(
                  color: Colors.black87,
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.videocam_off_rounded,
                          color: Colors.orangeAccent, size: 30),
                      const SizedBox(height: 6),
                      const Text('Live stream unavailable',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 5),
                      Text(playerError!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white60, fontSize: 10)),
                      const SizedBox(height: 6),
                      TextButton.icon(
                        onPressed: _reconnect,
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
"""
    if marker not in s:
        raise SystemExit('V112: tile overlay anchor missing')
    s = s.replace(marker, overlay + marker, 1)

# Fullscreen uses the compatibility stream, not a hard-coded main stream.
s = s.replace(
    "      widget.camera.authenticatedUri,\n      hwAcc: HwAcc.full,\n",
    "      widget.camera.authenticated(widget.camera.compatibilityStreamUri),\n      hwAcc: HwAcc.auto,\n",
    1,
)
old_full_options = """      options: VlcPlayerOptions(
        advanced: VlcAdvancedOptions([VlcAdvancedOptions.networkCaching(300)]),
        rtp: VlcRtpOptions([VlcRtpOptions.rtpOverRtsp(true)]),
      ),
"""
new_full_options = """      options: VlcPlayerOptions(
        advanced: VlcAdvancedOptions([
          VlcAdvancedOptions.networkCaching(1200),
          VlcAdvancedOptions.liveCaching(1200),
        ]),
        rtp: VlcRtpOptions([VlcRtpOptions.rtpOverRtsp(true)]),
        http: VlcHttpOptions([VlcHttpOptions.httpReconnect(true)]),
        extras: [
          ':rtsp-tcp',
          ':network-caching=1200',
          ':clock-jitter=0',
          ':clock-synchro=0',
          if (widget.camera.username.isNotEmpty)
            ':rtsp-user=${widget.camera.username}',
          if (widget.camera.username.isNotEmpty)
            ':rtsp-pwd=${widget.camera.password}',
        ],
      ),
"""
if old_full_options in s:
    s = s.replace(old_full_options, new_full_options, 1)

if 'String get compatibilityStreamUri' not in s:
    anchor = '  String get authenticatedUri => authenticated(streamUri);\n'
    helper = r'''  String get compatibilityStreamUri {
    if (subStreamUri.isNotEmpty) return subStreamUri;
    final v = vendor.toLowerCase();
    if ((v.contains('dahua') || v.contains('amcrest')) &&
        streamUri.contains('subtype=0')) {
      return streamUri.replaceFirst('subtype=0', 'subtype=1');
    }
    return streamUri;
  }

'''
    if anchor not in s:
        raise SystemExit('V112: camera device compatibility getter anchor missing')
    s = s.replace(anchor, anchor + '\n' + helper, 1)

p.write_text(s, encoding='utf-8')

# ---------------------------------------------------------------------------
# Release verification guards.
# ---------------------------------------------------------------------------
onboarding = Path('lib/monitoring/dahua_thermal_camera_onboarding_page.dart').read_text(encoding='utf-8')
live = Path('lib/monitoring/camera_live_view_page.dart').read_text(encoding='utf-8')
center = Path('lib/monitoring/camera_center_page.dart').read_text(encoding='utf-8')
control = Path('lib/monitoring/camera_control_page.dart').read_text(encoding='utf-8')
connection = Path('lib/monitoring/camera_connection_service.dart').read_text(encoding='utf-8')

for token in [
    "usableStream.replaceFirst('subtype=0', 'subtype=1')",
    "':rtsp-tcp'",
    'Live video could not be started',
    'Retry stream',
]:
    if token not in onboarding + live:
        raise SystemExit(f'V112 live verification missing: {token}')
for token in [
    'String _compatibleSubstream(_CameraDevice camera)',
    'String get compatibilityStreamUri',
    'Live stream unavailable',
    'vendor: camera.vendor',
]:
    if token not in center:
        raise SystemExit(f'V112 wall verification missing: {token}')
for token in [
    'Future<void> dahuaPtz({',
    "path: '/cgi-bin/ptz.cgi",
]:
    if token not in connection:
        raise SystemExit(f'V112 Dahua API verification missing: {token}')
for token in [
    'Dahua direct control',
    "_dahuaMove('Left')",
    "_dahuaMove('ZoomTele')",
]:
    if token not in control:
        raise SystemExit(f'V112 control verification missing: {token}')

print('V112 Dahua live RTSP compatibility + native PTZ controls applied')
