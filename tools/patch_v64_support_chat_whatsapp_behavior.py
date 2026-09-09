from pathlib import Path


def add_import(text: str, anchor: str, line: str, label: str) -> str:
    if line in text:
        return text
    if anchor not in text:
        raise SystemExit(f'V64: {label} import anchor missing')
    return text.replace(anchor, anchor + line, 1)


def replace_method(text: str, start_sig: str, next_sig: str, replacement: str, label: str) -> str:
    start = text.find(start_sig)
    if start < 0:
        if replacement.strip() in text:
            return text
        raise SystemExit(f'V64: {label} start marker missing')
    end = text.find(next_sig, start)
    if end < 0:
        raise SystemExit(f'V64: {label} end marker missing')
    return text[:start] + replacement + text[end:]


# ---------------------------------------------------------------------------
# Customer chat: keep keyboard open, true gray/blue read receipts, visible-chat
# send/receive cues, and a tappable official Vet AI Support avatar.
# ---------------------------------------------------------------------------
p = Path('lib/support/support_chat_v6.dart')
s = p.read_text(encoding='utf-8')

if "import 'dart:async';\n" not in s:
    s = "import 'dart:async';\n" + s
s = add_import(
    s,
    "import 'support_rich_service.dart';\n",
    "import 'support_chat_sound.dart';\n",
    'customer chat sound',
)

field_anchor = "  final scroll = ScrollController();\n"
if "final composerFocus = FocusNode();" not in s:
    if field_anchor not in s:
        raise SystemExit('V64: customer scroll field missing')
    s = s.replace(
        field_anchor,
        field_anchor
        + "  final composerFocus = FocusNode();\n"
        + "  bool markingIncomingRead = false;\n",
        1,
    )

new_send = r'''  Future<void> _sendText() async {
    final text = message.text.trim();
    if (threadId == null || text.isEmpty || sending) return;
    final now = DateTime.now();
    if (lastSentText == text &&
        lastSentAt != null &&
        now.difference(lastSentAt!) < const Duration(seconds: 2)) {
      return;
    }
    lastSentText = text;
    lastSentAt = now;

    // WhatsApp-style composer behavior: sending never dismisses the keyboard.
    message.clear();
    if (composerFocus.canRequestFocus) composerFocus.requestFocus();
    if (mounted) setState(() => sending = true);
    try {
      await VetBackend.instance.sendSupportMessage(threadId!, text);
      unawaited(VetSupportChatSound.playSend());
      _scrollToNewest();
    } catch (_) {
      lastSentText = null;
      lastSentAt = null;
      if (mounted) {
        if (message.text.trim().isEmpty) {
          message.text = text;
          message.selection = TextSelection.collapsed(offset: message.text.length);
        }
        _error(_t(context, 'Message could not be sent.', 'الرسالة مااتبعتتش. جرّب تاني.', 'Bericht kon niet worden verzonden.'));
      }
    } finally {
      if (mounted) {
        setState(() => sending = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && composerFocus.canRequestFocus) {
            composerFocus.requestFocus();
          }
        });
      }
    }
  }

'''
s = replace_method(
    s,
    '  Future<void> _sendText() async {',
    '  Future<bool> _confirmAccess(',
    new_send,
    'customer send',
)

# Insert one guarded read marker helper before the error helper.
if 'void _markCustomerMessagesRead(' not in s:
    marker = '  void _error(String text) {\n'
    if marker not in s:
        raise SystemExit('V64: customer error helper marker missing')
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

# Make the official support avatar itself open a full-screen profile.
old_title = """        title: Row(children: [
          const Icon(Icons.support_agent_rounded, size: 32, color: VetColors.primary),
          const SizedBox(width: 10),
          Text(_t(context, 'Vet AI Support', 'دعم Vet AI', 'Vet AI Support')),
        ]),
"""
new_title = """        title: Row(children: [
          const VetSupportAvatar(radius: 18),
          const SizedBox(width: 7),
          Expanded(child: Text(_t(context, 'Vet AI Support', 'دعم Vet AI', 'Vet AI Support'), overflow: TextOverflow.ellipsis)),
        ]),
"""
if old_title in s:
    s = s.replace(old_title, new_title, 1)
