from pathlib import Path

p = Path('lib/support/support_agent_thread_v2.dart')
s = p.read_text(encoding='utf-8')

expected = """        actions: [
          IconButton(
            tooltip: _wt(context, 'Video call', 'مكالمة فيديو', 'Videogesprek'),
            onPressed: () => _startCall('video'),
            icon: const Icon(Icons.videocam_outlined),
          ),
          IconButton(
            tooltip: _wt(context, 'Voice call', 'مكالمة صوتية', 'Spraakoproep'),
            onPressed: () => _startCall('voice'),
            icon: const Icon(Icons.call_outlined),
          ),
"""

if expected not in s:
    video_pos = s.find("_startCall('video')")
    voice_pos = s.find("_startCall('voice')", video_pos)
    if video_pos < 0 or voice_pos < 0:
        raise SystemExit('V69c: agent call callbacks missing')
    actions_pos = s.rfind('        actions: [', 0, video_pos)
    if actions_pos < 0 or video_pos - actions_pos > 2500:
        raise SystemExit('V69c: agent actions list missing')
    # V59 grouped both call buttons in a single Container. Locate the end of
    # that first child using the next top-level action after the group.
    # The grouped block ends with 10-space '),' followed by either another
    # action or the closing actions list.
    marker = "          ),\n"
    search_from = voice_pos
    block_end = s.find(marker, search_from)
    # There are nested _HeaderCallButton closures. Skip until we pass the Row
    # and the outer Container; the first top-level close after `]),` is ours.
    row_close = s.find('            ]),\n', voice_pos)
    if row_close >= 0:
        block_end = s.find(marker, row_close + len('            ]),\n'))
    if block_end < 0 or block_end - actions_pos > 3000:
        raise SystemExit('V69c: grouped agent call control end missing')
    block_end += len(marker)
    s = s[:actions_pos] + expected + s[block_end:]

if expected not in s:
    raise SystemExit('V69c: agent call action normalization verification failed')

p.write_text(s, encoding='utf-8')
print('Vet AI V69c applied: grouped agent call buttons normalized for V69 sound control')
