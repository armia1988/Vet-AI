from pathlib import Path

path = Path('lib/support/support_agent_thread_v2.dart')
s = path.read_text(encoding='utf-8')
old_v50 = """    final picked = await FilePicker.platform.pickFiles(withData: true, allowMultiple: false);
    if (picked == null || picked.files.isEmpty) return;
    final f = picked.files.single;
    final bytes = f.bytes;
    if (bytes == null) return;
"""
old_v51 = """    final picked = await FilePicker.pickFile(withData: true);
    if (picked == null || picked.files.isEmpty) return;
    final f = picked.files.single;
    final bytes = f.bytes;
    if (bytes == null) return;
"""
old_bad_read = """    final f = await FilePicker.pickFile();
    if (f == null) return;
    final bytes = await f.readBytes();
"""
new = """    final f = await FilePicker.pickFile();
    if (f == null) return;
    final bytes = await f.readAsBytes();
"""
if old_v50 in s:
    s = s.replace(old_v50, new, 1)
elif old_v51 in s:
    s = s.replace(old_v51, new, 1)
elif old_bad_read in s:
    s = s.replace(old_bad_read, new, 1)
elif new not in s:
    raise SystemExit('V51: FilePicker block anchor not found')
path.write_text(s, encoding='utf-8')
print('Vet AI V51 FilePicker 12 API compatibility fix applied')
