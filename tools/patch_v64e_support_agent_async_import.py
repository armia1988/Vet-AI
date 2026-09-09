from pathlib import Path

p = Path('lib/support/support_agent_thread_v2.dart')
s = p.read_text(encoding='utf-8')

if "import 'dart:async';" not in s:
    s = "import 'dart:async';\n" + s

if "import 'dart:async';" not in s or 'unawaited(' not in s:
    raise SystemExit('V64e: support agent async import verification failed')

p.write_text(s, encoding='utf-8')
print('Vet AI V64e applied: support-agent chat imports dart:async for non-blocking chat sounds/read receipts')
