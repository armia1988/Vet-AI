import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../i18n/vet_locale.dart';
import '../services/vet_backend.dart';
import '../theme/app_theme.dart';
import 'support_call_service.dart';

String _ct(BuildContext context, String en, String ar, String nl) =>
    VetTranslator.instance.text(
      localeCode: Localizations.localeOf(context).languageCode,
      en: en,
      ar: ar,
      nl: nl,
    );

class VetWebRtcCallPage extends StatefulWidget {
  const VetWebRtcCallPage({
    super.key,
    required this.call,
    required this.role,
    required this.isCaller,
  });

  final Map<String, dynamic> call;
  final String role;
  final bool isCaller;

  @override
  State<VetWebRtcCallPage> createState() => _VetWebRtcCallPageState();
}

class _VetWebRtcCallPageState extends State<VetWebRtcCallPage> {
  final localRenderer = RTCVideoRenderer();
  final remoteRenderer = RTCVideoRenderer();
  final calls = VetSupportCallService.instance;

  RTCPeerConnection? peer;
  MediaStream? localStream;
  StreamSubscription<List<Map<String, dynamic>>>? signalSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? callSubscription;

  final Set<String> seenSignals = <String>{};
  final List<RTCIceCandidate> pendingCandidates = <RTCIceCandidate>[];

  bool ready = false;
  bool remoteDescriptionSet = false;
  bool microphoneEnabled = true;
  bool cameraEnabled = true;
  bool speakerEnabled = true;
  bool ending = false;
  bool turnConfigured = false;
  String connectionLabel = 'Connecting';

  String get callId => widget.call['id'].toString();
  String get threadId => widget.call['thread_id'].toString();
  bool get isVideo => '${widget.call['call_type']}' == 'video';

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await localRenderer.initialize();
      await remoteRenderer.initialize();

      final ice = await calls.iceConfiguration(callId);
      turnConfigured = ice['turnConfigured'] == true;
      final iceServers = (ice['iceServers'] as List? ?? const <dynamic>[])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      final connection = await createPeerConnection({
        'iceServers': iceServers,
        'sdpSemantics': 'unified-plan',
      });
      peer = connection;

      connection.onIceCandidate = (candidate) {
        final value = candidate.candidate;
        if (value == null || value.isEmpty) return;
        unawaited(calls.sendSignal(
          callId: callId,
          type: 'candidate',
          payload: {
            'candidate': value,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          },
        ));
      };

      connection.onTrack = (event) {
        if (event.streams.isNotEmpty) {
          remoteRenderer.srcObject = event.streams.first;
        }
        if (mounted) setState(() => connectionLabel = 'Connected');
      };

      connection.onConnectionState = (state) {
        if (!mounted) return;
        setState(() {
          connectionLabel = switch (state) {
            RTCPeerConnectionState.RTCPeerConnectionStateConnected => 'Connected',
            RTCPeerConnectionState.RTCPeerConnectionStateConnecting => 'Connecting',
            RTCPeerConnectionState.RTCPeerConnectionStateDisconnected => 'Reconnecting',
            RTCPeerConnectionState.RTCPeerConnectionStateFailed => 'Connection failed',
            RTCPeerConnectionState.RTCPeerConnectionStateClosed => 'Ended',
            _ => connectionLabel,
          };
        });
      };

