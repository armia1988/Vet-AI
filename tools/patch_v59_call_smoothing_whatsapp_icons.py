from pathlib import Path


def replace_method(text: str, start_sig: str, next_sig: str, replacement: str, label: str) -> str:
    start = text.find(start_sig)
    if start < 0:
        if replacement.strip() in text:
            return text
        raise SystemExit(f'V59: {label} start marker missing')
    end = text.find(next_sig, start)
    if end < 0:
        raise SystemExit(f'V59: {label} end marker missing')
    return text[:start] + replacement + text[end:]


# ---------------------------------------------------------------------------
# 1) WebRTC call page: smooth iPhone/Safari camera switching, no mirror-only
#    fake flip, and explicit red X when video is disabled.
# ---------------------------------------------------------------------------
p = Path('lib/support/support_webrtc_call_page.dart')
s = p.read_text(encoding='utf-8')

field_anchor = "  bool usingFrontCamera = true;\n"
if "bool cameraSwitching = false;" not in s:
    if field_anchor not in s:
        raise SystemExit('V59: usingFrontCamera field missing')
    s = s.replace(field_anchor, field_anchor + "  bool cameraSwitching = false;\n", 1)

new_switch = r'''  Future<void> _switchCamera() async {
    if (!isVideo || cameraSwitching) return;
    final connection = peer;
    final oldPreviewStream = localRenderer.srcObject ?? localStream;
    final oldTracks = oldPreviewStream?.getVideoTracks() ?? const <MediaStreamTrack>[];
    if (connection == null || oldPreviewStream == null || oldTracks.isEmpty) return;

    final targetFacing = usingFrontCamera ? 'environment' : 'user';
    MediaStream? fresh;
    setState(() => cameraSwitching = true);

    try {
      if (!kIsWeb) {
        final switched = await Helper.switchCamera(oldTracks.first);
        if (!switched) throw StateError('Camera switch was not completed.');
        usingFrontCamera = !usingFrontCamera;
        await Future<void>.delayed(const Duration(milliseconds: 90));
      } else {
        // Safari on iPhone can report success from switchCamera while only
        // mirroring the same front-camera track. Re-acquire the requested
        // physical facing mode first, then atomically replace the sender.
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
        freshTrack.enabled = cameraEnabled;

        // Replace the outgoing WebRTC video track before touching the old
        // preview so the remote side never receives a black/frozen gap.
        final senders = await connection.getSenders();
        RTCRtpSender? videoSender;
        for (final sender in senders) {
          if (sender.track?.kind == 'video') {
            videoSender = sender;
            break;
          }
        }
        if (videoSender == null) {
          throw StateError('Video sender is unavailable.');
        }
        await videoSender.replaceTrack(freshTrack);

        // Keep the old frame visible until the replacement stream has had a
        // moment to start. The small switching overlay hides Safari's first
        // unstable frame instead of flashing/mirroring across the preview.
        await Future<void>.delayed(const Duration(milliseconds: 140));
        localRenderer.srcObject = fresh;
        switchedCameraStream = fresh;
        usingFrontCamera = targetFacing == 'user';

        final oldVideoTrack = oldTracks.first;
        if (!identical(oldVideoTrack, freshTrack)) {
          oldVideoTrack.stop();
        }
        if (oldPreviewStream != localStream && oldPreviewStream != fresh) {
          for (final track in oldPreviewStream.getTracks()) {
            track.stop();
          }
          oldPreviewStream.dispose();
        }
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }

      final current = localRenderer.srcObject ?? localStream;
      for (final track in current?.getVideoTracks() ?? const <MediaStreamTrack>[]) {
        track.enabled = cameraEnabled;
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
      if (mounted) setState(() => cameraSwitching = false);
    }
  }

'''
s = replace_method(s, '  Future<void> _switchCamera() async {', '  Future<void> _toggleSpeaker() async {', new_switch, 'camera switch')

# Local preview: keep the preview tile draggable, but hide Safari's transient
# frame during physical-camera change and show a red X when video is muted.
old_preview = """                        child: RTCVideoView(\n                          localRenderer,\n                          mirror: usingFrontCamera,\n                          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,\n                        ),\n"""
new_preview = """                        child: Stack(\n                          fit: StackFit.expand,\n                          children: [\n                            RTCVideoView(\n                              localRenderer,\n                              mirror: usingFrontCamera,\n                              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,\n                            ),\n                            if (cameraSwitching)\n                              Container(\n                                color: const Color(0xCC111B21),\n                                alignment: Alignment.center,\n                                child: const SizedBox.square(\n                                  dimension: 24,\n                                  child: CircularProgressIndicator(\n                                    strokeWidth: 2.4,\n                                    color: Colors.white,\n                                  ),\n                                ),\n                              ),\n                            if (!cameraEnabled && !cameraSwitching)\n                              Container(\n                                color: const Color(0xCC111B21),\n                                alignment: Alignment.center,\n                                child: Container(\n                                  width: 34,\n                                  height: 34,\n                                  decoration: const BoxDecoration(\n                                    color: Color(0xFFEA4335),\n                                    shape: BoxShape.circle,\n                                  ),\n                                  child: const Icon(Icons.close_rounded, color: Colors.white, size: 25),\n                                ),\n                              ),\n                          ],\n                        ),\n"""
if old_preview in s:
    s = s.replace(old_preview, new_preview, 1)
