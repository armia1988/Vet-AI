import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';
import 'package:path_provider/path_provider.dart';

import 'camera_connection_service.dart';
import 'camera_control_page.dart';

class CameraDevicePage extends StatefulWidget {
  const CameraDevicePage({
    super.key,
    required this.cameraName,
    required this.vendor,
    required this.host,
    required this.httpPort,
    required this.rtspPort,
    required this.username,
    required this.password,
    required this.streamUri,
    this.subStreamUri = '',
    this.onvif = false,
    this.channel = 1,
    this.onChannelChanged,
  });

  final String cameraName;
  final String vendor;
  final String host;
  final int httpPort;
  final int rtspPort;
  final String username;
  final String password;
  final String streamUri;
  final String subStreamUri;
  final bool onvif;
  final int channel;
  final Future<void> Function(int channel)? onChannelChanged;

  @override
  State<CameraDevicePage> createState() => _CameraDevicePageState();
}

class _CameraDevicePageState extends State<CameraDevicePage> {
  static const _nativeConnector = CameraConnectionService();

  late VlcPlayerController _controller;
  Timer? _startupTimer;
  bool playing = false;
  bool audioEnabled = false;
  bool recording = false;
  bool checkingHealth = false;
  bool ptzBusy = false;
  String? playerError;
  String healthText = '';
  late int channel;

  bool get isDahua {
    final value = widget.vendor.toLowerCase();
    return value.contains('dahua') || value.contains('amcrest');
  }

  String _t(String en, String ar, String nl) {
    final code = Localizations.localeOf(context).languageCode.toLowerCase();
    if (code == 'ar') return ar;
    if (code == 'nl') return nl;
    return en;
  }

  @override
  void initState() {
    super.initState();
    channel = widget.channel.clamp(1, 64);
    _controller = _newController(_channelStream(channel));
    _controller.addListener(_playerChanged);
    _armStartupTimeout();
  }

  String _channelStream(int selectedChannel) {
    var source = widget.subStreamUri.trim().isNotEmpty
        ? widget.subStreamUri.trim()
        : widget.streamUri.trim();
    if (!isDahua || source.isEmpty) return source;
    final channelExp = RegExp(r'([?&])channel=\d+', caseSensitive: false);
    if (channelExp.hasMatch(source)) {
      return source.replaceFirstMapped(
        channelExp,
        (match) => '${match.group(1)}channel=$selectedChannel',
      );
    }
    if (source.contains('?')) return '$source&channel=$selectedChannel';
    return '$source?channel=$selectedChannel&subtype=1';
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
    _startupTimer = Timer(const Duration(seconds: 12), () {
      if (!mounted || playing) return;
      setState(() {
        playerError ??= _t(
          'No video received from the camera.',
          'لم يتم استقبال فيديو من الكاميرا.',
          'Geen video van de camera ontvangen.',
        );
      });
    });
  }

  void _playerChanged() {
    if (!mounted) return;
    final value = _controller.value;
    final nextPlaying = value.isPlaying;
    final nextError = value.hasError && value.errorDescription.trim().isNotEmpty
        ? value.errorDescription.trim()
        : null;
    if (nextPlaying) _startupTimer?.cancel();
    if (playing != nextPlaying || nextError != playerError) {
      setState(() {
        playing = nextPlaying;
        if (nextPlaying) {
          playerError = null;
        } else if (nextError != null) {
          playerError = nextError;
        }
      });
    }
  }

  Future<void> _restartPlayer({int? newChannel}) async {
    final target = (newChannel ?? channel).clamp(1, 64);
    _startupTimer?.cancel();
    _controller.removeListener(_playerChanged);
    try {
      if (recording) await _controller.stopRecording();
      await _controller.stop();
    } catch (_) {}
    _controller.dispose();
    channel = target;
    playing = false;
    recording = false;
    playerError = null;
    _controller = _newController(_channelStream(channel));
    _controller.addListener(_playerChanged);
    if (mounted) setState(() {});
    _armStartupTimeout();
    await widget.onChannelChanged?.call(channel);
  }

  Future<void> _toggleAudio() async {
    audioEnabled = !audioEnabled;
    await _controller.setVolume(audioEnabled ? 100 : 0);
    if (mounted) setState(() {});
  }

  String _safeName(String value) => value
      .replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');

