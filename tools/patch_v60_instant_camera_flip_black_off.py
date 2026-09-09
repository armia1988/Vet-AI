from pathlib import Path


def replace_method(text: str, start_sig: str, next_sig: str, replacement: str, label: str) -> str:
    start = text.find(start_sig)
    if start < 0:
        if replacement.strip() in text:
            return text
        raise SystemExit(f'V60: {label} start marker missing')
    end = text.find(next_sig, start)
    if end < 0:
        raise SystemExit(f'V60: {label} end marker missing')
    return text[:start] + replacement + text[end:]


p = Path('lib/support/support_webrtc_call_page.dart')
s = p.read_text(encoding='utf-8')

# Camera on/off must always operate on the ACTIVE camera track. After an iPhone
# Safari front/rear switch the live track can live in switchedCameraStream rather
# than the original localStream. Toggling only localStream left the new camera
# visually frozen, which is what the user was seeing.
new_toggle = r'''  Future<void> _toggleCamera() async {
    if (!isVideo || cameraSwitching) return;
    final nextEnabled = !cameraEnabled;

    // When turning video off, paint the UI black immediately before touching
    // WebRTC so there is never a frozen last camera frame on screen.
    if (!nextEnabled) {
      cameraEnabled = false;
      if (mounted) setState(() {});
    }

    final activeStream = localRenderer.srcObject ?? switchedCameraStream ?? localStream;
    final touched = <MediaStreamTrack>{};

    for (final track in activeStream?.getVideoTracks() ?? const <MediaStreamTrack>[]) {
      track.enabled = nextEnabled;
      touched.add(track);
    }

    final connection = peer;
    if (connection != null) {
      final senders = await connection.getSenders();
      for (final sender in senders) {
        final track = sender.track;
        if (track != null && track.kind == 'video' && touched.add(track)) {
          track.enabled = nextEnabled;
        }
      }
    }

    // Keep the original stream state in sync too when it is still alive, but it
    // is no longer the source of truth after a physical camera switch.
    for (final track in localStream?.getVideoTracks() ?? const <MediaStreamTrack>[]) {
      if (touched.add(track)) track.enabled = nextEnabled;
    }

    if (nextEnabled) {
      cameraEnabled = true;
      if (mounted) setState(() {});
    }
  }

'''
s = replace_method(
    s,
    '  Future<void> _toggleCamera() async {',
    '  Future<void> _switchCamera() async {',
    new_toggle,
    'camera toggle',
)

