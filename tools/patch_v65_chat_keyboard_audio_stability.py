from pathlib import Path


def replace_method(text: str, start_sig: str, next_sig: str, replacement: str, label: str) -> str:
    start = text.find(start_sig)
    if start < 0:
        if replacement.strip() in text:
            return text
        raise SystemExit(f'V65: {label} start marker missing')
    end = text.find(next_sig, start)
    if end < 0:
        raise SystemExit(f'V65: {label} end marker missing')
    return text[:start] + replacement + text[end:]


# ---------------------------------------------------------------------------
# Customer support chat: keep the iOS keyboard/composer fixed and play the
# outgoing cue at the exact tap moment (before any network await).
# ---------------------------------------------------------------------------
p = Path('lib/support/support_chat_v6.dart')
s = p.read_text(encoding='utf-8')

customer_send = r'''  Future<void> _sendText() async {
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

    // Do not rebuild/dismiss the native iOS text input when Send is tapped.
    // The sound is fired before the first await so Safari treats it as a
    // user-gesture audio action instead of blocking it as autoplay.
    sending = true;
    message.clear();
    if (composerFocus.canRequestFocus) composerFocus.requestFocus();
    unawaited(VetSupportChatSound.playSend());

    try {
      await VetBackend.instance.sendSupportMessage(threadId!, text);
      _scrollToNewest(animated: false);
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
      sending = false;
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && composerFocus.canRequestFocus) composerFocus.requestFocus();
        });
      }
    }
  }

'''
s = replace_method(
    s,
    '  Future<void> _sendText() async {',
    '  Future<bool> _confirmAccess(',
    customer_send,
    'customer send',
)

customer_scroll = r'''  void _scrollToNewest({bool animated = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scroll.hasClients) return;
      final target = scroll.position.maxScrollExtent;
      // A chat composer must feel anchored, not animated around the keyboard.
      // Jumping inside the message list avoids the whole Safari viewport being
      // dragged up/down while the user is typing.
      scroll.jumpTo(target);
    });
  }

'''
s = replace_method(
    s,
    '  void _scrollToNewest({bool animated = true}) {',
    '  Future<void> _startSupportCall(',
    customer_scroll,
    'customer bottom scroll',
) if s.find('  void _scrollToNewest({bool animated = true}) {') < s.find('  Future<void> _startSupportCall(') else s

# V50 places _startSupportCall before _scrollToNewest. Handle that ordering too.
if '  void _scrollToNewest({bool animated = true}) {' in s:
    start = s.find('  void _scrollToNewest({bool animated = true}) {')
    end = s.find('  void _error(String text) {', start)
    if end < 0:
        raise SystemExit('V65: customer scroll end marker missing')
    s = s[:start] + customer_scroll + s[end:]

s = s.replace(
    'ScrollViewKeyboardDismissBehavior.onDrag',
    'ScrollViewKeyboardDismissBehavior.manual',
    1,
)
s = s.replace(
    'scrollPadding: const EdgeInsets.only(bottom: 140),',
    'scrollPadding: EdgeInsets.zero,',
    1,
)

customer_focus_anchor = """                        textInputAction: TextInputAction.newline,
                        onTapOutside: (_) {},
"""
customer_focus_new = """                        textInputAction: TextInputAction.newline,
                        style: const TextStyle(fontSize: 16, height: 1.25),
                        onTap: () => unawaited(VetSupportChatSound.unlock()),
                        onTapOutside: (_) {},
"""
if customer_focus_anchor in s:
    s = s.replace(customer_focus_anchor, customer_focus_new, 1)
elif 'VetSupportChatSound.unlock()' not in s:
    raise SystemExit('V65: customer composer focus anchor missing')

p.write_text(s, encoding='utf-8')


# ---------------------------------------------------------------------------
# Company/support-agent chat: same fixed composer behavior.
# ---------------------------------------------------------------------------
p = Path('lib/support/support_agent_thread_v2.dart')
s = p.read_text(encoding='utf-8')

