from pathlib import Path

# Customer support-chat route has its own call bar. Keep the global call tone
# alive there too because that route sits above the dashboard call overlay.
p = Path('lib/support/support_call_bar.dart')
s = p.read_text(encoding='utf-8')
if "import 'dart:async';" not in s:
    s = "import 'dart:async';\n" + s
if "import 'support_call_tone.dart';" not in s:
    anchor = "import 'support_call_service.dart';\n"
    if anchor not in s:
        raise SystemExit('V65b: customer call bar service import missing')
    s = s.replace(anchor, anchor + "import 'support_call_tone.dart';\n", 1)

empty_old = """          if (active.isEmpty) return const SizedBox.shrink();
          final call = active.first;
          final incoming = '${call['caller_role']}' != role;
"""
empty_new = """          if (active.isEmpty) {
            unawaited(VetSupportCallTone.stopIncoming());
            return const SizedBox.shrink();
          }
          final call = active.first;
          final incoming = '${call['caller_role']}' != role;
          if (incoming) {
            unawaited(VetSupportCallTone.startIncoming(call['id'].toString()));
          } else {
            unawaited(VetSupportCallTone.stopIncoming());
          }
"""
if empty_new not in s:
    if empty_old not in s:
        raise SystemExit('V65b: customer call bar ringing anchor missing')
    s = s.replace(empty_old, empty_new, 1)
p.write_text(s, encoding='utf-8')

# Company agent thread also sits above the admin dashboard route.
p = Path('lib/support/support_agent_thread_v2.dart')
s = p.read_text(encoding='utf-8')
agent_old = """              if (active.isEmpty) return const SizedBox.shrink();
              final call = active.first;
              final incoming = call['caller_role'] != 'support';
"""
agent_new = """              if (active.isEmpty) {
                unawaited(VetSupportCallTone.stopIncoming());
                return const SizedBox.shrink();
              }
              final call = active.first;
              final incoming = call['caller_role'] != 'support';
              if (incoming) {
                unawaited(VetSupportCallTone.startIncoming(call['id'].toString()));
              } else {
                unawaited(VetSupportCallTone.stopIncoming());
              }
"""
if agent_new not in s:
    if agent_old not in s:
        raise SystemExit('V65b: agent call strip ringing anchor missing')
    s = s.replace(agent_old, agent_new, 1)
p.write_text(s, encoding='utf-8')

for path in ['lib/support/support_call_bar.dart', 'lib/support/support_agent_thread_v2.dart']:
    text = Path(path).read_text(encoding='utf-8')
    if 'VetSupportCallTone.startIncoming' not in text or 'VetSupportCallTone.stopIncoming' not in text:
        raise SystemExit(f'V65b verification failed: {path}')

print('Vet AI V65b applied: incoming call ringtone also continues inside customer and company chat routes')
