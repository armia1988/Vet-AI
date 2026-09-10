from pathlib import Path
import math
import plistlib
import struct
import subprocess
import wave


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    if old not in text:
        raise SystemExit(f'V65: {label} anchor missing')
    return text.replace(old, new, 1)


# ---------------------------------------------------------------------------
# 1) Dart: register a real PushKit VoIP token in addition to normal APNs.
# ---------------------------------------------------------------------------
p = Path('lib/services/alert_notification_service.dart')
s = p.read_text(encoding='utf-8')
if "import 'dart:async';" not in s:
    s = "import 'dart:async';\n" + s

s = replace_once(
    s,
    "  static const MethodChannel _apnsChannel = MethodChannel('vet_ai/apns');\n",
    "  static const MethodChannel _apnsChannel = MethodChannel('vet_ai/apns');\n  static const MethodChannel _voipChannel = MethodChannel('vet_ai/voip');\n",
    'VoIP method channel',
)
s = replace_once(
    s,
    "  String? _adminRemoteToken;\n",
    "  String? _adminRemoteToken;\n  String? _voipRemoteToken;\n",
    'VoIP token field',
)

marker = "  Future<void> registerRemotePushForFarm(String farmId) async {\n"
if 'Future<String?> _fetchVoipTokenWithRetry()' not in s:
    if marker not in s:
        raise SystemExit('V65: farm push registration marker missing')
    helper = r'''  Future<String?> _fetchVoipTokenWithRetry() async {
    if (!_isIOS) return null;
    for (var attempt = 0; attempt < 10; attempt++) {
      try {
        final token = await _voipChannel.invokeMethod<String>('getToken');
        final clean = token?.trim().toLowerCase() ?? '';
        if (clean.length >= 64) return clean;
      } catch (e) {
        debugPrint('Vet AI PushKit token attempt ${attempt + 1} failed: $e');
      }
      await Future<void>.delayed(Duration(milliseconds: 350 + (attempt * 250)));
    }
    return null;
  }

  Future<void> _registerVoipPush({
    required String scope,
    String? farmId,
  }) async {
    if (!_isIOS || Supabase.instance.client.auth.currentUser == null) return;
    try {
      final clean = await _fetchVoipTokenWithRetry();
      if (clean == null || clean.isEmpty) return;
      await Supabase.instance.client.rpc(
        'register_voip_push_device',
        params: {
          'p_device_token': clean,
          'p_environment': 'production',
          'p_farm_id': scope == 'farm' ? farmId : null,
          'p_scope': scope,
        },
      );
      _voipRemoteToken = clean;
      debugPrint('Vet AI PushKit device registered for $scope');
    } catch (e) {
      debugPrint('Vet AI PushKit registration failed: $e');
    }
  }

  Future<void> _disableVoipPush() async {
    if (!_isIOS || Supabase.instance.client.auth.currentUser == null) return;
    try {
      var token = _voipRemoteToken;
      token ??= await _voipChannel.invokeMethod<String>('getToken');
      final clean = token?.trim().toLowerCase() ?? '';
      if (clean.isEmpty) return;
      await Supabase.instance.client.rpc(
        'disable_voip_push_device',
        params: {'p_device_token': clean},
      );
      _voipRemoteToken = null;
    } catch (e) {
      debugPrint('Vet AI PushKit unregister failed: $e');
    }
  }

'''
    s = s.replace(marker, helper + marker, 1)

farm_anchor = """    await initialize();
    try {
      final clean = await _fetchApnsTokenWithRetry();
"""
farm_new = """    await initialize();
    unawaited(_registerVoipPush(scope: 'farm', farmId: farmId));
    try {
      final clean = await _fetchApnsTokenWithRetry();
"""
# first occurrence is farm registration
s = replace_once(s, farm_anchor, farm_new, 'farm PushKit registration')

admin_start = s.find('  Future<void> registerRemotePushForAdmin() async {')
if admin_start < 0:
    raise SystemExit('V65: admin push registration method missing')
