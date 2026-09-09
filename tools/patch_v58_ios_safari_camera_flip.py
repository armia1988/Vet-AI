from pathlib import Path

p = Path('lib/support/support_webrtc_call_page.dart')
s = p.read_text(encoding='utf-8')

# Keep the separately re-acquired browser camera stream alive so Safari does
# not release it, and so we can dispose it cleanly when the call ends.
anchor = "  MediaStream? localStream;\n"
if "MediaStream? switchedCameraStream;" not in s:
    if anchor not in s:
        raise SystemExit('V58: localStream field anchor missing')
    s = s.replace(anchor, anchor + "  MediaStream? switchedCameraStream;\n", 1)

old = r'''  Future<void> _switchCamera() async {
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
'''

new = r'''  Future<void> _switchCamera() async {
    final stream = localRenderer.srcObject ?? localStream;
    final tracks = stream?.getVideoTracks() ?? const <MediaStreamTrack>[];
    if (stream == null || tracks.isEmpty) return;

    try {
      if (!kIsWeb) {
        final switched = await Helper.switchCamera(tracks.first);
        if (!switched) throw StateError('Camera switch was not completed.');
        usingFrontCamera = !usingFrontCamera;
        if (mounted) setState(() {});
        return;
      }

      // iOS Safari frequently reports success from switchCamera() while it
      // continues delivering frames from the same lens. Re-acquire the other
      // physical camera and replace the active WebRTC sender track instead.
      final wantBack = usingFrontCamera;
      final currentTrack = tracks.first;
      final settings = currentTrack.getSettings();
      final currentDeviceId = '${settings['deviceId'] ?? ''}';
      final cameras = await Helper.cameras;

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

      // Mobile Safari is much more reliable when the current lens is released
      // before requesting the second physical camera.
      for (final track in tracks) {
        track.stop();
      }

      Future<MediaStream> acquireReplacement() async {
        if (target != null && target.deviceId.isNotEmpty) {
          try {
            return await navigator.mediaDevices.getUserMedia({
              'audio': false,
              'video': <String, dynamic>{
                'deviceId': <String, dynamic>{'exact': target.deviceId},
                'width': <String, dynamic>{'ideal': 1280},
                'height': <String, dynamic>{'ideal': 720},
              },
            });
          } catch (_) {
            // Fall through to facingMode for browsers that rotate device IDs.
          }
        }
        try {
          return await navigator.mediaDevices.getUserMedia({
            'audio': false,
            'video': <String, dynamic>{
              'facingMode': <String, dynamic>{
                'exact': wantBack ? 'environment' : 'user',
              },
              'width': <String, dynamic>{'ideal': 1280},
              'height': <String, dynamic>{'ideal': 720},
            },
          });
        } catch (_) {
          return navigator.mediaDevices.getUserMedia({
            'audio': false,
            'video': <String, dynamic>{
              'facingMode': wantBack ? 'environment' : 'user',
              'width': <String, dynamic>{'ideal': 1280},
              'height': <String, dynamic>{'ideal': 720},
            },
          });
        }
      }

      final replacement = await acquireReplacement();
      final replacementTracks = replacement.getVideoTracks();
      if (replacementTracks.isEmpty) {
        await replacement.dispose();
        throw StateError('The selected camera returned no video track.');
      }
      final newTrack = replacementTracks.first;
      newTrack.enabled = cameraEnabled;

      final connection = peer;
      if (connection == null) {
        newTrack.stop();
        await replacement.dispose();
        throw StateError('The WebRTC connection is not ready.');
      }

      final senders = await connection.senders;
      RTCRtpSender? videoSender;
      for (final sender in senders) {
        if (sender.track?.kind == 'video') {
          videoSender = sender;
          break;
        }
      }
      if (videoSender == null) {
        newTrack.stop();
        await replacement.dispose();
        throw StateError('The outgoing video sender was not found.');
      }

      await videoSender.replaceTrack(newTrack);

      final previousReplacement = switchedCameraStream;
      switchedCameraStream = replacement;
      localRenderer.srcObject = replacement;
      usingFrontCamera = !usingFrontCamera;

      if (previousReplacement != null && previousReplacement != replacement) {
        for (final track in previousReplacement.getTracks()) {
          if (track.id != newTrack.id) track.stop();
        }
        await previousReplacement.dispose();
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
'''

if old in s:
    s = s.replace(old, new, 1)
elif "iOS Safari frequently reports success from switchCamera()" not in s:
    raise SystemExit('V58: V57 switchCamera block not found')

# Stop/dispose a separately re-acquired Safari camera when leaving the call.
anchor = "    localStream?.dispose();\n"
if "switchedCameraStream?.dispose();" not in s:
    if anchor not in s:
        raise SystemExit('V58: dispose localStream anchor missing')
    cleanup = """    if (switchedCameraStream != null && switchedCameraStream != localStream) {
      for (final track in switchedCameraStream!.getTracks()) {
        track.stop();
      }
      switchedCameraStream!.dispose();
    }
"""
    s = s.replace(anchor, anchor + cleanup, 1)

p.write_text(s, encoding='utf-8')
print('Vet AI V58 applied: Safari camera button now re-acquires the rear/front physical lens and replaces the outgoing WebRTC track')