  Future<Directory> _mediaDirectory(String child) async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}/VetAI/$child');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> _snapshot() async {
    try {
      final bytes = await _controller.takeSnapshot();
      if (bytes == null || bytes.isEmpty) {
        throw StateError('No video frame is available yet.');
      }
      final dir = await _mediaDirectory('CameraSnapshots');
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final name = _safeName(widget.cameraName).isEmpty
          ? 'camera'
          : _safeName(widget.cameraName);
      final file = File('${dir.path}/${name}_ch${channel}_$stamp.jpg');
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_t(
            'Snapshot saved on this device.',
            'تم حفظ الصورة على هذا الجهاز.',
            'Momentopname is op dit apparaat opgeslagen.',
          )),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_t('Snapshot failed', 'فشل التقاط الصورة', 'Momentopname mislukt')}: $e')),
      );
    }
  }

  Future<void> _toggleRecording() async {
    try {
      if (!recording) {
        final dir = await _mediaDirectory('CameraRecordings');
        final started = await _controller.startRecording(dir.path);
        if (started != true) throw StateError('Recording could not be started.');
        if (mounted) setState(() => recording = true);
        return;
      }
      await _controller.stopRecording();
      final path = (_controller.value.recordPath ?? '').trim();
      if (mounted) {
        setState(() => recording = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(path.isEmpty
                ? _t('Recording saved on this device.', 'تم حفظ التسجيل على هذا الجهاز.', 'Opname is op dit apparaat opgeslagen.')
                : '${_t('Recording saved', 'تم حفظ التسجيل', 'Opname opgeslagen')}: $path'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => recording = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_t('Recording failed', 'فشل التسجيل', 'Opname mislukt')}: $e')),
      );
    }
  }

  Future<bool> _portOpen(int port) async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        widget.host,
        port,
        timeout: const Duration(seconds: 4),
      );
      return true;
    } catch (_) {
      return false;
    } finally {
      socket?.destroy();
    }
  }

  Future<void> _checkHealth() async {
    if (checkingHealth) return;
    setState(() {
      checkingHealth = true;
      healthText = '';
    });
    final httpOk = await _portOpen(widget.httpPort);
    final rtspOk = await _portOpen(widget.rtspPort);
    if (!mounted) return;
    final liveOk = _controller.value.isPlaying;
    setState(() {
      checkingHealth = false;
      healthText = _t(
        'HTTP ${httpOk ? 'OK' : 'offline'} • RTSP ${rtspOk ? 'OK' : 'offline'} • Live ${liveOk ? 'playing' : 'not playing'}',
        'HTTP ${httpOk ? 'يعمل' : 'غير متصل'} • RTSP ${rtspOk ? 'يعمل' : 'غير متصل'} • البث ${liveOk ? 'يعمل' : 'لا يعمل'}',
        'HTTP ${httpOk ? 'OK' : 'offline'} • RTSP ${rtspOk ? 'OK' : 'offline'} • Live ${liveOk ? 'speelt' : 'speelt niet'}',
      );
    });
  }

  Future<void> _dahuaMove(String code) async {
    if (ptzBusy) return;
    setState(() => ptzBusy = true);
    try {
      await _nativeConnector.dahuaPtz(
        host: widget.host,
        port: widget.httpPort,
        username: widget.username,
        password: widget.password,
        code: code,
        stop: false,
      );
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await _nativeConnector.dahuaPtz(
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
          SnackBar(content: Text('PTZ: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => ptzBusy = false);
    }
  }

  Future<void> _openControls() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => CameraControlPage(
          cameraName: widget.cameraName,
          host: widget.host,
          httpPort: widget.httpPort,
          username: widget.username,
          password: widget.password,
          vendor: widget.vendor,
        ),
      ),
    );
  }

  Widget _roundAction(IconData icon, String label, VoidCallback? onTap,
      {bool active = false}) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 23,
                backgroundColor: active
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Icon(
                  icon,
                  color: active
                      ? Theme.of(context).colorScheme.onPrimary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 7),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ptzButton(IconData icon, String code) {
    return IconButton.filledTonal(
      onPressed: ptzBusy ? null : () => _dahuaMove(code),
      icon: Icon(icon),
      iconSize: 30,
    );
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
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.cameraName),
            Text(
              '${widget.vendor} • ${widget.host}',
              style: const TextStyle(fontSize: 11, color: Colors.white60),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: checkingHealth ? null : _checkHealth,
            tooltip: _t('Health check', 'فحص الحالة', 'Statuscontrole'),
            icon: const Icon(Icons.monitor_heart_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  VlcPlayer(
                    key: ValueKey('camera-${channel}-${_channelStream(channel)}'),
                    controller: _controller,
                    aspectRatio: 16 / 9,
                    placeholder: const SizedBox.shrink(),
                  ),
                  if (!playing && playerError == null)
                    const Center(child: CircularProgressIndicator()),
                  if (playerError != null)
                    Container(
                      color: Colors.black87,
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.videocam_off_rounded,
                              color: Colors.orangeAccent, size: 48),
                          const SizedBox(height: 10),
                          Text(
                            playerError!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white70),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: () => _restartPlayer(),
                            icon: const Icon(Icons.refresh_rounded),
                            label: Text(_t('Retry', 'إعادة المحاولة', 'Opnieuw')),
                          ),
                        ],
                      ),
                    ),
                  Positioned(
                    left: 10,
                    top: 10,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              playing ? Icons.circle : Icons.circle_outlined,
                              size: 10,
                              color: playing ? Colors.greenAccent : Colors.orangeAccent,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              playing ? 'LIVE' : _t('Connecting', 'اتصال', 'Verbinden'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (recording)
                    const Positioned(
                      right: 10,
                      top: 10,
                      child: Chip(
                        avatar: Icon(Icons.fiber_manual_record, color: Colors.red, size: 16),
                        label: Text('REC'),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
                  children: [
                    Row(
                      children: [
                        _roundAction(
                          audioEnabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                          _t('Audio', 'الصوت', 'Audio'),
                          _toggleAudio,
                          active: audioEnabled,
                        ),
                        _roundAction(
                          Icons.photo_camera_rounded,
                          _t('Snapshot', 'صورة', 'Foto'),
                          playing ? _snapshot : null,
                        ),
                        _roundAction(
                          recording ? Icons.stop_circle_rounded : Icons.fiber_manual_record_rounded,
                          recording
                              ? _t('Stop', 'إيقاف', 'Stop')
                              : _t('Record', 'تسجيل', 'Opnemen'),
                          playing || recording ? _toggleRecording : null,
                          active: recording,
                        ),
                        _roundAction(
                          Icons.tune_rounded,
                          _t('Controls', 'تحكم', 'Bediening'),
                          _openControls,
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    if (isDahua) ...[
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _t('Channel', 'القناة', 'Kanaal'),
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                          DropdownButton<int>(
                            value: channel,
                            items: List.generate(
                              16,
                              (index) => DropdownMenuItem(
                                value: index + 1,
                                child: Text('${index + 1}'),
                              ),
                            ),
                            onChanged: (value) {
                              if (value != null && value != channel) {
                                _restartPlayer(newChannel: value);
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _t('Direct Dahua PTZ', 'تحكم Dahua مباشر', 'Directe Dahua PTZ'),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 10),
                      Center(child: _ptzButton(Icons.keyboard_arrow_up_rounded, 'Up')),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _ptzButton(Icons.keyboard_arrow_left_rounded, 'Left'),
                          const SizedBox(width: 26),
                          _ptzButton(Icons.keyboard_arrow_right_rounded, 'Right'),
                        ],
                      ),
                      Center(child: _ptzButton(Icons.keyboard_arrow_down_rounded, 'Down')),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          OutlinedButton.icon(
                            onPressed: ptzBusy ? null : () => _dahuaMove('ZoomWide'),
                            icon: const Icon(Icons.zoom_out_rounded),
                            label: Text(_t('Zoom out', 'تصغير', 'Uitzoomen')),
                          ),
                          const SizedBox(width: 12),
                          OutlinedButton.icon(
                            onPressed: ptzBusy ? null : () => _dahuaMove('ZoomTele'),
                            icon: const Icon(Icons.zoom_in_rounded),
                            label: Text(_t('Zoom in', 'تكبير', 'Inzoomen')),
                          ),
                        ],
                      ),
                      const Divider(height: 28),
                    ],
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: checkingHealth
                          ? const SizedBox.square(
                              dimension: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.monitor_heart_outlined),
                      title: Text(_t('Camera health', 'حالة الكاميرا', 'Camerastatus')),
                      subtitle: Text(
                        healthText.isEmpty
                            ? _t('Tap to check HTTP, RTSP and current live stream.', 'اضغط لفحص HTTP وRTSP والبث الحالي.', 'Tik om HTTP, RTSP en de livestream te controleren.')
                            : healthText,
                      ),
                      trailing: const Icon(Icons.refresh_rounded),
                      onTap: checkingHealth ? null : _checkHealth,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