admin_tail = s[admin_start:]
if "unawaited(_registerVoipPush(scope: 'admin'));" not in admin_tail.split('  Future<void> unregisterRemotePush()', 1)[0]:
    old = """    await initialize();
    try {
      final clean = await _fetchApnsTokenWithRetry();
"""
    pos = s.find(old, admin_start)
    if pos < 0:
        raise SystemExit('V65: admin PushKit insertion anchor missing')
    s = s[:pos] + s[pos:].replace(
        old,
        """    await initialize();
    unawaited(_registerVoipPush(scope: 'admin'));
    try {
      final clean = await _fetchApnsTokenWithRetry();
""",
        1,
    )

unreg = """  Future<void> unregisterRemotePush() async {
    if (!_isIOS) return;
    try {
"""
unreg_new = """  Future<void> unregisterRemotePush() async {
    if (!_isIOS) return;
    await _disableVoipPush();
    try {
"""
s = replace_once(s, unreg, unreg_new, 'PushKit sign-out cleanup')
p.write_text(s, encoding='utf-8')


# ---------------------------------------------------------------------------
# 2) Dart: initialize CallKit coordinator and root navigator.
# ---------------------------------------------------------------------------
p = Path('lib/main_v2.dart')
s = p.read_text(encoding='utf-8')
if "import 'support/incoming_call_coordinator.dart';" not in s:
    anchor = "import 'services/alert_notification_service.dart';\n"
    if anchor not in s:
        raise SystemExit('V65: main notification import anchor missing')
    s = s.replace(anchor, anchor + "import 'support/incoming_call_coordinator.dart';\n", 1)
if 'VetIncomingCallCoordinator.instance.initialize()' not in s:
    anchor = '  await VetAlertNotificationService.instance.initialize();\n'
    if anchor not in s:
        raise SystemExit('V65: main notification init anchor missing')
    s = s.replace(
        anchor,
        anchor + '  await VetIncomingCallCoordinator.instance.initialize();\n',
        1,
    )
p.write_text(s, encoding='utf-8')

p = Path('lib/v5_app.dart')
s = p.read_text(encoding='utf-8')
if "import 'support/incoming_call_coordinator.dart';" not in s:
    anchor = "import 'support/support_console.dart';\n"
    if anchor not in s:
        raise SystemExit('V65: v5 support import anchor missing')
    s = s.replace(anchor, anchor + "import 'support/incoming_call_coordinator.dart';\n", 1)
if 'navigatorKey: VetIncomingCallCoordinator.navigatorKey,' not in s:
    class_pos = s.find('class _VetAIAppV5State')
    mat_pos = s.find('return MaterialApp(', class_pos)
    if mat_pos < 0:
        raise SystemExit('V65: customer MaterialApp missing')
    insert = mat_pos + len('return MaterialApp(')
    s = s[:insert] + '\n      navigatorKey: VetIncomingCallCoordinator.navigatorKey,' + s[insert:]
if 'VetIncomingCallCoordinator.instance.onAuthReady();' not in s:
    reg = "unawaited(VetAlertNotificationService.instance.registerRemotePushForFarm(farm['id']?.toString() ?? ''));"
    pos = s.find(reg)
    if pos < 0:
        raise SystemExit('V65: V44 farm APNs registration marker missing')
    line_end = s.find('\n', pos)
    s = s[:line_end + 1] + '    VetIncomingCallCoordinator.instance.onAuthReady();\n' + s[line_end + 1:]
p.write_text(s, encoding='utf-8')

p = Path('lib/admin/admin_entry.dart')
s = p.read_text(encoding='utf-8')
if "import '../support/incoming_call_coordinator.dart';" not in s:
    anchor = "import '../services/vet_backend.dart';\n"
    if anchor not in s:
        raise SystemExit('V65: admin import anchor missing')
    s = s.replace(anchor, anchor + "import '../support/incoming_call_coordinator.dart';\n", 1)
