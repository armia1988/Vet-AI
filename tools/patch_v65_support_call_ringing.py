from pathlib import Path
import math
import struct
import subprocess
import wave


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    if old not in text:
        raise SystemExit(f'V65: {label} anchor missing')
    return text.replace(old, new, 1)


def add_import(text: str, anchor: str, line: str, label: str) -> str:
    if line in text:
        return text
    if anchor not in text:
        raise SystemExit(f'V65: {label} import anchor missing')
    return text.replace(anchor, anchor + line, 1)


# ---------------------------------------------------------------------------
# 1) A global RLS-scoped support-call stream. This is what lets the receiver
#    ring even when they are not currently sitting inside the exact chat page.
# ---------------------------------------------------------------------------
p = Path('lib/support/support_call_service.dart')
s = p.read_text(encoding='utf-8')
if 'accessibleCallsStream()' not in s:
    anchor = "  Stream<List<Map<String, dynamic>>> signalsStream(String callId) => client\n"
    if anchor not in s:
        raise SystemExit('V65: call service signals stream anchor missing')
    method = """  Stream<List<Map<String, dynamic>>> accessibleCallsStream() => client
      .from('support_calls')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false);

"""
    s = s.replace(anchor, method + anchor, 1)
p.write_text(s, encoding='utf-8')


# ---------------------------------------------------------------------------
# 2) Customer chat: begin outgoing ringback on the actual tap gesture, before
#    waiting for Supabase/WebRTC. Safari otherwise may treat late audio as
#    autoplay and silence it.
# ---------------------------------------------------------------------------
p = Path('lib/support/support_chat_v6.dart')
s = p.read_text(encoding='utf-8')
s = add_import(
    s,
    "import 'support_call_service.dart';\n",
    "import 'support_call_tone.dart';\n",
    'customer call tone',
)
start_sig = '  Future<void> _startSupportCall(String type) async {\n'
if 'VetSupportCallTone.startOutgoing()' not in s[s.find(start_sig):s.find(start_sig) + 900] if start_sig in s else True:
    if start_sig not in s:
        raise SystemExit('V65: customer start-call method missing')
    s = s.replace(
        start_sig,
        start_sig + "    unawaited(VetSupportCallTone.startOutgoing());\n",
        1,
    )
    catch_anchor = """    } catch (e) {
      if (mounted) _error('${_t(context, 'Call could not start.', 'المكالمة ما بدأتش.', 'Oproep kon niet starten.')} $e');
"""
    if catch_anchor not in s:
        raise SystemExit('V65: customer call catch anchor missing')
    s = s.replace(
        catch_anchor,
        """    } catch (e) {
      unawaited(VetSupportCallTone.stopOutgoing());
      if (mounted) _error('${_t(context, 'Call could not start.', 'المكالمة ما بدأتش.', 'Oproep kon niet starten.')} $e');
""",
        1,
    )
p.write_text(s, encoding='utf-8')


# ---------------------------------------------------------------------------
# 3) Company/support-agent chat gets the same immediate outgoing ringback.
# ---------------------------------------------------------------------------
p = Path('lib/support/support_agent_thread_v2.dart')
s = p.read_text(encoding='utf-8')
s = add_import(
    s,
    "import 'support_call_service.dart';\n",
    "import 'support_call_tone.dart';\n",
    'agent call tone',
)
agent_sig = '  Future<void> _startCall(String type) async {\n'
agent_pos = s.find(agent_sig)
if agent_pos < 0:
    raise SystemExit('V65: agent start-call method missing')
if 'VetSupportCallTone.startOutgoing()' not in s[agent_pos:agent_pos + 1000]:
    s = s.replace(
        agent_sig,
        agent_sig + "    unawaited(VetSupportCallTone.startOutgoing());\n",
        1,
    )
    catch_anchor = """    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
"""
    catch_pos = s.find(catch_anchor, agent_pos)
    if catch_pos < 0:
        raise SystemExit('V65: agent call catch anchor missing')
    s = s[:catch_pos] + s[catch_pos:].replace(
        catch_anchor,
        """    } catch (e) {
      unawaited(VetSupportCallTone.stopOutgoing());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
""",
        1,
    )
p.write_text(s, encoding='utf-8')


