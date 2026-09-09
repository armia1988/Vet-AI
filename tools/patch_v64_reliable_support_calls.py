from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    if old not in text:
        raise SystemExit(f'V64: {label} anchor missing')
    return text.replace(old, new, 1)


# 1) Never leave an older ringing call active in the same support thread.
p = Path('lib/support/support_call_service.dart')
s = p.read_text(encoding='utf-8')
old = """    final row = await client.from('support_calls').insert({
      'thread_id': threadId,
"""
new = """    // A previous browser/tab can disappear without sending hangup. Clear any
    // older ringing call in this thread before creating the new call, otherwise
    // the receiver can accidentally answer an hours-old call.
    try {
      await client
          .from('support_calls')
          .update({
            'status': 'ended',
            'ended_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('thread_id', threadId)
          .eq('status', 'ringing');
    } catch (_) {
      // Starting the new call is still more important than cleanup.
    }

    final row = await client.from('support_calls').insert({
      'thread_id': threadId,
"""
s = replace_once(s, old, new, 'clear previous ringing calls')
p.write_text(s, encoding='utf-8')


# Helper block used by both call surfaces: only a fresh call can ring, and the
# newest call always wins even if Supabase stream row order changes after a
# realtime update.
fresh_block_old = """          final active = (snapshot.data ?? const <Map<String, dynamic>>[])
              .where((c) => c['status'] == 'ringing')
              .toList();
          if (active.isEmpty) return const SizedBox.shrink();
          final call = active.first;
"""
fresh_block_new = """          final cutoff = DateTime.now().toUtc().subtract(const Duration(seconds: 90));
          final active = (snapshot.data ?? const <Map<String, dynamic>>[])
              .where((c) {
                if (c['status'] != 'ringing') return false;
                final created = DateTime.tryParse('${c['created_at'] ?? ''}')?.toUtc();
                return created != null && created.isAfter(cutoff);
              })
              .toList(growable: true)
            ..sort((a, b) {
              final at = DateTime.tryParse('${a['created_at'] ?? ''}') ?? DateTime.fromMillisecondsSinceEpoch(0);
              final bt = DateTime.tryParse('${b['created_at'] ?? ''}') ?? DateTime.fromMillisecondsSinceEpoch(0);
              return bt.compareTo(at);
            });
          if (active.isEmpty) return const SizedBox.shrink();
          final call = active.first;
"""

# 2) Customer call bar.
p = Path('lib/support/support_call_bar.dart')
s = p.read_text(encoding='utf-8')
s = replace_once(s, fresh_block_old, fresh_block_new, 'customer newest/fresh ringing call')
p.write_text(s, encoding='utf-8')


# 3) Company support thread has its own incoming-call strip; apply the same rule.
p = Path('lib/support/support_agent_thread_v2.dart')
s = p.read_text(encoding='utf-8')
agent_old = """              final active = (snap.data ?? const <Map<String, dynamic>>[])
                  .where((call) => call['status'] == 'ringing')
                  .toList();
              if (active.isEmpty) return const SizedBox.shrink();
              final call = active.first;
"""
agent_new = """              final cutoff = DateTime.now().toUtc().subtract(const Duration(seconds: 90));
              final active = (snap.data ?? const <Map<String, dynamic>>[])
                  .where((call) {
                    if (call['status'] != 'ringing') return false;
                    final created = DateTime.tryParse('${call['created_at'] ?? ''}')?.toUtc();
                    return created != null && created.isAfter(cutoff);
                  })
                  .toList(growable: true)
                ..sort((a, b) {
                  final at = DateTime.tryParse('${a['created_at'] ?? ''}') ?? DateTime.fromMillisecondsSinceEpoch(0);
                  final bt = DateTime.tryParse('${b['created_at'] ?? ''}') ?? DateTime.fromMillisecondsSinceEpoch(0);
                  return bt.compareTo(at);
                });
              if (active.isEmpty) return const SizedBox.shrink();
              final call = active.first;
"""
s = replace_once(s, agent_old, agent_new, 'support newest/fresh ringing call')
p.write_text(s, encoding='utf-8')


# 4) Caller no-answer timeout: a call that nobody answers is ended automatically
# instead of remaining poisonous in the realtime feed forever.
p = Path('lib/support/support_webrtc_call_page.dart')
s = p.read_text(encoding='utf-8')
if 'Timer? noAnswerTimer;' not in s:
    s = replace_once(
        s,
        "  StreamSubscription<List<Map<String, dynamic>>>? callSubscription;\n",
        "  StreamSubscription<List<Map<String, dynamic>>>? callSubscription;\n  Timer? noAnswerTimer;\n",
        'no-answer timer field',
    )

old_listener = """        final status = '${current.first['status']}';
        if ((status == 'ended' || status == 'declined') && mounted && !ending) {
          Navigator.of(context).maybePop();
        }
"""
new_listener = """        final status = '${current.first['status']}';
        if (status == 'accepted') {
          noAnswerTimer?.cancel();
          noAnswerTimer = null;
        }
        if ((status == 'ended' || status == 'declined') && mounted && !ending) {
          noAnswerTimer?.cancel();
          noAnswerTimer = null;
          Navigator.of(context).maybePop();
        }
"""
s = replace_once(s, old_listener, new_listener, 'cancel timeout on accept/end')

offer_anchor = """        await calls.sendSignal(
          callId: callId,
          type: 'offer',
          payload: {'sdp': offer.sdp, 'type': offer.type},
        );
"""
offer_new = offer_anchor + """        noAnswerTimer?.cancel();
        noAnswerTimer = Timer(const Duration(seconds: 45), () async {
          if (ending) return;
          try {
            await calls.end(callId);
          } catch (_) {}
          if (mounted) {
            ending = true;
            Navigator.of(context).maybePop();
          }
        });
"""
s = replace_once(s, offer_anchor, offer_new, 'caller timeout start')

if 'noAnswerTimer?.cancel();\n    signalSubscription?.cancel();' not in s:
    s = replace_once(
        s,
        "  void dispose() {\n    signalSubscription?.cancel();\n",
        "  void dispose() {\n    noAnswerTimer?.cancel();\n    signalSubscription?.cancel();\n",
        'dispose timeout',
    )
p.write_text(s, encoding='utf-8')

for path, markers in {
    'lib/support/support_call_service.dart': [".eq('status', 'ringing')"],
    'lib/support/support_call_bar.dart': ['Duration(seconds: 90)', 'bt.compareTo(at)'],
    'lib/support/support_agent_thread_v2.dart': ['Duration(seconds: 90)', 'bt.compareTo(at)'],
    'lib/support/support_webrtc_call_page.dart': ['Timer? noAnswerTimer;', 'Duration(seconds: 45)'],
}.items():
    text = Path(path).read_text(encoding='utf-8')
    for marker in markers:
        if marker not in text:
            raise SystemExit(f'V64 verification missing: {path} / {marker}')

print('Vet AI V64 applied: latest call always wins, stale ringing calls are ignored/cleared, and unanswered calls auto-end')