# No spinner, no artificial delay, no blank transition. Keep the old preview
# visible while Safari acquires the other physical camera; the moment the fresh
# track is ready it replaces the sender and preview in one UI frame.
new_switch = r'''  Future<void> _switchCamera() async {
    if (!isVideo || cameraSwitching || !cameraEnabled) return;
    final connection = peer;
    final oldPreviewStream = localRenderer.srcObject ?? switchedCameraStream ?? localStream;
    final oldTracks = oldPreviewStream?.getVideoTracks() ?? const <MediaStreamTrack>[];
    if (connection == null || oldPreviewStream == null || oldTracks.isEmpty) return;

    cameraSwitching = true;
    final targetFacing = usingFrontCamera ? 'environment' : 'user';
    MediaStream? fresh;

    try {
      if (!kIsWeb) {
        final switched = await Helper.switchCamera(oldTracks.first);
        if (!switched) throw StateError('Camera switch was not completed.');
        usingFrontCamera = !usingFrontCamera;
        if (mounted) setState(() {});
        return;
      }

      final preferred = <String, dynamic>{
        'audio': false,
        'video': <String, dynamic>{
          'facingMode': <String, dynamic>{'exact': targetFacing},
          'width': <String, dynamic>{'ideal': 1280},
          'height': <String, dynamic>{'ideal': 720},
        },
      };
      final fallback = <String, dynamic>{
        'audio': false,
        'video': <String, dynamic>{
          'facingMode': <String, dynamic>{'ideal': targetFacing},
          'width': <String, dynamic>{'ideal': 1280},
          'height': <String, dynamic>{'ideal': 720},
        },
      };

      try {
        fresh = await navigator.mediaDevices.getUserMedia(preferred);
      } catch (_) {
        fresh = await navigator.mediaDevices.getUserMedia(fallback);
      }

      final freshTracks = fresh.getVideoTracks();
      if (freshTracks.isEmpty) throw StateError('Requested camera is unavailable.');
      final freshTrack = freshTracks.first;
      freshTrack.enabled = true;

      final senders = await connection.getSenders();
      RTCRtpSender? videoSender;
      for (final sender in senders) {
        if (sender.track?.kind == 'video') {
          videoSender = sender;
          break;
        }
      }
      if (videoSender == null) throw StateError('Video sender is unavailable.');

      // Replace remote outgoing video first, then swap the local preview.
      // The old camera remains visible until this exact point: no loading ring.
      await videoSender.replaceTrack(freshTrack);
      localRenderer.srcObject = fresh;
      switchedCameraStream = fresh;
      usingFrontCamera = targetFacing == 'user';

      final oldVideoTrack = oldTracks.first;
      if (!identical(oldVideoTrack, freshTrack)) oldVideoTrack.stop();
      if (oldPreviewStream != localStream && oldPreviewStream != fresh) {
        for (final track in oldPreviewStream.getTracks()) {
          track.stop();
        }
        oldPreviewStream.dispose();
      }

      if (mounted) setState(() {});
    } catch (error) {
      if (fresh != null && fresh != localRenderer.srcObject) {
        for (final track in fresh.getTracks()) {
          track.stop();
        }
        fresh.dispose();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_ct(context, 'Could not switch the camera.', 'تعذر تبديل الكاميرا.', 'Camera wisselen is niet gelukt.')} $error',
          ),
          backgroundColor: VetColors.red,
        ),
      );
    } finally {
      cameraSwitching = false;
    }
  }

'''
s = replace_method(
    s,
    '  Future<void> _switchCamera() async {',
    '  Future<void> _toggleSpeaker() async {',
    new_switch,
    'camera switch',
)

# V59 intentionally showed a loading spinner while Safari switched cameras.
# Remove that overlay completely: the old live frame stays visible until the
# new physical camera is ready.
spinner = '''                            if (cameraSwitching)\n                              Container(\n                                color: const Color(0xCC111B21),\n                                alignment: Alignment.center,\n                                child: const SizedBox.square(\n                                  dimension: 24,\n                                  child: CircularProgressIndicator(\n                                    strokeWidth: 2.4,\n                                    color: Colors.white,\n                                  ),\n                                ),\n                              ),\n'''
if spinner in s:
    s = s.replace(spinner, '', 1)

# Camera-off must be a truly opaque black tile, never the last frozen frame.
s = s.replace('if (!cameraEnabled && !cameraSwitching)', 'if (!cameraEnabled)', 1)
s = s.replace(
    '''                            if (!cameraEnabled)\n                              Container(\n                                color: const Color(0xCC111B21),''',
    '''                            if (!cameraEnabled)\n                              Container(\n                                color: Colors.black,''',
    1,
)

# Use the same compact outlined video-camera symbol as the chat header, while
# keeping the requested red X state on top when camera is off.
s = s.replace(
    '                  Icons.videocam_rounded,\n                  color: enabled ? Colors.white : const Color(0xFFB6BEC4),',
    '                  Icons.videocam_outlined,\n                  color: enabled ? Colors.white : const Color(0xFFB6BEC4),',
    1,
)

required = [
    'final activeStream = localRenderer.srcObject ?? switchedCameraStream ?? localStream;',
    'cameraSwitching = true;',
    'localRenderer.srcObject = fresh;',
    'if (!cameraEnabled)',
    'color: Colors.black,',
    'Icons.videocam_outlined',
]
for marker in required:
    if marker not in s:
        raise SystemExit(f'V60 verification missing: {marker}')

p.write_text(s, encoding='utf-8')
print('Vet AI V60 applied: no camera-switch spinner, instant track swap, active-track camera toggle, opaque black + red X when video is off')