elif 'if (!cameraEnabled && !cameraSwitching)' not in s:
    raise SystemExit('V59: local preview marker missing')

# Dedicated video on/off control: normal camera glyph when live, red X badge
# when disabled. This matches the requested visual state and avoids a giant
# crossed-camera glyph.
old_camera_control = """                      if (isVideo)\n                        _CallControl(\n                          icon: cameraEnabled ? Icons.videocam_rounded : Icons.videocam_off_rounded,\n                          active: cameraEnabled,\n                          onTap: _toggleCamera,\n                        ),\n"""
new_camera_control = """                      if (isVideo)\n                        _VideoToggleControl(\n                          enabled: cameraEnabled,\n                          onTap: _toggleCamera,\n                        ),\n"""
if old_camera_control in s:
    s = s.replace(old_camera_control, new_camera_control, 1)
elif '_VideoToggleControl(' not in s:
    raise SystemExit('V59: video toggle control marker missing')

# Make in-call controls a little smaller and closer to WhatsApp proportions.
s = s.replace('            width: 50,\n            height: 50,\n            child: Icon(icon, color: Colors.white, size: 25),',
              '            width: 44,\n            height: 44,\n            child: Icon(icon, color: Colors.white, size: 22),')

if 'class _VideoToggleControl extends StatelessWidget' not in s:
    append_marker = '\nclass _CallControl extends StatelessWidget {'
    idx = s.find(append_marker)
    if idx < 0:
        raise SystemExit('V59: CallControl class marker missing')
    widget = r'''
class _VideoToggleControl extends StatelessWidget {
  const _VideoToggleControl({required this.enabled, required this.onTap});
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xFF2A3942),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                Icon(
                  Icons.videocam_rounded,
                  color: enabled ? Colors.white : const Color(0xFFB6BEC4),
                  size: 22,
                ),
                if (!enabled)
                  Positioned(
                    right: 3,
                    top: 3,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: const BoxDecoration(
                        color: Color(0xFFEA4335),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close_rounded, size: 12, color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
}

'''
    s = s[:idx] + '\n' + widget + s[idx:]

p.write_text(s, encoding='utf-8')


# ---------------------------------------------------------------------------
# 2) Company/support chat header and composer: compact iOS WhatsApp-like
#    call pill, small back/plus/send controls.
# ---------------------------------------------------------------------------
p = Path('lib/support/support_agent_thread_v2.dart')
s = p.read_text(encoding='utf-8')

# Custom compact back button.
appbar_anchor = """      appBar: AppBar(\n        elevation: 0,\n        scrolledUnderElevation: 0,\n        backgroundColor: _waChrome,\n        foregroundColor: const Color(0xFF111B21),\n        titleSpacing: 0,\n"""
appbar_new = """      appBar: AppBar(\n        elevation: 0,\n        scrolledUnderElevation: 0,\n        backgroundColor: _waChrome,\n        foregroundColor: const Color(0xFF111B21),\n        leadingWidth: 52,\n        leading: Padding(\n          padding: const EdgeInsetsDirectional.only(start: 5),\n          child: IconButton(\n            visualDensity: VisualDensity.compact,\n            padding: EdgeInsets.zero,\n            onPressed: () => Navigator.maybePop(context),\n            icon: const Icon(Icons.chevron_left_rounded, size: 34),\n          ),\n        ),\n        titleSpacing: 0,\n"""
if appbar_anchor in s:
    s = s.replace(appbar_anchor, appbar_new, 1)
elif 'leadingWidth: 52' not in s:
    raise SystemExit('V59: agent appbar anchor missing')

old_actions = """        actions: [\n          IconButton(\n            tooltip: _wt(context, 'Video call', 'مكالمة فيديو', 'Videogesprek'),\n            onPressed: () => _startCall('video'),\n            icon: const Icon(Icons.videocam_outlined),\n          ),\n          IconButton(\n            tooltip: _wt(context, 'Voice call', 'مكالمة صوتية', 'Spraakoproep'),\n            onPressed: () => _startCall('voice'),\n            icon: const Icon(Icons.call_outlined),\n          ),\n"""
new_actions = """        actions: [\n          Container(\n            height: 42,\n            margin: const EdgeInsetsDirectional.only(end: 3),\n            padding: const EdgeInsets.symmetric(horizontal: 2),\n            decoration: BoxDecoration(\n              color: Colors.white.withValues(alpha: .92),\n              borderRadius: BorderRadius.circular(23),\n              border: Border.all(color: const Color(0x14000000)),\n            ),\n            child: Row(mainAxisSize: MainAxisSize.min, children: [\n              _HeaderCallButton(\n                tooltip: _wt(context, 'Video call', 'مكالمة فيديو', 'Videogesprek'),\n                icon: Icons.videocam_outlined,\n                onTap: () => _startCall('video'),\n              ),\n              _HeaderCallButton(\n                tooltip: _wt(context, 'Voice call', 'مكالمة صوتية', 'Spraakoproep'),\n                icon: Icons.call_outlined,\n                onTap: () => _startCall('voice'),\n              ),\n            ]),\n          ),\n"""
if old_actions in s:
    s = s.replace(old_actions, new_actions, 1)