# ---------------------------------------------------------------------------
# 4) Call page: use the global tone that was already unlocked by the tap, stop
#    it immediately on answer/end, and give unanswered calls a hard timeout.
# ---------------------------------------------------------------------------
p = Path('lib/support/support_webrtc_call_page.dart')
s = p.read_text(encoding='utf-8')
s = add_import(
    s,
    "import 'support_call_service.dart';\n",
    "import 'support_call_tone.dart';\n",
    'call page tone',
)
if 'Timer? ringTimeoutTimer;' not in s:
    anchor = '  StreamSubscription<List<Map<String, dynamic>>>? callSubscription;\n'
    if anchor not in s:
        raise SystemExit('V65: call subscription field anchor missing')
    s = s.replace(anchor, anchor + '  Timer? ringTimeoutTimer;\n', 1)

# V56 introduced these helpers. Keep their names so the rest of the call page
# stays stable, but route playback through the shared tone service.
start = s.find('  Future<void> _startRingback() async {')
stop = s.find('  Future<void> _stopRingback() async {', start)
activate = s.find('  Future<void> _activateRemoteAudio() async {', stop)
if start < 0 or stop < 0 or activate < 0:
    raise SystemExit('V65: V56 ringback helpers missing')
new_helpers = """  Future<void> _startRingback() async {
    await VetSupportCallTone.startOutgoing();
  }

  Future<void> _stopRingback() async {
    ringTimeoutTimer?.cancel();
    ringTimeoutTimer = null;
    await VetSupportCallTone.stopOutgoing();
  }

"""
s = s[:start] + new_helpers + s[activate:]

# Start timeout as soon as the outgoing call page is ready. The tone itself may
# already be playing from the initiating tap.
ready_anchor = """      if (widget.isCaller && callStatus == 'ringing') {
        unawaited(_startRingback());
      }
"""
ready_new = """      if (widget.isCaller && callStatus == 'ringing') {
        unawaited(_startRingback());
        ringTimeoutTimer?.cancel();
        ringTimeoutTimer = Timer(const Duration(seconds: 45), () {
          if (mounted && callStatus == 'ringing' && !ending) {
            unawaited(_hangUp());
          }
        });
      }
"""
s = replace_once(s, ready_anchor, ready_new, 'outgoing call timeout')

# Answer/end/decline must cancel the timeout even if a status update arrives
# before WebRTC media.
accepted_anchor = """        if (status == 'accepted') {
          unawaited(_stopRingback());
        }
"""
if accepted_anchor not in s:
    raise SystemExit('V65: accepted status anchor missing')
s = s.replace(
    accepted_anchor,
    """        if (status == 'accepted') {
          ringTimeoutTimer?.cancel();
          ringTimeoutTimer = null;
          unawaited(_stopRingback());
        }
""",
    1,
)

if 'ringTimeoutTimer?.cancel();\n    unawaited(ringPlayer.dispose());' not in s:
    dispose_anchor = '    unawaited(ringPlayer.dispose());\n'
    if dispose_anchor not in s:
        raise SystemExit('V65: call page dispose ring-player anchor missing')
    s = s.replace(
        dispose_anchor,
        '    ringTimeoutTimer?.cancel();\n' + dispose_anchor,
        1,
    )
p.write_text(s, encoding='utf-8')


# ---------------------------------------------------------------------------
# 5) Customer dashboard: global incoming-call layer, not just the chat screen.
# ---------------------------------------------------------------------------
p = Path('lib/v5_app.dart')
s = p.read_text(encoding='utf-8')
s = add_import(
    s,
    "import 'support/support_console.dart';\n",
    "import 'support/support_incoming_call_overlay.dart';\n",
    'customer incoming call layer',
)
state_start = s.find('class _V5DashboardState extends State<V5Dashboard>')
state_end = s.find('\nclass V5Home extends StatelessWidget', state_start)
if state_start < 0 or state_end < 0:
    raise SystemExit('V65: customer dashboard state bounds missing')
