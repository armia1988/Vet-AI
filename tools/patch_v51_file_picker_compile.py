from pathlib import Path

path = Path('lib/support/support_agent_thread_v2.dart')
s = path.read_text(encoding='utf-8')
old = "FilePicker.platform.pickFiles(withData: true, allowMultiple: false)"
new = "FilePicker.pickFile(withData: true)"
if old in s:
    s = s.replace(old, new, 1)
elif new not in s:
    raise SystemExit('V51: FilePicker call anchor not found')
path.write_text(s, encoding='utf-8')
print('Vet AI V51 FilePicker API compatibility fix applied')
