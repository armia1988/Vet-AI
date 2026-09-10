from pathlib import Path

p = Path('lib/support/support_chat_v6.dart')
s = p.read_text(encoding='utf-8')

# V50 already added video/voice controls to this app bar. Put the V69 sound
# preference before those controls so V69 can keep the existing call buttons.
if 'VetSupportChatSound.muted' not in s:
    anchor = """        actions: [
          IconButton(tooltip: _t(context, 'Video call', 'مكالمة فيديو', 'Videogesprek'), onPressed: threadId == null ? null : () => _startSupportCall('video'), icon: const Icon(Icons.videocam_rounded)),
"""
    replacement = """        actions: [
          IconButton(
            tooltip: VetSupportChatSound.muted
                ? _t(context, 'Turn chat sound on', 'تشغيل صوت الشات', 'Chatgeluid aan')
                : _t(context, 'Mute chat sound', 'كتم صوت الشات', 'Chatgeluid dempen'),
            onPressed: () async {
              await VetSupportChatSound.setMuted(!VetSupportChatSound.muted);
              if (mounted) setState(() {});
            },
            icon: Icon(VetSupportChatSound.muted ? Icons.volume_off_rounded : Icons.volume_up_rounded),
          ),
          IconButton(tooltip: _t(context, 'Video call', 'مكالمة فيديو', 'Videogesprek'), onPressed: threadId == null ? null : () => _startSupportCall('video'), icon: const Icon(Icons.videocam_rounded)),
"""
    if anchor not in s:
        raise SystemExit('V69a: customer call app bar anchor missing')
    s = s.replace(anchor, replacement, 1)

if 'VetSupportChatSound.muted' not in s or "_startSupportCall('video')" not in s:
    raise SystemExit('V69a: customer app bar verification failed')

p.write_text(s, encoding='utf-8')
print('Vet AI V69a applied: customer sound toggle added without removing voice/video call controls')