agent_send = r'''  Future<void> _send() async {
    final clean = message.text.trim();
    if (clean.isEmpty || sending) return;

    // Keep the keyboard and IME alive. Play before awaiting Supabase so the
    // web audio call stays inside the explicit Send tap on iOS Safari.
    sending = true;
    message.clear();
    if (composerFocus.canRequestFocus) composerFocus.requestFocus();
    unawaited(VetSupportChatSound.playSend());

    try {
      await backend.sendSupportAgentMessage(threadId, clean);
      _toBottom(animated: false);
    } catch (_) {
      if (mounted) {
        if (message.text.trim().isEmpty) {
          message.text = clean;
          message.selection = TextSelection.collapsed(offset: clean.length);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_wt(context, 'Message could not be sent.', 'الرسالة مااتبعتتش.', 'Bericht kon niet worden verzonden.')),
            backgroundColor: VetColors.red,
          ),
        );
      }
    } finally {
      sending = false;
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && composerFocus.canRequestFocus) composerFocus.requestFocus();
        });
      }
    }
  }

'''
s = replace_method(
    s,
    '  Future<void> _send() async {',
    '  Future<void> _showAttachmentMenu() async {',
    agent_send,
    'agent send',
)

agent_scroll = r'''  void _toBottom({bool animated = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scroll.hasClients) return;
      scroll.jumpTo(scroll.position.maxScrollExtent);
    });
  }

'''
start = s.find('  void _toBottom({bool animated = true}) {')
if start >= 0:
    end = s.find('  Future<void> _send() async {', start)
    if end < 0:
        raise SystemExit('V65: agent scroll end marker missing')
    s = s[:start] + agent_scroll + s[end:]
elif 'void _toBottom({bool animated = false})' not in s:
    raise SystemExit('V65: agent bottom scroll marker missing')

# There is one message ListView in this screen.
s = s.replace(
    'ScrollViewKeyboardDismissBehavior.onDrag',
    'ScrollViewKeyboardDismissBehavior.manual',
    1,
)

agent_field_anchor = """                        focusNode: composerFocus,
                        minLines: 1,
                        maxLines: 6,
                        textCapitalization: TextCapitalization.sentences,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        onTapOutside: (_) {},
"""
agent_field_new = """                        focusNode: composerFocus,
                        scrollPadding: EdgeInsets.zero,
                        minLines: 1,
                        maxLines: 6,
                        textCapitalization: TextCapitalization.sentences,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        style: const TextStyle(fontSize: 16, height: 1.25),
                        onTap: () => unawaited(VetSupportChatSound.unlock()),
                        onTapOutside: (_) {},
"""
if agent_field_anchor in s:
    s = s.replace(agent_field_anchor, agent_field_new, 1)
elif 'scrollPadding: EdgeInsets.zero' not in s or s.count('VetSupportChatSound.unlock()') < 1:
    raise SystemExit('V65: agent composer field anchor missing')

# Do not let the multiline keyboard's return action unexpectedly send/dismiss.
s = s.replace('                        onSubmitted: (_) => _send(),\n', '', 1)

p.write_text(s, encoding='utf-8')


# ---------------------------------------------------------------------------
# iPhone Safari: prevent the browser page itself from being auto-panned when
# Flutter focuses its hidden text-editing element. Flutter keeps scrolling
# inside the message ListView; the browser page remains fixed like an app.
# ---------------------------------------------------------------------------
index = Path('web/index.html')
if index.exists():
    html = index.read_text(encoding='utf-8')
    css = r'''  <style id="vet-ai-ios-chat-stability">
    html, body {
      margin: 0;
      width: 100%;
      height: 100%;
      overflow: hidden;
      overscroll-behavior: none;
      -webkit-text-size-adjust: 100%;
    }
    @supports (-webkit-touch-callout: none) {
      body {
        position: fixed;
        inset: 0;
      }
      flt-text-editing-host input,
      flt-text-editing-host textarea {
        font-size: 16px !important;
      }
    }
  </style>
'''
    if 'vet-ai-ios-chat-stability' not in html:
        if '</head>' not in html:
            raise SystemExit('V65: web index head marker missing')
        html = html.replace('</head>', css + '</head>', 1)
        index.write_text(html, encoding='utf-8')

for path, markers in {
    'lib/support/support_chat_v6.dart': [
        'VetSupportChatSound.playSend()',
        'VetSupportChatSound.unlock()',
        'scrollPadding: EdgeInsets.zero',
        'ScrollViewKeyboardDismissBehavior.manual',
    ],
    'lib/support/support_agent_thread_v2.dart': [
        'VetSupportChatSound.playSend()',
        'VetSupportChatSound.unlock()',
        'scrollPadding: EdgeInsets.zero',
        'ScrollViewKeyboardDismissBehavior.manual',
    ],
}.items():
    text = Path(path).read_text(encoding='utf-8')
    for marker in markers:
        if marker not in text:
            raise SystemExit(f'V65 verification missing: {path} / {marker}')

print('Vet AI V65 applied: stable iPhone chat viewport, persistent keyboard, instant send cue, and distinct receive cue readiness')