elif 'const VetSupportAvatar(radius: 18)' not in s:
    raise SystemExit('V64: customer app bar title anchor missing')

# Read new incoming messages only while this chat screen is actually open.
old_count = """                    if (rows.length != lastMessageCount) {
                      lastMessageCount = rows.length;
                      _scrollToNewest(animated: !firstMessageScroll);
                      firstMessageScroll = false;
                    }
"""
new_count = """                    if (rows.length != lastMessageCount) {
                      final previousCount = lastMessageCount;
                      if (previousCount >= 0 && rows.length > previousCount) {
                        final start = previousCount.clamp(0, rows.length);
                        final incoming = rows.skip(start).any((row) => row['sender_role'] == 'support');
                        if (incoming) unawaited(VetSupportChatSound.playReceive());
                      }
                      lastMessageCount = rows.length;
                      _scrollToNewest(animated: !firstMessageScroll);
                      firstMessageScroll = false;
                    }
                    _markCustomerMessagesRead(rows);
"""
if old_count in s:
    s = s.replace(old_count, new_count, 1)
elif '_markCustomerMessagesRead(rows);' not in s:
    raise SystemExit('V64: customer message count anchor missing')

# Keep focus when the send control is tapped. onTapOutside is deliberately a
# no-op; scrolling the message list may still dismiss the keyboard naturally.
customer_field = """                      child: TextField(
                        controller: message,
                        scrollPadding: const EdgeInsets.only(bottom: 140),
                        minLines: 1,
                        maxLines: 4,
"""
customer_field_new = """                      child: TextField(
                        controller: message,
                        focusNode: composerFocus,
                        scrollPadding: const EdgeInsets.only(bottom: 140),
                        minLines: 1,
                        maxLines: 4,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        onTapOutside: (_) {},
"""
if customer_field in s:
    s = s.replace(customer_field, customer_field_new, 1)
elif 'focusNode: composerFocus' not in s:
    raise SystemExit('V64: customer composer field anchor missing')

# Wrap the small send control in TextFieldTapRegion so iOS/Safari and Flutter
# treat the send tap as part of the composer instead of an outside tap.
customer_send = """                    SizedBox.square(
                      dimension: 43,
                      child: IconButton.filled(
                        style: IconButton.styleFrom(backgroundColor: const Color(0xFF00A884), padding: EdgeInsets.zero),
                        onPressed: sending ? null : _sendText,
                        icon: sending
                            ? const SizedBox.square(dimension: 17, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.send_rounded, size: 23, color: Colors.white),
                      ),
                    ),
"""
customer_send_new = """                    TextFieldTapRegion(
                      child: SizedBox.square(
                        dimension: 43,
                        child: IconButton.filled(
                          style: IconButton.styleFrom(backgroundColor: const Color(0xFF00A884), padding: EdgeInsets.zero),
                          onPressed: sending ? null : _sendText,
                          icon: sending
                              ? const SizedBox.square(dimension: 17, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.send_rounded, size: 23, color: Colors.white),
                        ),
                      ),
                    ),
"""
if customer_send in s:
    s = s.replace(customer_send, customer_send_new, 1)
elif 'TextFieldTapRegion(' not in s:
    raise SystemExit('V64: customer send button anchor missing')

# Dispose focus node with the other composer resources.
if 'composerFocus.dispose();' not in s:
    dispose_anchor = '    scroll.dispose();\n'
    if dispose_anchor not in s:
        raise SystemExit('V64: customer dispose anchor missing')
    s = s.replace(dispose_anchor, dispose_anchor + '    composerFocus.dispose();\n', 1)

