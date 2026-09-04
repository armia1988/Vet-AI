from pathlib import Path

p = Path('lib/support/support_chat_v6.dart')
s = p.read_text()
old = '''  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'txt', 'csv'],
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      if (mounted) _error(_t(context, 'The selected file could not be read.', 'تعذر قراءة الملف المختار.', 'Het gekozen bestand kon niet worden gelezen.'));
      return;
    }
    await _sendAttachment(bytes, file.name, _mimeFor(file.name));
  }
'''
new = '''  Future<void> _pickFile() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'txt', 'csv'],
    );
    if (file == null) return;
    try {
      final bytes = await file.readAsBytes();
      await _sendAttachment(bytes, file.name, _mimeFor(file.name));
    } catch (_) {
      if (mounted) _error(_t(context, 'The selected file could not be read.', 'تعذر قراءة الملف المختار.', 'Het gekozen bestand kon niet worden gelezen.'));
    }
  }
'''
if old not in s:
    raise SystemExit('file picker block not found')
p.write_text(s.replace(old, new, 1))
print('file_picker v12 patch applied')