admin_class = s.find('class _VetAdminAppState')
if admin_class < 0:
    raise SystemExit('V65: admin app state missing')
if 'VetIncomingCallCoordinator.instance.onAuthReady();' not in s[admin_class:]:
    reg = '    unawaited(VetAlertNotificationService.instance.registerRemotePushForAdmin());\n'
    pos = s.find(reg, admin_class)
    if pos < 0:
        raise SystemExit('V65: admin APNs registration marker missing')
    s = s[:pos] + s[pos:].replace(
        reg,
        reg + '    VetIncomingCallCoordinator.instance.onAuthReady();\n',
        1,
    )
if 'navigatorKey: VetIncomingCallCoordinator.navigatorKey,' not in s[admin_class:]:
    mat = s.find('Widget build(BuildContext context) => MaterialApp(', admin_class)
    if mat < 0:
        raise SystemExit('V65: admin MaterialApp missing')
    insert = mat + len('Widget build(BuildContext context) => MaterialApp(')
    s = s[:insert] + '\n        navigatorKey: VetIncomingCallCoordinator.navigatorKey,' + s[insert:]
p.write_text(s, encoding='utf-8')


# ---------------------------------------------------------------------------
# 3) Web/foreground: audible incoming ring while the chat is already open.
#    Native iOS deliberately skips this to avoid double audio with CallKit.
# ---------------------------------------------------------------------------
p = Path('lib/support/support_chat_sound.dart')
s = p.read_text(encoding='utf-8')
if "import 'package:flutter/foundation.dart';" not in s:
    anchor = "import 'package:flutter/services.dart';\n"
    if anchor not in s:
        raise SystemExit('V65: chat sound services import missing')
    s = s.replace(anchor, "import 'package:flutter/foundation.dart';\n" + anchor, 1)
if 'static final AudioPlayer _callPlayer' not in s:
    anchor = '  static final AudioPlayer _receivePlayer = AudioPlayer();\n'
    if anchor not in s:
        raise SystemExit('V65: receive player field missing')
    s = s.replace(
        anchor,
        anchor + "  static final AudioPlayer _callPlayer = AudioPlayer();\n  static String? _activeCallId;\n  static final Uint8List _incomingCallBytes = _phoneRingWav();\n",
        1,
    )
if 'static Future<void> startIncomingCall' not in s:
    marker = '  static Uint8List _wav({\n'
    if marker not in s:
        raise SystemExit('V65: chat wav helper missing')
    methods = r'''  static Future<void> startIncomingCall(String callId) async {
    if (!kIsWeb || callId.isEmpty || _activeCallId == callId) return;
    _activeCallId = callId;
    try {
      await _callPlayer.stop();
      await _callPlayer.setReleaseMode(ReleaseMode.loop);
      await _callPlayer.play(BytesSource(_incomingCallBytes), volume: .62);
    } catch (_) {}
  }

  static Future<void> stopIncomingCall([String? callId]) async {
    if (!kIsWeb) return;
    if (callId != null && _activeCallId != callId) return;
    _activeCallId = null;
    try {
      await _callPlayer.stop();
    } catch (_) {}
  }

  static Uint8List _phoneRingWav() {
    const sampleRate = 22050;
    const durationMs = 3200;
    const bytesPerSample = 2;
    final sampleCount = (sampleRate * durationMs / 1000).round();
    final dataLength = sampleCount * bytesPerSample;
    final data = ByteData(44 + dataLength);
    void ascii(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        data.setUint8(offset + i, value.codeUnitAt(i));
      }
    }
    ascii(0, 'RIFF');
    data.setUint32(4, 36 + dataLength, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, 1, Endian.little);
    data.setUint32(24, sampleRate, Endian.little);
    data.setUint32(28, sampleRate * bytesPerSample, Endian.little);
    data.setUint16(32, bytesPerSample, Endian.little);
    data.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    data.setUint32(40, dataLength, Endian.little);
    for (var i = 0; i < sampleCount; i++) {
      final t = i / sampleRate;
      final cycle = t % 3.2;
      final active = cycle < .62 || (cycle > .82 && cycle < 1.44);
      final edge = active ? math.min(1.0, (cycle % .82) / .018) : 0.0;
      final waveValue = active
          ? (math.sin(2 * math.pi * 438 * t) * .66 +
              math.sin(2 * math.pi * 492 * t) * .34) * edge
          : 0.0;
      final sample = (waveValue * 7600).round().clamp(-32767, 32767).toInt();
      data.setInt16(44 + i * 2, sample, Endian.little);
    }
    return data.buffer.asUint8List();
  }

'''
    s = s.replace(marker, methods + marker, 1)
