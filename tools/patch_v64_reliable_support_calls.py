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


# Only a fresh call can ring, and the newest call always wins even if Supabase
# changes row order after realtime updates.
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

# 2) Customer incoming call bar.
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

for path, markers in {
    'lib/support/support_call_service.dart': [".eq('status', 'ringing')"],
    'lib/support/support_call_bar.dart': ['Duration(seconds: 90)', 'bt.compareTo(at)'],
    'lib/support/support_agent_thread_v2.dart': ['Duration(seconds: 90)', 'bt.compareTo(at)'],
}.items():
    text = Path(path).read_text(encoding='utf-8')
    for marker in markers:
        if marker not in text:
            raise SystemExit(f'V64 verification missing: {path} / {marker}')

print('Vet AI V64 applied: latest incoming call always wins and stale ringing calls are ignored/cleared')
