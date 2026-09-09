from pathlib import Path

p = Path('lib/support/support_chat_v6.dart')
s = p.read_text(encoding='utf-8')

if 'void _markCustomerMessagesRead(' not in s:
    marker = '  void _error(String text) {\n'
    if marker not in s:
        raise SystemExit('V65d: customer error marker missing')
    helper = r'''  void _markCustomerMessagesRead(List<Map<String, dynamic>> rows) {
    if (markingIncomingRead || threadId == null) return;
    final hasUnread = rows.any(
      (row) => row['sender_role'] == 'support' && row['read_at'] == null,
    );
    if (!hasUnread) return;
    markingIncomingRead = true;
    unawaited(
      VetSupportRichService.instance.markThreadRead(threadId!).whenComplete(() {
        markingIncomingRead = false;
      }),
    );
  }

'''
    s = s.replace(marker, helper + marker, 1)

if 'void _markCustomerMessagesRead(' not in s:
    raise SystemExit('V65d: customer read helper still missing')

p.write_text(s, encoding='utf-8')
print('Vet AI V65d applied: customer read-receipt helper preserved after stable-scroll patch')