p.write_text(s, encoding='utf-8')

# Customer incoming call strip.
p = Path('lib/support/support_call_bar.dart')
s = p.read_text(encoding='utf-8')
if "import 'dart:async';" not in s:
    s = "import 'dart:async';\n\n" + s
if "import 'support_chat_sound.dart';" not in s:
    anchor = "import 'support_call_service.dart';\n"
    if anchor not in s:
        raise SystemExit('V65: call bar service import missing')
    s = s.replace(anchor, anchor + "import 'support_chat_sound.dart';\n", 1)
old = """          if (active.isEmpty) return const SizedBox.shrink();
          final call = active.first;
          final incoming = '${call['caller_role']}' != role;
"""
new = """          if (active.isEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              unawaited(VetSupportChatSound.stopIncomingCall());
            });
            return const SizedBox.shrink();
          }
          final call = active.first;
          final incoming = '${call['caller_role']}' != role;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (incoming) {
              unawaited(VetSupportChatSound.startIncomingCall('${call['id']}'));
            } else {
              unawaited(VetSupportChatSound.stopIncomingCall());
            }
          });
"""
s = replace_once(s, old, new, 'customer incoming ring hook')
# Stop the web tone before answer/decline/end.
s = s.replace(
    "onPressed: () => VetSupportCallService.instance.end(call['id'].toString()),",
    "onPressed: () { unawaited(VetSupportChatSound.stopIncomingCall()); VetSupportCallService.instance.end(call['id'].toString()); },",
)
s = s.replace(
    "onPressed: () => VetSupportCallService.instance.decline(call['id'].toString()),",
    "onPressed: () { unawaited(VetSupportChatSound.stopIncomingCall()); VetSupportCallService.instance.decline(call['id'].toString()); },",
)
answer_anchor = """                onPressed: () async {
                  await VetSupportCallService.instance.accept(call['id'].toString());
"""
answer_new = """                onPressed: () async {
                  await VetSupportChatSound.stopIncomingCall();
                  await VetSupportCallService.instance.accept(call['id'].toString());
"""
s = replace_once(s, answer_anchor, answer_new, 'customer answer stops ring')
p.write_text(s, encoding='utf-8')

# Support-agent incoming strip after V64/V64c.
p = Path('lib/support/support_agent_thread_v2.dart')
s = p.read_text(encoding='utf-8')
old = """              if (active.isEmpty) return const SizedBox.shrink();
              final call = active.first;
              final incoming = call['caller_role'] != 'support';
"""
new = """              if (active.isEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  unawaited(VetSupportChatSound.stopIncomingCall());
                });
                return const SizedBox.shrink();
              }
              final call = active.first;
              final incoming = call['caller_role'] != 'support';
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (incoming) {
                  unawaited(VetSupportChatSound.startIncomingCall('${call['id']}'));
                } else {
                  unawaited(VetSupportChatSound.stopIncomingCall());
                }
              });
"""
s = replace_once(s, old, new, 'support-agent incoming ring hook')
join_anchor = """  Future<void> _join(Map<String, dynamic> call) async {
    try {
      await calls.accept(call['id'].toString());
"""
join_new = """  Future<void> _join(Map<String, dynamic> call) async {
    try {
      await VetSupportChatSound.stopIncomingCall();
      await calls.accept(call['id'].toString());
"""
s = replace_once(s, join_anchor, join_new, 'agent answer stops ring')
s = s.replace(
    "onPressed: () => calls.decline(call['id'].toString()),",
    "onPressed: () { unawaited(VetSupportChatSound.stopIncomingCall()); calls.decline(call['id'].toString()); },",
)
p.write_text(s, encoding='utf-8')


