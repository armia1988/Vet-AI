from pathlib import Path

# V69 replaces the send surfaces to keep Safari text focus while tapping Send.
# V55/V59 wrapped and resized those controls, so normalize only those two small
# blocks immediately before V69 performs its final WhatsApp camera/mic layout.

p = Path('lib/support/support_chat_v6.dart')
s = p.read_text(encoding='utf-8')
customer_current = """                    const SizedBox(width: 8),
                    SizedBox.square(
                      dimension: 40,
                      child: IconButton.filled(
                        style: IconButton.styleFrom(backgroundColor: const Color(0xFF00A884), padding: EdgeInsets.zero),
                        onPressed: sending ? null : _sendText,
                        icon: sending
                            ? const SizedBox.square(dimension: 17, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.send_rounded, size: 20, color: Colors.white),
                      ),
                    ),
"""
customer_expected = """                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: sending ? null : _sendText,
                      icon: sending
                          ? const SizedBox.square(dimension: 21, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.send_rounded, size: 29),
                    ),
"""
if customer_expected not in s:
    if customer_current not in s:
        raise SystemExit('V69b: current customer send control missing')
    s = s.replace(customer_current, customer_expected, 1)
p.write_text(s, encoding='utf-8')

p = Path('lib/support/support_agent_thread_v2.dart')
s = p.read_text(encoding='utf-8')
agent_expected = """                  const SizedBox(width: 7),
                  CircleAvatar(
                    radius: 24,
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
if agent_expected not in s:
    send_pos = s.find('onPressed: sending ? null : _send,')
    if send_pos < 0:
        raise SystemExit('V69b: agent send callback missing')
    start = s.rfind('                  const SizedBox(width: 7),', 0, send_pos)
    if start < 0 or send_pos - start > 1000:
        raise SystemExit('V69b: agent send block start missing')
    end_marker = '\n                  ),\n'
    end = s.find(end_marker, send_pos)
    if end < 0 or end - send_pos > 1400:
        raise SystemExit('V69b: agent send block end missing')
    end += len(end_marker)
    s = s[:start] + agent_expected + s[end:]

if customer_expected not in Path('lib/support/support_chat_v6.dart').read_text(encoding='utf-8'):
    raise SystemExit('V69b: customer normalization verification failed')
if agent_expected not in s:
    raise SystemExit('V69b: agent normalization verification failed')

p.write_text(s, encoding='utf-8')
print('Vet AI V69b applied: V59 composer controls normalized for final V69 camera/mic replacement')
