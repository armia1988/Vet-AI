from pathlib import Path


def replace_method(text: str, start_sig: str, next_sig: str, replacement: str, label: str) -> str:
    start = text.find(start_sig)
    if start < 0:
        if replacement.strip() in text:
            return text
        raise SystemExit(f'V70: {label} start marker missing')
    end = text.find(next_sig, start)
    if end < 0:
        raise SystemExit(f'V70: {label} end marker missing')
    return text[:start] + replacement + text[end:]


# ---------------------------------------------------------------------------
# 1) Reliable chat sounds on Safari/iOS web.
#
# The previous implementation awaited stop()/setReleaseMode() before play().
# On Safari that moved the actual audio start outside the user's Send gesture,
# so the browser could reject it as autoplay. V70 invokes play() immediately
# inside the gesture and primes BOTH send and receive players together.
# ---------------------------------------------------------------------------
Path('lib/support/support_chat_sound.dart').write_text(r'''import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class VetSupportChatSound {
  VetSupportChatSound._();

  static final AudioPlayer _sendPlayer = AudioPlayer();
  static final AudioPlayer _receivePlayer = AudioPlayer();
  static const _prefKey = 'vet_ai_support_chat_muted';
  static bool _unlocked = false;
  static bool _muted = false;
  static bool _initialized = false;
  static String? _lastReceiveMessageId;
  static DateTime? _lastReceiveAt;

  static bool get muted => _muted;

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _muted = prefs.getBool(_prefKey) ?? false;
    } catch (_) {}
    try { await _sendPlayer.setReleaseMode(ReleaseMode.stop); } catch (_) {}
    try { await _receivePlayer.setReleaseMode(ReleaseMode.stop); } catch (_) {}
  }

  static Future<void> setMuted(bool value) async {
    _muted = value;
    _initialized = true;
    if (value) {
      try { await _sendPlayer.stop(); } catch (_) {}
      try { await _receivePlayer.stop(); } catch (_) {}
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, value);
    } catch (_) {}
  }

  /// Must be called directly from a real tap/click. Both play() invocations
  /// happen before the first await so Safari grants playback to both players.
  static Future<void> unlock() async {
    if (_muted || _unlocked) return;
    _unlocked = true;
    Future<void>? sendPrime;
    Future<void>? receivePrime;
    try {
      sendPrime = _sendPlayer.play(
        AssetSource('audio/vet_ai_chat_send.wav'),
        volume: 0.0,
        position: Duration.zero,
      );
      receivePrime = _receivePlayer.play(
        AssetSource('audio/vet_ai_chat_receive.wav'),
        volume: 0.0,
        position: Duration.zero,
      );
      await Future.wait<void>([sendPrime, receivePrime]);
      try { await _sendPlayer.stop(); } catch (_) {}
      try { await _receivePlayer.stop(); } catch (_) {}
    } catch (_) {
      _unlocked = false;
    }
  }

  /// This method is called from the Send tap. Do not put an await before the
  /// audible play() call: that is the key Safari user-activation requirement.
  static Future<void> playSend() async {
    if (_muted) return;
    _unlocked = true;
    Future<void>? receivePrime;
    try {
      // Prime the receive player silently during this same user gesture too,
      // so a later incoming message can make a sound while the chat is open.
      receivePrime = _receivePlayer.play(
        AssetSource('audio/vet_ai_chat_receive.wav'),
        volume: 0.0,
        position: Duration.zero,
      );
      final sendStart = _sendPlayer.play(
        AssetSource('audio/vet_ai_chat_send.wav'),
        volume: 0.92,
        position: Duration.zero,
      );
      await sendStart;
      try {
        await receivePrime;
        await _receivePlayer.stop();
      } catch (_) {}
    } catch (_) {}
  }

  static Future<void> playReceive() => playReceiveFor('');

  static Future<void> playReceiveFor(String messageId) async {
    if (_muted) return;
    final now = DateTime.now();
    if (messageId.isNotEmpty &&
        _lastReceiveMessageId == messageId &&
        _lastReceiveAt != null &&
        now.difference(_lastReceiveAt!) < const Duration(seconds: 5)) {
      return;
    }
    _lastReceiveMessageId = messageId.isEmpty ? _lastReceiveMessageId : messageId;
    _lastReceiveAt = now;
    try {
      await _receivePlayer.play(
        AssetSource('audio/vet_ai_chat_receive.wav'),
        volume: 0.88,
        position: Duration.zero,
      );
    } catch (_) {}
  }
}
''', encoding='utf-8')