elif '_HeaderCallButton(' not in s:
    raise SystemExit('V59: agent call actions marker missing')

s = s.replace("icon: const Icon(Icons.add_rounded, size: 28),", "icon: const Icon(Icons.add_rounded, size: 24),", 1)
s = s.replace("""                  CircleAvatar(\n                    radius: 24,\n                    backgroundColor: _waGreen,\n                    child: IconButton(\n""", """                  CircleAvatar(\n                    radius: 20,\n                    backgroundColor: _waGreen,\n                    child: IconButton(\n                      padding: EdgeInsets.zero,\n""", 1)
s = s.replace("""                          : const Icon(\n                              Icons.send_rounded,\n                              color: Colors.white,\n                            ),\n""", """                          : const Icon(\n                              Icons.send_rounded,\n                              color: Colors.white,\n                              size: 20,\n                            ),\n""", 1)

if 'class _HeaderCallButton extends StatelessWidget' not in s:
    marker = '\nclass _DayChip extends StatelessWidget {'
    idx = s.find(marker)
    if idx < 0:
        raise SystemExit('V59: agent DayChip marker missing')
    header_widget = r'''
class _HeaderCallButton extends StatelessWidget {
  const _HeaderCallButton({required this.tooltip, required this.icon, required this.onTap});
  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: InkResponse(
          radius: 21,
          onTap: onTap,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(icon, size: 23, color: const Color(0xFF111B21)),
          ),
        ),
      );
}

'''
    s = s[:idx] + '\n' + header_widget + s[idx:]

p.write_text(s, encoding='utf-8')


# ---------------------------------------------------------------------------
# 3) Customer support chat gets the same compact grouped video/voice buttons,
#    plus smaller plus/send controls.
# ---------------------------------------------------------------------------
p = Path('lib/support/support_chat_v6.dart')
s = p.read_text(encoding='utf-8')

old_customer_actions = """        actions: [\n          IconButton(tooltip: _t(context, 'Video call', 'مكالمة فيديو', 'Videogesprek'), onPressed: threadId == null ? null : () => _startSupportCall('video'), icon: const Icon(Icons.videocam_rounded)),\n          IconButton(tooltip: _t(context, 'Voice call', 'مكالمة صوتية', 'Spraakoproep'), onPressed: threadId == null ? null : () => _startSupportCall('voice'), icon: const Icon(Icons.call_rounded)),\n        ],\n"""
new_customer_actions = """        actions: [\n          Container(\n            height: 42,\n            margin: const EdgeInsetsDirectional.only(end: 8),\n            padding: const EdgeInsets.symmetric(horizontal: 2),\n            decoration: BoxDecoration(\n              color: Colors.white.withValues(alpha: .92),\n              borderRadius: BorderRadius.circular(23),\n              border: Border.all(color: const Color(0x14000000)),\n            ),\n            child: Row(mainAxisSize: MainAxisSize.min, children: [\n              IconButton(\n                tooltip: _t(context, 'Video call', 'مكالمة فيديو', 'Videogesprek'),\n                visualDensity: VisualDensity.compact,\n                padding: EdgeInsets.zero,\n                constraints: const BoxConstraints.tightFor(width: 42, height: 42),\n                onPressed: threadId == null ? null : () => _startSupportCall('video'),\n                icon: const Icon(Icons.videocam_outlined, size: 23),\n              ),\n              IconButton(\n                tooltip: _t(context, 'Voice call', 'مكالمة صوتية', 'Spraakoproep'),\n                visualDensity: VisualDensity.compact,\n                padding: EdgeInsets.zero,\n                constraints: const BoxConstraints.tightFor(width: 42, height: 42),\n                onPressed: threadId == null ? null : () => _startSupportCall('voice'),\n                icon: const Icon(Icons.call_outlined, size: 23),\n              ),\n            ]),\n          ),\n        ],\n"""
if old_customer_actions in s:
    s = s.replace(old_customer_actions, new_customer_actions, 1)
elif "constraints: const BoxConstraints.tightFor(width: 42, height: 42)" not in s:
    raise SystemExit('V59: customer call actions marker missing')

# V55 already reduced the send button; tighten the plus and send one more step
# to match the user's iOS WhatsApp reference.
s = s.replace("const Icon(Icons.add_rounded, size: 28)", "const Icon(Icons.add_rounded, size: 24)")
s = s.replace("dimension: 43,", "dimension: 40,", 1)
s = s.replace("const Icon(Icons.send_rounded, size: 23, color: Colors.white)", "const Icon(Icons.send_rounded, size: 20, color: Colors.white)", 1)

p.write_text(s, encoding='utf-8')

print('Vet AI V59 applied: smooth physical camera switching, red video-off X, compact WhatsApp-style header/composer controls')
