from pathlib import Path
import plistlib

# Customer support chat: route outgoing calls to the internal WebRTC screen.
p = Path('lib/support/support_chat_v6.dart')
s = p.read_text(encoding='utf-8')
if "support_webrtc_call_page.dart" not in s:
    anchor = "import 'support_call_service.dart';\n"
    if anchor not in s:
        raise SystemExit('V54: customer support call service import missing')
    s = s.replace(anchor, anchor + "import 'support_webrtc_call_page.dart';\n", 1)
old = "await VetSupportCallService.instance.openMediaRoom(call);"
new = """if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VetWebRtcCallPage(
            call: call,
            role: 'user',
            isCaller: true,
          ),
        ),
      );"""
if old in s:
    s = s.replace(old, new, 1)
elif "VetWebRtcCallPage(" not in s:
    raise SystemExit('V54: customer outgoing call anchor missing')
p.write_text(s, encoding='utf-8')

# Company support thread: both outgoing and incoming calls stay inside Vet AI.
p = Path('lib/support/support_agent_thread_v2.dart')
s = p.read_text(encoding='utf-8')
if "support_webrtc_call_page.dart" not in s:
    anchor = "import 'support_call_service.dart';\n"
    if anchor not in s:
        raise SystemExit('V54: support agent call service import missing')
    s = s.replace(anchor, anchor + "import 'support_webrtc_call_page.dart';\n", 1)

outgoing_old = "await calls.openMediaRoom(call);"
outgoing_new = """if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VetWebRtcCallPage(
            call: call,
            role: 'support',
            isCaller: true,
          ),
        ),
      );"""
if outgoing_old in s:
    s = s.replace(outgoing_old, outgoing_new, 1)
elif "role: 'support',\n            isCaller: true" not in s:
    raise SystemExit('V54: support outgoing call anchor missing')

incoming_old = """await calls.accept(call['id'].toString());
      await calls.openMediaRoom(call);"""
incoming_new = """await calls.accept(call['id'].toString());
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VetWebRtcCallPage(
            call: call,
            role: 'support',
            isCaller: false,
          ),
        ),
      );"""
if incoming_old in s:
    s = s.replace(incoming_old, incoming_new, 1)
elif "role: 'support',\n            isCaller: false" not in s:
    # A previous replacement can leave one old openMediaRoom occurrence in _join.
    if outgoing_old in s:
        s = s.replace(outgoing_old, """if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VetWebRtcCallPage(
            call: call,
            role: 'support',
            isCaller: false,
          ),
        ),
      );""", 1)
    else:
        raise SystemExit('V54: support incoming call anchor missing')
p.write_text(s, encoding='utf-8')

# Native microphone/camera permissions for generated Android projects.
manifest = Path('android/app/src/main/AndroidManifest.xml')
if manifest.exists():
    text = manifest.read_text(encoding='utf-8')
    permissions = [
        'android.permission.INTERNET',
        'android.permission.ACCESS_NETWORK_STATE',
        'android.permission.CAMERA',
        'android.permission.RECORD_AUDIO',
        'android.permission.MODIFY_AUDIO_SETTINGS',
    ]
    insertion = ''
    for permission in permissions:
        marker = f'android:name="{permission}"'
        if marker not in text:
            insertion += f'    <uses-permission android:name="{permission}" />\n'
    if insertion:
        manifest_tag = '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n'
        if manifest_tag not in text:
            raise SystemExit('V54: Android manifest anchor missing')
        text = text.replace(manifest_tag, manifest_tag + insertion, 1)
        manifest.write_text(text, encoding='utf-8')

# Native iOS permission descriptions when an iOS project is present.
plist_path = Path('ios/Runner/Info.plist')
if plist_path.exists():
    with plist_path.open('rb') as f:
        data = plistlib.load(f)
    data.setdefault(
        'NSCameraUsageDescription',
        'Vet AI uses the camera only when you choose a support video call.',
    )
    data.setdefault(
        'NSMicrophoneUsageDescription',
        'Vet AI uses the microphone only when you choose a support voice or video call.',
    )
    with plist_path.open('wb') as f:
        plistlib.dump(data, f)

print('Vet AI V54 applied: in-app WebRTC voice/video calls with Supabase signalling and TURN-ready ICE config')