# Blue double-check only after the other party has opened the thread; gray until
# then. Do not fake "read" based merely on successful delivery.
old_tick = """                const Icon(Icons.done_all_rounded, size: 15, color: Color(0xFF53BDEB)),
"""
new_tick = """                Icon(
                  Icons.done_all_rounded,
                  size: 15,
                  color: row['read_at'] == null
                      ? const Color(0xFF8696A0)
                      : const Color(0xFF53BDEB),
                ),
"""
if old_tick in s:
    s = s.replace(old_tick, new_tick, 1)
elif "row['read_at'] == null" not in s:
    raise SystemExit('V64: customer read receipt anchor missing')

p.write_text(s, encoding='utf-8')


# ---------------------------------------------------------------------------
# Support-agent chat: same keyboard, read receipt and sound behavior.
# ---------------------------------------------------------------------------
p = Path('lib/support/support_agent_thread_v2.dart')
s = p.read_text(encoding='utf-8')

s = add_import(
    s,
    "import 'support_rich_service.dart';\n",
    "import 'support_chat_sound.dart';\n",
    'agent chat sound',
)

field_anchor = "  final scroll = ScrollController();\n"
if "final composerFocus = FocusNode();" not in s:
    if field_anchor not in s:
        raise SystemExit('V64: agent scroll field missing')
    s = s.replace(
        field_anchor,
        field_anchor
        + "  final composerFocus = FocusNode();\n"
        + "  bool markingIncomingRead = false;\n",
        1,
    )

new_agent_send = r'''  Future<void> _send() async {
    final clean = message.text.trim();
    if (clean.isEmpty || sending) return;
    if (mounted) setState(() => sending = true);
    message.clear();
    if (composerFocus.canRequestFocus) composerFocus.requestFocus();
    try {
      await backend.sendSupportAgentMessage(threadId, clean);
      unawaited(VetSupportChatSound.playSend());
      _toBottom();
    } catch (_) {
      if (mounted) {
        if (message.text.trim().isEmpty) {
          message.text = clean;
          message.selection = TextSelection.collapsed(offset: clean.length);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _wt(
                context,
                'Message could not be sent.',
                'الرسالة مااتبعتتش.',
                'Bericht kon niet worden verzonden.',
              ),
            ),
            backgroundColor: VetColors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => sending = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && composerFocus.canRequestFocus) {
            composerFocus.requestFocus();
          }
        });
      }
    }
  }

'''
s = replace_method(
    s,
    '  Future<void> _send() async {',
    '  Future<void> _showAttachmentMenu() async {',
    new_agent_send,
    'agent send',
)

if 'void _markAgentMessagesRead(' not in s:
    marker = '  Future<void> _sendFile() async {\n'
    if marker not in s:
        raise SystemExit('V64: agent send-file marker missing')
    helper = r'''  void _markAgentMessagesRead(List<Map<String, dynamic>> rows) {
    if (markingIncomingRead) return;
    final hasUnread = rows.any(
      (row) => row['sender_role'] == 'user' && row['read_at'] == null,
    );
    if (!hasUnread) return;
    markingIncomingRead = true;
    unawaited(
      VetSupportRichService.instance.markThreadRead(threadId).whenComplete(() {
        markingIncomingRead = false;
      }),
    );
  }

'''
    s = s.replace(marker, helper + marker, 1)

old_count = """                  if (rows.length != lastCount) {
                    lastCount = rows.length;
                    _toBottom(animated: !firstScroll);
                    firstScroll = false;
                  }
"""
new_count = """                  if (rows.length != lastCount) {
                    final previousCount = lastCount;
                    if (previousCount >= 0 && rows.length > previousCount) {
                      final start = previousCount.clamp(0, rows.length);
                      final incoming = rows.skip(start).any((row) => row['sender_role'] == 'user');
                      if (incoming) unawaited(VetSupportChatSound.playReceive());
                    }
                    lastCount = rows.length;
                    _toBottom(animated: !firstScroll);
                    firstScroll = false;
                  }
                  _markAgentMessagesRead(rows);
"""
if old_count in s:
    s = s.replace(old_count, new_count, 1)
