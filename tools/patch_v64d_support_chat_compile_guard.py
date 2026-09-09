from pathlib import Path

for name in [
    'lib/support/support_chat_v6.dart',
    'lib/support/support_agent_thread_v2.dart',
]:
    p = Path(name)
    s = p.read_text(encoding='utf-8')
    s = s.replace(
        'final start = previousCount.clamp(0, rows.length);',
        'final start = previousCount.clamp(0, rows.length).toInt();',
    )
    if 'rows.skip(start)' in s and 'previousCount.clamp(0, rows.length).toInt()' not in s:
        raise SystemExit(f'V64d: realtime index type guard missing in {name}')
    p.write_text(s, encoding='utf-8')

print('Vet AI V64d applied: support chat realtime indexes are strongly typed for Dart')