block = s[state_start:state_end]
if "VetIncomingSupportCallLayer(\n      role: 'user'" not in block:
    old = """    return Scaffold(
      body: SafeArea(
        child: IndexedStack(index: index, children: pages),
      ),
      bottomNavigationBar: NavigationBar(
"""
    new = """    return VetIncomingSupportCallLayer(
      role: 'user',
      child: Scaffold(
        body: SafeArea(
          child: IndexedStack(index: index, children: pages),
        ),
        bottomNavigationBar: NavigationBar(
"""
    if old not in block:
        raise SystemExit('V65: customer dashboard Scaffold anchor missing')
    block = block.replace(old, new, 1)
    old_tail = """        ],
      ),
    );
  }

  NavigationDestination _nav(
"""
    new_tail = """          ],
        ),
      ),
    );
  }

  NavigationDestination _nav(
"""
    if old_tail not in block:
        raise SystemExit('V65: customer dashboard Scaffold tail missing')
    block = block.replace(old_tail, new_tail, 1)
    s = s[:state_start] + block + s[state_end:]
p.write_text(s, encoding='utf-8')


# ---------------------------------------------------------------------------
# 6) Admin/support dashboard: register its native APNs token and listen for
#    incoming customer calls globally too.
# ---------------------------------------------------------------------------
p = Path('lib/admin/admin_dashboard.dart')
s = p.read_text(encoding='utf-8')
s = add_import(
    s,
    "import '../services/vet_backend.dart';\n",
    "import '../services/alert_notification_service.dart';\n",
    'admin notification service',
)
s = add_import(
    s,
    "import '../support/support_console.dart';\n",
    "import '../support/support_incoming_call_overlay.dart';\n",
    'admin incoming call layer',
)
init_anchor = """  void initState() {
    super.initState();
"""
if 'registerRemotePushForAdmin()' not in s:
    if init_anchor not in s:
        raise SystemExit('V65: admin initState anchor missing')
    s = s.replace(
        init_anchor,
        init_anchor + '    unawaited(VetAlertNotificationService.instance.registerRemotePushForAdmin());\n',
        1,
    )

# Wrap the compact/mobile scaffold.
mobile_old = """      return Scaffold(
        drawer: Drawer(
"""
mobile_new = """      return VetIncomingSupportCallLayer(
        role: 'support',
        child: Scaffold(
          drawer: Drawer(
"""
if mobile_old in s:
    s = s.replace(mobile_old, mobile_new, 1)
    mobile_tail = """        body: _page(),
      );
    }

    return Scaffold(
"""
    mobile_tail_new = """          body: _page(),
        ),
      );
    }

    return VetIncomingSupportCallLayer(
      role: 'support',
      child: Scaffold(
"""
    if mobile_tail not in s:
        raise SystemExit('V65: admin mobile Scaffold tail missing')
    s = s.replace(mobile_tail, mobile_tail_new, 1)
elif "return VetIncomingSupportCallLayer(\n        role: 'support'" not in s:
    raise SystemExit('V65: admin mobile call-layer anchor missing')

# If the final/wide return was not converted by the previous replacement,
# convert it now.
admin_state = s.find('class _VetAdminDashboardState')
admin_end = s.find('\nclass _AdminDestination', admin_state)
segment = s[admin_state:admin_end]
if segment.count("role: 'support'") < 2:
    wide_old = """    return Scaffold(
      body: Row(
"""
    wide_new = """    return VetIncomingSupportCallLayer(
      role: 'support',
      child: Scaffold(
        body: Row(
"""
    if wide_old not in segment:
        raise SystemExit('V65: admin wide Scaffold anchor missing')
    segment = segment.replace(wide_old, wide_new, 1)
    wide_tail = """        ],
      ),
    );
  }
}
"""
    wide_tail_new = """          ],
        ),
      ),
    );
  }
}
"""
    if wide_tail not in segment:
        raise SystemExit('V65: admin wide Scaffold tail missing')
    segment = segment.replace(wide_tail, wide_tail_new, 1)
    s = s[:admin_state] + segment + s[admin_end:]
p.write_text(s, encoding='utf-8')


