from pathlib import Path

p = Path('lib/support/support_incoming_call_overlay.dart')
s = p.read_text(encoding='utf-8')

# V75 introduced a global call/message listener, but accidentally called an
# openMediaRoom method that does not exist on VetSupportCallService. Keep the
# same valid navigation path used by the earlier support-call overlay.
import_anchor = "import 'support_chat_sound.dart';\n"
webrtc_import = "import 'support_webrtc_call_page.dart';\n"
if webrtc_import not in s:
    if import_anchor not in s:
        raise SystemExit('V76: support overlay import anchor missing')
    s = s.replace(import_anchor, import_anchor + webrtc_import, 1)

if 'Future<void> _openMediaRoom(Map<String, dynamic> call)' not in s:
    marker = "  Future<void> _answerById(String callId) async {\n"
    if marker not in s:
        raise SystemExit('V76: answer helper anchor missing')
    helper = r'''  Future<void> _openMediaRoom(Map<String, dynamic> call) async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VetWebRtcCallPage(
          call: {...call, 'status': 'accepted'},
          role: widget.role,
          isCaller: false,
        ),
      ),
    );
  }

'''
    s = s.replace(marker, helper + marker, 1)

s = s.replace('await calls.openMediaRoom(call);', 'await _openMediaRoom(call);')

if 'calls.openMediaRoom(' in s:
    raise SystemExit('V76: invalid service media-room call still present')
for required in [
    "import 'support_webrtc_call_page.dart';",
    'Future<void> _openMediaRoom(Map<String, dynamic> call)',
    'VetWebRtcCallPage(',
    'await _openMediaRoom(call);',
]:
    if required not in s:
        raise SystemExit(f'V76 verification missing: {required}')

p.write_text(s, encoding='utf-8')
print('Vet AI V76 applied: V75 overlay compiles and opens accepted calls through VetWebRtcCallPage')