# ---------------------------------------------------------------------------
# 2) Customer chat: text messages send optimistically with NO loading spinner.
#
# The realtime message can already appear before the Supabase Future completes.
# Keeping `sending=true` until that Future returned made the UI look stuck even
# though the message was delivered. Text send now clears immediately, plays the
# cue immediately, and completes the network request in the background. The
# shared `sending` state remains available for actual uploads/voice notes.
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

    // WhatsApp-style optimistic text send: never turn on the global loading
    // state for a plain text message. This keeps the camera/mic/send control
    // immediately usable and prevents a spinner after the message is visible.
    message.clear();
    if (composerFocus.canRequestFocus) composerFocus.requestFocus();

    // Fire at the exact tap moment so Safari does not block the sound.
    await VetSupportChatSound.playSend();

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
    'customer instant text send',
)
p.write_text(s, encoding='utf-8')


# ---------------------------------------------------------------------------
# 3) Admin/company chat: same optimistic text-send behavior. This is the path
# shown in the user's Safari screen recording.
# ---------------------------------------------------------------------------
p = Path('lib/support/support_agent_thread_v2.dart')
s = p.read_text(encoding='utf-8')
agent_send = r'''  Future<void> _send() async {
    final clean = message.text.trim();
    if (clean.isEmpty || sending) return;

    // Plain text must never hold the global upload/loading flag. The realtime
    // row may arrive before the HTTP Future returns, so a spinner here is both
    // misleading and visibly slower than the delivered message.
    message.clear();
    if (composerFocus.canRequestFocus) composerFocus.requestFocus();

    // Audible play() is initiated before the network await for Safari/iPhone.
    await VetSupportChatSound.playSend();

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
    'agent instant text send',
)
p.write_text(s, encoding='utf-8')

for path, markers in {
    'lib/support/support_chat_sound.dart': [
        "volume: 0.92",
        "volume: 0.88",
        "position: Duration.zero",
    ],
    'lib/support/support_chat_v6.dart': [
        'await VetSupportChatSound.playSend();',
        'await VetBackend.instance.sendSupportMessage(threadId!, text);',
    ],
    'lib/support/support_agent_thread_v2.dart': [
        'await VetSupportChatSound.playSend();',
        'await backend.sendSupportAgentMessage(threadId, clean);',
    ],
}.items():
    text = Path(path).read_text(encoding='utf-8')
    for marker in markers:
        if marker not in text:
            raise SystemExit(f'V70 verification missing: {path} / {marker}')

# Verify plain-text methods no longer activate the shared loading state.
customer = Path('lib/support/support_chat_v6.dart').read_text(encoding='utf-8')
cs = customer.find('  Future<void> _sendText() async {')
ce = customer.find('  Future<bool> _confirmAccess(', cs)
if 'sending = true' in customer[cs:ce] or 'setState(() => sending = true)' in customer[cs:ce]:
    raise SystemExit('V70: customer text send still activates loading state')

agent = Path('lib/support/support_agent_thread_v2.dart').read_text(encoding='utf-8')
as_ = agent.find('  Future<void> _send() async {')
ae = agent.find('  Future<void> _showAttachmentMenu() async {', as_)
if 'sending = true' in agent[as_:ae] or 'setState(() => sending = true)' in agent[as_:ae]:
    raise SystemExit('V70: agent text send still activates loading state')

print('Vet AI V70 applied: instant text send without spinner + Safari-safe send/receive chat sounds')
