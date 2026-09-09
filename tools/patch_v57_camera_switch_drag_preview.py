from pathlib import Path

p = Path('lib/support/support_webrtc_call_page.dart')
s = p.read_text(encoding='utf-8')

# Web needs the explicit kIsWeb branch because flutter_webrtc requires a
# target deviceId for camera switching in browsers.
if "package:flutter/foundation.dart" not in s:
    anchor = "import 'package:flutter/material.dart';\n"
    if anchor not in s:
        raise SystemExit('V57: material import anchor missing')
    s = s.replace(
        anchor,
        "import 'package:flutter/foundation.dart';\n" + anchor,
        1,
    )

# Track which side is requested and let the local preview be dragged freely.
anchor = "  bool turnConfigured = false;\n"
if "Offset previewOffset" not in s:
    if anchor not in s:
        raise SystemExit('V57: turnConfigured field anchor missing')
    s = s.replace(
        anchor,
        anchor + "  bool usingFrontCamera = true;\n  Offset previewOffset = const Offset(18, 18);\n",
        1,
    )

# Camera mute must always operate on the stream currently shown by the local
# renderer. On web the video track can be replaced when cameras are switched.
old = """  Future<void> _toggleCamera() async {
    cameraEnabled = !cameraEnabled;
    for (final track in localStream?.getVideoTracks() ?? const <MediaStreamTrack>[]) {
      track.enabled = cameraEnabled;
    }
    if (mounted) setState(() {});
  }
"""
new = """  Future<void> _toggleCamera() async {
    cameraEnabled = !cameraEnabled;
    final stream = localRenderer.srcObject ?? localStream;
    for (final track in stream?.getVideoTracks() ?? const <MediaStreamTrack>[]) {
      track.enabled = cameraEnabled;
    }
    if (mounted) setState(() {});
  }
"""
if old in s:
    s = s.replace(old, new, 1)
elif "final stream = localRenderer.srcObject ?? localStream;" not in s:
    raise SystemExit('V57: camera toggle anchor missing')

# Native can toggle the capture device directly. On Flutter Web/Safari the
# helper explicitly requires a target camera deviceId plus the active stream.
old = """  Future<void> _switchCamera() async {
    final tracks = localStream?.getVideoTracks() ?? const <MediaStreamTrack>[];
    if (tracks.isEmpty) return;
    try {
      await Helper.switchCamera(tracks.first);
    } catch (_) {}
  }
"""
new = """  Future<void> _switchCamera() async {
    final stream = localRenderer.srcObject ?? localStream;
    final tracks = stream?.getVideoTracks() ?? const <MediaStreamTrack>[];
    if (stream == null || tracks.isEmpty) return;

    try {
      if (!kIsWeb) {
        final switched = await Helper.switchCamera(tracks.first);
        if (!switched) throw StateError('Camera switch was not completed.');
        usingFrontCamera = !usingFrontCamera;
      } else {
        final cameras = await Helper.cameras;
        if (cameras.length < 2) {
          throw StateError('No second camera is available.');
        }

        final settings = tracks.first.getSettings();
        final currentDeviceId = '${settings['deviceId'] ?? ''}';
        final wantBack = usingFrontCamera;

        bool labelMatches(MediaDeviceInfo camera) {
          final label = camera.label.toLowerCase();
          if (wantBack) {
            return label.contains('back') ||
                label.contains('rear') ||
                label.contains('environment') ||
                label.contains('achter') ||
                label.contains('rück') ||
                label.contains('arrière') ||
                label.contains('trasera');
          }
          return label.contains('front') ||
              label.contains('user') ||
              label.contains('voor') ||
              label.contains('vorder') ||
              label.contains('avant') ||
              label.contains('frontal');
        }

        MediaDeviceInfo? target;
        for (final camera in cameras) {
          if (camera.deviceId != currentDeviceId && labelMatches(camera)) {
            target = camera;
            break;
          }
        }
        if (target == null) {
          for (final camera in cameras) {
            if (camera.deviceId != currentDeviceId) {
              target = camera;
              break;
            }
          }
        }
        target ??= cameras.last;

        final switched = await Helper.switchCamera(
          tracks.first,
          target.deviceId,
          stream,
        );
        if (!switched) throw StateError('Camera switch was not completed.');
        usingFrontCamera = !usingFrontCamera;
      }

      final refreshed = localRenderer.srcObject;
      if (refreshed != null) {
        for (final track in refreshed.getVideoTracks()) {
          track.enabled = cameraEnabled;
        }
      }
      if (mounted) setState(() {});
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_ct(context, 'Could not switch the camera.', 'تعذر تبديل الكاميرا.', 'Camera wisselen is niet gelukt.')} $error',
          ),
          backgroundColor: VetColors.red,
        ),
      );
    }
  }
"""
if old in s:
    s = s.replace(old, new, 1)
elif "final cameras = await Helper.cameras;" not in s:
    raise SystemExit('V57: camera switch anchor missing')

# Replace the fixed top-corner selfie preview with a WhatsApp-like draggable
# picture-in-picture tile. Dragging is clamped to the visible call area.
old = """              if (isVideo && localRenderer.srcObject != null)
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
"""
new = """              if (isVideo && localRenderer.srcObject != null)
                Positioned(
                  left: previewOffset.dx,
                  top: previewOffset.dy,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (details) {
                      final size = MediaQuery.sizeOf(context);
                      final nextX = (previewOffset.dx + details.delta.dx)
                          .clamp(8.0, size.width - 120.0)
                          .toDouble();
                      final nextY = (previewOffset.dy + details.delta.dy)
                          .clamp(8.0, size.height - 174.0)
                          .toDouble();
                      setState(() => previewOffset = Offset(nextX, nextY));
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        width: 112,
                        height: 158,
                        decoration: BoxDecoration(
                          color: Colors.black,
                          border: Border.all(color: Colors.white24),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: RTCVideoView(
                          localRenderer,
                          mirror: usingFrontCamera,
                          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                        ),
                      ),
                    ),
                  ),
                ),
"""
if old in s:
    s = s.replace(old, new, 1)
elif "setState(() => previewOffset = Offset(nextX, nextY));" not in s:
    raise SystemExit('V57: local preview anchor missing')

p.write_text(s, encoding='utf-8')
print('Vet AI V57 applied: reliable browser rear/front camera switching and draggable local video preview')
