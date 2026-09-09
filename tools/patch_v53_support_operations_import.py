from pathlib import Path

path = Path('lib/support/support_agent_thread_v2.dart')
s = path.read_text(encoding='utf-8')
anchor = "import '../services/vet_backend.dart';\n"
needed = "import '../services/vet_operations.dart';\n"
if needed not in s:
    if anchor not in s:
        raise SystemExit('V53: VetBackend import anchor not found')
    s = s.replace(anchor, anchor + needed, 1)
path.write_text(s, encoding='utf-8')
print('Vet AI V53 applied: support agent operations extension restored')