# ---------------------------------------------------------------------------
# 4) Native iOS: PushKit + CallKit. Web builds have no ios/Runner and skip this.
# ---------------------------------------------------------------------------
ios_dir = Path('ios/Runner')
if ios_dir.exists():
    # Original Vet AI phone-like ringtone (not copied from any third-party app).
    wav_path = ios_dir / 'vet_ai_incoming_call.wav'
    caf_path = ios_dir / 'vet_ai_incoming_call.caf'
    rate = 22050
    duration = 3.2
    frames = []
    for i in range(int(rate * duration)):
        t = i / rate
        cycle = t % 3.2
        active = cycle < .62 or (.82 < cycle < 1.44)
        if active:
            envelope = min(1.0, (cycle % .82) / .018)
            value = (math.sin(2 * math.pi * 438 * t) * .66 + math.sin(2 * math.pi * 492 * t) * .34)
            sample = int(max(-32767, min(32767, value * envelope * 7600)))
        else:
            sample = 0
        frames.append(struct.pack('<h', sample))
    with wave.open(str(wav_path), 'wb') as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(rate)
        wf.writeframes(b''.join(frames))
    subprocess.run(['afconvert', '-f', 'caff', '-d', 'ima4', str(wav_path), str(caf_path)], check=True)

    # Background modes needed for real VoIP wake + in-call audio.
    plist_path = ios_dir / 'Info.plist'
    with plist_path.open('rb') as f:
        info = plistlib.load(f)
    modes = list(info.get('UIBackgroundModes', []))
    for mode in ['voip', 'audio', 'remote-notification']:
        if mode not in modes:
            modes.append(mode)
    info['UIBackgroundModes'] = modes
    with plist_path.open('wb') as f:
        plistlib.dump(info, f)

    app_delegate = ios_dir / 'AppDelegate.swift'
    app_delegate.write_text(r'''import AVFoundation
import CallKit
import Flutter
import PushKit
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, PKPushRegistryDelegate, CXProviderDelegate {
  private var vetAiApnsToken: String?
  private var vetAiApnsChannel: FlutterMethodChannel?
  private var vetAiVoipToken: String?
  private var vetAiVoipChannel: FlutterMethodChannel?
  private var voipRegistry: PKPushRegistry?
  private var callProvider: CXProvider?
  private var callMetadata: [UUID: [String: Any]] = [:]
  private var answeredCalls = Set<UUID>()
  private var pendingCallAction: [String: Any]?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    configureCallKit()
    configurePushKit()
    DispatchQueue.main.async {
      UIApplication.shared.registerForRemoteNotifications()
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func configureCallKit() {
    let configuration = CXProviderConfiguration(localizedName: "Vet AI")
    configuration.supportsVideo = true
    configuration.maximumCallsPerCallGroup = 1
    configuration.maximumCallGroups = 1
    configuration.supportedHandleTypes = [.generic]
    configuration.ringtoneSound = "vet_ai_incoming_call.caf"
    let provider = CXProvider(configuration: configuration)
    provider.setDelegate(self, queue: .main)
    callProvider = provider
  }

  private func configurePushKit() {
    let registry = PKPushRegistry(queue: .main)
    registry.delegate = self
    registry.desiredPushTypes = [.voIP]
    voipRegistry = registry
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()

    let apns = FlutterMethodChannel(name: "vet_ai/apns", binaryMessenger: messenger)
    apns.setMethodCallHandler { [weak self] call, result in
      guard call.method == "getToken" else {
        result(FlutterMethodNotImplemented)
        return
      }
      if let token = self?.vetAiApnsToken, !token.isEmpty {
        result(token)
      } else {
        UIApplication.shared.registerForRemoteNotifications()
        result(nil)
      }
    }
    vetAiApnsChannel = apns

    let voip = FlutterMethodChannel(name: "vet_ai/voip", binaryMessenger: messenger)
    voip.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      switch call.method {
      case "getToken":
        result(self.vetAiVoipToken)
      case "getPendingCallAction":
        result(self.pendingCallAction)
      case "clearPendingCallAction":
        self.pendingCallAction = nil
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    vetAiVoipChannel = voip
    if let pending = pendingCallAction {
      voip.invokeMethod("callAction", arguments: pending)
    }
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    vetAiApnsToken = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    NSLog("Vet AI APNs registration failed: %@", error.localizedDescription)
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didUpdate pushCredentials: PKPushCredentials,
    for type: PKPushType
  ) {
    guard type == .voIP else { return }
    vetAiVoipToken = pushCredentials.token.map { String(format: "%02.2hhx", $0) }.joined()
    NSLog("Vet AI PushKit token received (%ld chars)", vetAiVoipToken?.count ?? 0)
  }

  func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
    if type == .voIP { vetAiVoipToken = nil }
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didReceiveIncomingPushWith payload: PKPushPayload,
    for type: PKPushType,
    completion: @escaping () -> Void
  ) {
    guard type == .voIP else { completion(); return }
    guard let meta = payload.dictionaryPayload["vet_ai"] as? [String: Any],
          let callId = meta["call_id"] as? String,
          let uuid = UUID(uuidString: callId) else {
      completion()
      return
    }
    let event = String(describing: meta["event"] ?? "ringing")
    if event != "ringing" {
      callProvider?.reportCall(with: uuid, endedAt: Date(), reason: .remoteEnded)
      callMetadata.removeValue(forKey: uuid)
      answeredCalls.remove(uuid)
      completion()
      return
    }

    callMetadata[uuid] = meta
    let caller = (meta["caller_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    let farm = (meta["farm_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    let displayName = (caller?.isEmpty == false ? caller : nil) ?? (farm?.isEmpty == false ? farm : nil) ?? "Vet AI"
    let update = CXCallUpdate()
    update.remoteHandle = CXHandle(type: .generic, value: displayName)
    update.localizedCallerName = displayName
    update.hasVideo = (meta["call_type"] as? String) == "video"
    update.supportsHolding = false
    update.supportsGrouping = false
    update.supportsUngrouping = false

    callProvider?.reportNewIncomingCall(with: uuid, update: update) { error in
      if let error = error {
        NSLog("Vet AI CallKit report failed: %@", error.localizedDescription)
      }
      completion()
    }
  }

  func providerDidReset(_ provider: CXProvider) {
    callMetadata.removeAll()
    answeredCalls.removeAll()
  }

  func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
    guard let meta = callMetadata[action.callUUID] else {
      action.fail()
      return
    }
    answeredCalls.insert(action.callUUID)
    postCallAction(meta: meta, action: "accept")
    var dart = meta
    dart["action"] = "answer"
    pendingCallAction = dart
    vetAiVoipChannel?.invokeMethod("callAction", arguments: dart)
    action.fulfill()
  }

  func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
    guard let meta = callMetadata[action.callUUID] else {
      action.fulfill()
      return
    }
    let serverAction = answeredCalls.contains(action.callUUID) ? "end" : "decline"
    postCallAction(meta: meta, action: serverAction)
    callMetadata.removeValue(forKey: action.callUUID)
    answeredCalls.remove(action.callUUID)
    action.fulfill()
  }

  func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
    do {
      try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .defaultToSpeaker])
    } catch {
      NSLog("Vet AI CallKit audio configuration failed: %@", error.localizedDescription)
    }
  }

  private func postCallAction(meta: [String: Any], action: String) {
    guard let callId = meta["call_id"] as? String,
          let roomKey = meta["room_key"] as? String,
          let url = URL(string: "https://mzqwjyantyvizwbzetwf.supabase.co/functions/v1/support-call-action") else { return }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = 6
    request.httpBody = try? JSONSerialization.data(withJSONObject: [
      "call_id": callId,
      "room_key": roomKey,
      "action": action,
    ])
    URLSession.shared.dataTask(with: request) { _, response, error in
      if let error = error {
        NSLog("Vet AI CallKit action request failed: %@", error.localizedDescription)
      } else if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
        NSLog("Vet AI CallKit action HTTP %ld", http.statusCode)
      }
    }.resume()
  }
}
''', encoding='utf-8')

    # Add ringtone to Runner resources so CallKit can resolve it by file name.
    probe = subprocess.run(['ruby', '-e', "require 'xcodeproj'"], capture_output=True, text=True)
    if probe.returncode != 0:
        subprocess.run(['gem', 'install', 'xcodeproj', '--no-document'], check=True)
    ruby = r'''
require 'xcodeproj'
project = Xcodeproj::Project.open('ios/Runner.xcodeproj')
target = project.targets.find { |t| t.name == 'Runner' }
raise 'Runner target missing' unless target
runner_group = project.main_group.groups.find { |g| g.display_name == 'Runner' || g.path == 'Runner' }
raise 'Runner group missing' unless runner_group
name = 'vet_ai_incoming_call.caf'
file_ref = project.files.find { |f| f.path == name || f.path == "Runner/#{name}" }
file_ref ||= runner_group.new_file(name)
unless target.resources_build_phase.files_references.include?(file_ref)
  target.resources_build_phase.add_file_reference(file_ref, true)
end
project.save
'''
    subprocess.run(['ruby', '-e', ruby], check=True)

    native = app_delegate.read_text(encoding='utf-8')
    for required in [
        'PKPushRegistryDelegate',
        'CXProviderDelegate',
        'reportNewIncomingCall',
        'vet_ai/voip',
        'vet_ai_incoming_call.caf',
        'support-call-action',
    ]:
        if required not in native:
            raise SystemExit(f'V65 native verification missing: {required}')
    if not caf_path.exists() or caf_path.stat().st_size < 1000:
        raise SystemExit('V65 native verification missing: incoming CallKit ringtone CAF')