# ---------------------------------------------------------------------------
# 7) Native iOS: bundle an original, long phone-like incoming notification
#    ringtone. APNs can then play it when Vet AI is backgrounded or closed.
# ---------------------------------------------------------------------------
ios_runner = Path('ios/Runner')
if ios_runner.exists():
    wav_path = ios_runner / 'vet_ai_incoming_call.wav'
    caf_path = ios_runner / 'vet_ai_incoming_call.caf'
    sample_rate = 22050
    duration_s = 21.0
    samples = int(sample_rate * duration_s)

    with wave.open(str(wav_path), 'wb') as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sample_rate)
        frames = bytearray()
        for i in range(samples):
            t = i / sample_rate
            cycle = t % 3.2
            active = (0.0 <= cycle < 0.52) or (0.65 <= cycle < 1.17)
            if active:
                local = cycle if cycle < 0.52 else cycle - 0.65
                length = 0.52
                edge = min(1.0, local / 0.018, max(0.0, (length - local) / 0.028))
                mod = 0.72 + 0.28 * abs(math.sin(2 * math.pi * 11 * t))
                wave_value = (
                    math.sin(2 * math.pi * 620 * t) * 0.62
                    + math.sin(2 * math.pi * 790 * t) * 0.38
                )
                value = int(32767 * 0.30 * edge * mod * wave_value)
            else:
                value = 0
            frames.extend(struct.pack('<h', max(-32767, min(32767, value))))
        wf.writeframes(frames)

    subprocess.run(
        ['afconvert', '-f', 'caff', '-d', 'ima4', str(wav_path), str(caf_path)],
        check=True,
    )

    probe = subprocess.run(
        ['ruby', '-e', "require 'xcodeproj'"],
        capture_output=True,
        text=True,
    )
    if probe.returncode != 0:
        install = subprocess.run(
            ['gem', 'install', 'xcodeproj', '--no-document'],
            capture_output=True,
            text=True,
        )
        if install.returncode != 0:
            install = subprocess.run(
                ['gem', 'install', 'xcodeproj', '--user-install', '--no-document'],
                capture_output=True,
                text=True,
            )
        if install.returncode != 0:
            raise SystemExit(f'V65: xcodeproj install failed: {install.stderr}')

    ruby = r'''
require 'xcodeproj'
project = Xcodeproj::Project.open('ios/Runner.xcodeproj')
target = project.targets.find { |t| t.name == 'Runner' }
raise 'Runner target missing' unless target
runner_group = project.main_group.groups.find do |g|
  g.display_name == 'Runner' || g.path == 'Runner'
end
raise 'Runner group missing' unless runner_group
name = 'vet_ai_incoming_call.caf'
file_ref = project.files.find do |f|
  f.path == name || f.path == "Runner/#{name}"
end
file_ref ||= runner_group.new_file(name)
unless target.resources_build_phase.files_references.include?(file_ref)
  target.resources_build_phase.add_file_reference(file_ref, true)
end
project.save
project = Xcodeproj::Project.open('ios/Runner.xcodeproj')
target = project.targets.find { |t| t.name == 'Runner' }
resource_names = target.resources_build_phase.files_references.map { |f| f.path.to_s }
raise 'incoming ringtone missing from Runner resources' unless resource_names.any? { |p| p.end_with?(name) }
'''
    result = subprocess.run(['ruby', '-e', ruby], capture_output=True, text=True)
    if result.returncode != 0:
        raise SystemExit(f'V65: Xcode ringtone resource attach failed: {result.stderr}')

    if not caf_path.exists() or caf_path.stat().st_size < 1000:
        raise SystemExit('V65: incoming call CAF was not created correctly')
else:
    print('V65: iOS project not present; native ringtone bundle step skipped for web build')


# Build-time verification for every platform.
checks = {
    'lib/support/support_call_service.dart': ['accessibleCallsStream()'],
    'lib/support/support_chat_v6.dart': ['VetSupportCallTone.startOutgoing()'],
    'lib/support/support_agent_thread_v2.dart': ['VetSupportCallTone.startOutgoing()'],
    'lib/support/support_webrtc_call_page.dart': ['Timer? ringTimeoutTimer;', 'VetSupportCallTone.stopOutgoing()'],
    'lib/v5_app.dart': ["VetIncomingSupportCallLayer(\n      role: 'user'"],
    'lib/admin/admin_dashboard.dart': ['registerRemotePushForAdmin()', "role: 'support'"],
}
for path, markers in checks.items():
    text = Path(path).read_text(encoding='utf-8')
    for marker in markers:
        if marker not in text:
            raise SystemExit(f'V65 verification missing: {path} / {marker}')

print('Vet AI V65 applied: global incoming call UI, immediate ringback, phone-like incoming ringtone, APNs admin registration, and unanswered-call timeout')
