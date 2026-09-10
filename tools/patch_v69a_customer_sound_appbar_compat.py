from pathlib import Path

p = Path('lib/support/support_chat_v6.dart')
s = p.read_text(encoding='utf-8')

# V50 already adds video/voice controls. Later formatter/compatibility patches
# can change their whitespace, so locate the actual actions list structurally
# instead of depending on one exact source formatting.
state_start = s.find('class _V6SupportScreenState')
state_end = s.find('\nclass SupportMessageBubble', state_start)
if state_start < 0 or state_end < 0:
    raise SystemExit('V69a: customer screen bounds missing')
segment = s[state_start:state_end]

if 'VetSupportChatSound.muted' not in segment:
    video_pos = segment.find("_startSupportCall('video')")
    if video_pos < 0:
        raise SystemExit('V69a: customer video call action missing')
    actions_pos = segment.rfind('actions: [', 0, video_pos)
    if actions_pos < 0 or video_pos - actions_pos > 2000:
        raise SystemExit('V69a: customer actions list missing near call buttons')
    line_end = segment.find('\n', actions_pos)
    if line_end < 0:
        raise SystemExit('V69a: customer actions line ending missing')
    insert_at = line_end + 1
    toggle = """          IconButton(
            tooltip: VetSupportChatSound.muted
                ? _t(context, 'Turn chat sound on', 'تشغيل صوت الشات', 'Chatgeluid aan')
                : _t(context, 'Mute chat sound', 'كتم صوت الشات', 'Chatgeluid dempen'),
            onPressed: () async {
              await VetSupportChatSound.setMuted(!VetSupportChatSound.muted);
              if (mounted) setState(() {});
            },
            icon: Icon(VetSupportChatSound.muted ? Icons.volume_off_rounded : Icons.volume_up_rounded),
          ),
"""
    segment = segment[:insert_at] + toggle + segment[insert_at:]
    s = s[:state_start] + segment + s[state_end:]

state_start = s.find('class _V6SupportScreenState')
state_end = s.find('\nclass SupportMessageBubble', state_start)
segment = s[state_start:state_end]
if 'VetSupportChatSound.muted' not in segment:
    raise SystemExit('V69a: sound toggle verification failed')
if "_startSupportCall('video')" not in segment or "_startSupportCall('voice')" not in segment:
    raise SystemExit('V69a: existing customer call controls were not preserved')

p.write_text(s, encoding='utf-8')
print('Vet AI V69a applied: customer sound toggle added without removing voice/video call controls')