# Cross-platform source verification.
checks = {
    'lib/services/alert_notification_service.dart': [
        "MethodChannel('vet_ai/voip')",
        "'register_voip_push_device'",
        "'disable_voip_push_device'",
    ],
    'lib/main_v2.dart': ['VetIncomingCallCoordinator.instance.initialize()'],
    'lib/v5_app.dart': ['VetIncomingCallCoordinator.navigatorKey', 'VetIncomingCallCoordinator.instance.onAuthReady()'],
    'lib/admin/admin_entry.dart': ['VetIncomingCallCoordinator.navigatorKey', 'VetIncomingCallCoordinator.instance.onAuthReady()'],
    'lib/support/support_chat_sound.dart': ['startIncomingCall', '_phoneRingWav'],
    'lib/support/support_call_bar.dart': ['VetSupportChatSound.startIncomingCall'],
    'lib/support/support_agent_thread_v2.dart': ['VetSupportChatSound.startIncomingCall'],
    'lib/support/incoming_call_coordinator.dart': ['getPendingCallAction', 'VetWebRtcCallPage'],
}
for path, markers in checks.items():
    text = Path(path).read_text(encoding='utf-8')
    for marker in markers:
        if marker not in text:
            raise SystemExit(f'V65 verification missing: {path} / {marker}')

print('Vet AI V65 applied: PushKit VoIP token registration, native CallKit incoming calls, phone-like ringtone, and foreground web ring')