elif '_markAgentMessagesRead(rows);' not in s:
    raise SystemExit('V64: agent message count anchor missing')

agent_field = """                      child: TextField(
                        controller: message,
                        minLines: 1,
                        maxLines: 6,
                        textCapitalization: TextCapitalization.sentences,
                        textInputAction: TextInputAction.newline,
"""
agent_field_new = """                      child: TextField(
                        controller: message,
                        focusNode: composerFocus,
                        minLines: 1,
                        maxLines: 6,
                        textCapitalization: TextCapitalization.sentences,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        onTapOutside: (_) {},
"""
if agent_field in s:
    s = s.replace(agent_field, agent_field_new, 1)
elif 'focusNode: composerFocus' not in s:
    raise SystemExit('V64: agent composer field anchor missing')

agent_send = """                  CircleAvatar(
                    radius: 21,
                    backgroundColor: _waGreen,
                    child: IconButton(
                      onPressed: sending ? null : _send,
                      icon: sending
                          ? const SizedBox.square(
                              dimension: 19,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.send_rounded,
                              color: Colors.white,
                            ),
                    ),
                  ),
"""
agent_send_new = """                  TextFieldTapRegion(
                    child: CircleAvatar(
                      radius: 21,
                      backgroundColor: _waGreen,
                      child: IconButton(
                        onPressed: sending ? null : _send,
                        icon: sending
                            ? const SizedBox.square(
                                dimension: 19,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(
                                Icons.send_rounded,
                                color: Colors.white,
                              ),
                      ),
                    ),
                  ),
"""
if agent_send in s:
    s = s.replace(agent_send, agent_send_new, 1)
elif 'TextFieldTapRegion(' not in s:
    raise SystemExit('V64: agent send button anchor missing')

if 'composerFocus.dispose();' not in s:
    dispose_anchor = '    scroll.dispose();\n'
    if dispose_anchor not in s:
        raise SystemExit('V64: agent dispose anchor missing')
    s = s.replace(dispose_anchor, dispose_anchor + '    composerFocus.dispose();\n', 1)

old_tick = """                      const Icon(
                        Icons.done_all_rounded,
                        size: 15,
                        color: Color(0xFF53BDEB),
                      ),
"""
new_tick = """                      Icon(
                        Icons.done_all_rounded,
                        size: 15,
                        color: row['read_at'] == null
                            ? const Color(0xFF8696A0)
                            : const Color(0xFF53BDEB),
                      ),
"""
if old_tick in s:
    s = s.replace(old_tick, new_tick, 1)
elif "row['read_at'] == null" not in s:
    raise SystemExit('V64: agent read receipt anchor missing')

p.write_text(s, encoding='utf-8')

for path in [
    'lib/support/support_chat_v6.dart',
    'lib/support/support_agent_thread_v2.dart',
]:
    text = Path(path).read_text(encoding='utf-8')
    for marker in [
        'composerFocus',
        'markThreadRead',
        "row['read_at'] == null",
        'VetSupportChatSound.playSend',
        'VetSupportChatSound.playReceive',
        'TextFieldTapRegion',
    ]:
        if marker not in text:
            raise SystemExit(f'V64 verification missing: {path} / {marker}')

customer = Path('lib/support/support_chat_v6.dart').read_text(encoding='utf-8')
if 'const VetSupportAvatar(radius: 18)' not in customer:
    raise SystemExit('V64 verification missing: tappable Vet AI support avatar')

print('Vet AI V64 applied: rich location payloads, true gray/blue read receipts, persistent keyboard focus, tappable profile avatars, and light chat send/receive cues')