      final constraints = <String, dynamic>{
        'audio': <String, dynamic>{
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': isVideo
            ? <String, dynamic>{
                'facingMode': 'user',
                'width': <String, dynamic>{'ideal': 1280},
                'height': <String, dynamic>{'ideal': 720},
              }
            : false,
      };
      final stream = await navigator.mediaDevices.getUserMedia(constraints);
      localStream = stream;
      localRenderer.srcObject = stream;
      for (final track in stream.getTracks()) {
        await connection.addTrack(track, stream);
      }

      signalSubscription = calls.signalsStream(callId).listen(_consumeSignals);
      callSubscription = calls.callsStream(threadId).listen((rows) {
        final current = rows.where((row) => '${row['id']}' == callId);
        if (current.isEmpty) return;
        final status = '${current.first['status']}';
        if ((status == 'ended' || status == 'declined') && mounted && !ending) {
          Navigator.of(context).maybePop();
        }
      });

      if (widget.isCaller) {
        final offer = await connection.createOffer({
          'offerToReceiveAudio': true,
          'offerToReceiveVideo': isVideo,
        });
        await connection.setLocalDescription(offer);
        await calls.sendSignal(
          callId: callId,
          type: 'offer',
          payload: {'sdp': offer.sdp, 'type': offer.type},
        );
      }

      if (mounted) setState(() => ready = true);
    } catch (error) {
      if (!mounted) return;
      setState(() => connectionLabel = 'Could not connect');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_ct(context, 'The secure call could not start.', 'المكالمة الآمنة ما بدأتش.', 'De beveiligde oproep kon niet starten.')} $error',
          ),
          backgroundColor: VetColors.red,
        ),
      );
    }
  }

  Future<void> _consumeSignals(List<Map<String, dynamic>> rows) async {
    final userId = VetBackend.instance.currentUser?.id;
    final ordered = rows.toList(growable: false)
      ..sort((a, b) => '${a['created_at']}'.compareTo('${b['created_at']}'));

    for (final row in ordered) {
      final id = '${row['id']}';
      if (id.isEmpty || !seenSignals.add(id)) continue;
      if ('${row['sender_id']}' == userId) continue;

      final type = '${row['signal_type']}';
      final payload = row['payload'] is Map
          ? Map<String, dynamic>.from(row['payload'] as Map)
          : <String, dynamic>{};

      if (type == 'offer') {
        await _handleOffer(payload);
      } else if (type == 'answer') {
        await _handleAnswer(payload);
      } else if (type == 'candidate') {
        await _handleCandidate(payload);
      }
    }
  }

  Future<void> _handleOffer(Map<String, dynamic> payload) async {
    final connection = peer;
    final sdp = payload['sdp']?.toString();
    if (connection == null || sdp == null || sdp.isEmpty || remoteDescriptionSet) {
      return;
    }
    await connection.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
    remoteDescriptionSet = true;
    await _flushCandidates();

    if (!widget.isCaller) {
      final answer = await connection.createAnswer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': isVideo,
      });
      await connection.setLocalDescription(answer);
      await calls.sendSignal(
        callId: callId,
        type: 'answer',
        payload: {'sdp': answer.sdp, 'type': answer.type},
      );
    }
  }

  Future<void> _handleAnswer(Map<String, dynamic> payload) async {
    final connection = peer;
    final sdp = payload['sdp']?.toString();
    if (connection == null || sdp == null || sdp.isEmpty || remoteDescriptionSet) {
      return;
    }
    await connection.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
    remoteDescriptionSet = true;
    await _flushCandidates();
  }

  Future<void> _handleCandidate(Map<String, dynamic> payload) async {
    final candidateText = payload['candidate']?.toString();
    if (candidateText == null || candidateText.isEmpty) return;
    final rawIndex = payload['sdpMLineIndex'];
    final candidate = RTCIceCandidate(
      candidateText,
      payload['sdpMid']?.toString(),
      rawIndex is int ? rawIndex : int.tryParse('$rawIndex'),
    );
    if (!remoteDescriptionSet || peer == null) {
      pendingCandidates.add(candidate);
      return;
    }
    await peer!.addCandidate(candidate);
  }

  Future<void> _flushCandidates() async {
    final connection = peer;
    if (connection == null) return;
    for (final candidate in List<RTCIceCandidate>.from(pendingCandidates)) {
      await connection.addCandidate(candidate);
    }
    pendingCandidates.clear();
  }

  Future<void> _toggleMicrophone() async {
    microphoneEnabled = !microphoneEnabled;
    for (final track in localStream?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      track.enabled = microphoneEnabled;
    }
    if (mounted) setState(() {});
  }

  Future<void> _toggleCamera() async {
    cameraEnabled = !cameraEnabled;
    for (final track in localStream?.getVideoTracks() ?? const <MediaStreamTrack>[]) {
      track.enabled = cameraEnabled;
    }
    if (mounted) setState(() {});
  }

  Future<void> _switchCamera() async {
    final tracks = localStream?.getVideoTracks() ?? const <MediaStreamTrack>[];
    if (tracks.isEmpty) return;
    try {
      await Helper.switchCamera(tracks.first);
    } catch (_) {}
  }

  Future<void> _toggleSpeaker() async {
    speakerEnabled = !speakerEnabled;
    try {
      await Helper.setSpeakerphoneOn(speakerEnabled);
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _hangUp() async {
    if (ending) return;
    ending = true;
    try {
      await calls.end(callId);
    } catch (_) {}
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    signalSubscription?.cancel();
    callSubscription?.cancel();
    for (final track in localStream?.getTracks() ?? const <MediaStreamTrack>[]) {
      track.stop();
    }
    localStream?.dispose();
    peer?.close();
    peer?.dispose();
    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;
    localRenderer.dispose();
    remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remoteReady = remoteRenderer.srcObject != null;
    final background = const Color(0xFF0B141A);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_hangUp());
      },
      child: Scaffold(
        backgroundColor: background,
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: isVideo
                    ? (remoteReady
                        ? RTCVideoView(
                            remoteRenderer,
                            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                          )
                        : _WaitingView(
                            icon: Icons.videocam_rounded,
                            title: _ct(context, 'Video call', 'مكالمة فيديو', 'Videogesprek'),
                            subtitle: _statusText(context),
                          ))
                    : _WaitingView(
                        icon: Icons.call_rounded,
                        title: _ct(context, 'Voice call', 'مكالمة صوتية', 'Spraakoproep'),
                        subtitle: _statusText(context),
                      ),
              ),
              if (isVideo && localRenderer.srcObject != null)
                PositionedDirectional(
                  top: 18,
                  end: 14,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      width: 112,
                      height: 158,
                      color: Colors.black,
                      child: RTCVideoView(
                        localRenderer,
                        mirror: true,
                        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      ),
                    ),
                  ),
                ),
              PositionedDirectional(
                top: 8,
                start: 8,
                child: IconButton.filledTonal(
                  onPressed: _hangUp,
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
              ),
              Positioned(
                left: 14,
                right: 14,
                bottom: 18,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .48),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _CallControl(
                        icon: microphoneEnabled ? Icons.mic_rounded : Icons.mic_off_rounded,
                        active: microphoneEnabled,
                        onTap: _toggleMicrophone,
                      ),
                      _CallControl(
                        icon: speakerEnabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                        active: speakerEnabled,
                        onTap: _toggleSpeaker,
                      ),
                      if (isVideo)
                        _CallControl(
                          icon: cameraEnabled ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                          active: cameraEnabled,
                          onTap: _toggleCamera,
                        ),
                      if (isVideo)
                        _CallControl(
                          icon: Icons.cameraswitch_rounded,
                          active: true,
                          onTap: _switchCamera,
                        ),
                      _CallControl(
                        icon: Icons.call_end_rounded,
                        active: false,
                        destructive: true,
                        onTap: _hangUp,
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                top: isVideo ? 184 : 20,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .42),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      _statusText(context),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _statusText(BuildContext context) {
    if (!ready && connectionLabel == 'Connecting') {
      return _ct(context, 'Preparing secure call…', 'جاري تجهيز المكالمة الآمنة…', 'Beveiligde oproep voorbereiden…');
    }
    final translated = switch (connectionLabel) {
      'Connected' => _ct(context, 'Connected', 'متصل', 'Verbonden'),
      'Reconnecting' => _ct(context, 'Reconnecting…', 'إعادة الاتصال…', 'Opnieuw verbinden…'),
      'Connection failed' => _ct(context, 'Connection failed', 'فشل الاتصال', 'Verbinding mislukt'),
      'Could not connect' => _ct(context, 'Could not connect', 'تعذر الاتصال', 'Kon niet verbinden'),
      'Ended' => _ct(context, 'Call ended', 'انتهت المكالمة', 'Oproep beëindigd'),
      _ => _ct(context, 'Calling…', 'جاري الاتصال…', 'Bellen…'),
    };
    if (!turnConfigured) {
      return '$translated • STUN';
    }
    return '$translated • TURN/WebRTC';
  }
}

class _WaitingView extends StatelessWidget {
  const _WaitingView({required this.icon, required this.title, required this.subtitle});

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 58,
              backgroundColor: const Color(0xFF202C33),
              child: Icon(icon, size: 56, color: const Color(0xFF00A884)),
            ),
            const SizedBox(height: 22),
            Text(
              title,
              style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(subtitle, style: const TextStyle(color: Color(0xFFB7C0C5))),
          ],
        ),
      );
}

class _CallControl extends StatelessWidget {
  const _CallControl({
    required this.icon,
    required this.active,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) => Material(
        color: destructive
            ? const Color(0xFFEA4335)
            : active
                ? const Color(0xFF2A3942)
                : const Color(0xFF667781),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 50,
            height: 50,
            child: Icon(icon, color: Colors.white, size: 25),
          ),
        ),
      );
}
