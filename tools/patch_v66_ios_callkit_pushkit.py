from pathlib import Path
import plistlib


def add_import(text: str, anchor: str, line: str, label: str) -> str:
    if line in text:
        return text
    if anchor not in text:
        raise SystemExit(f'V66: {label} import anchor missing')
    return text.replace(anchor, anchor + line, 1)


# ---------------------------------------------------------------------------
# 1) Start the Dart CallKit bridge before the UI and keep one root navigator
#    available for an answer action that wakes the app from iOS CallKit.
# ---------------------------------------------------------------------------
p = Path('lib/main_v2.dart')
s = p.read_text(encoding='utf-8')
s = add_import(
    s,
    "import 'services/alert_notification_service.dart';\n",
    "import 'services/callkit_service.dart';\nimport 'support/callkit_coordinator.dart';\n",
    'main CallKit services',
)
old = """  await VetAlertNotificationService.instance.initialize();

  runApp(kIsWeb ? const VetAdminWebRoot() : const VetAIRoot());
"""
new = """  await VetAlertNotificationService.instance.initialize();
  await VetCallKitService.instance.initialize();
  VetCallKitCoordinator.instance.initialize();

  runApp(kIsWeb ? const VetAdminWebRoot() : const VetAIRoot());
"""
if new not in s:
    if old not in s:
        raise SystemExit('V66: main initialization anchor missing')
    s = s.replace(old, new, 1)
p.write_text(s, encoding='utf-8')


# Customer app: navigator + farm PushKit token registration.
p = Path('lib/v5_app.dart')
s = p.read_text(encoding='utf-8')
s = add_import(
    s,
    "import 'services/alert_notification_service.dart';\n",
    "import 'services/callkit_service.dart';\nimport 'support/callkit_coordinator.dart';\n",
    'customer CallKit',
)
app_anchor = """    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Vet AI',
"""
app_new = """    return MaterialApp(
      navigatorKey: vetRootNavigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Vet AI',
"""
if app_new not in s:
    if app_anchor not in s:
        raise SystemExit('V66: customer MaterialApp anchor missing')
    s = s.replace(app_anchor, app_new, 1)
reg = "unawaited(VetAlertNotificationService.instance.registerRemotePushForFarm(farm['id']?.toString() ?? ''));"
if 'VetCallKitService.instance.registerForFarm' not in s:
    if reg not in s:
        raise SystemExit('V66: V44 farm APNs registration anchor missing')
    s = s.replace(
        reg,
        reg + "\n    unawaited(VetCallKitService.instance.registerForFarm(farm['id']?.toString() ?? ''));",
        1,
    )
p.write_text(s, encoding='utf-8')


# Admin app: same root navigator + admin PushKit token registration.
p = Path('lib/admin/admin_entry.dart')
s = p.read_text(encoding='utf-8')
s = add_import(
    s,
    "import '../services/alert_notification_service.dart';\n",
    "import '../services/callkit_service.dart';\nimport '../support/callkit_coordinator.dart';\n",
    'admin CallKit',
)
admin_app = """  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Vet AI Admin',
"""
admin_new = """  Widget build(BuildContext context) => MaterialApp(
        navigatorKey: vetRootNavigatorKey,
        debugShowCheckedModeBanner: false,
        title: 'Vet AI Admin',
"""
if admin_new not in s:
    if admin_app not in s:
        raise SystemExit('V66: admin MaterialApp anchor missing')
    s = s.replace(admin_app, admin_new, 1)
admin_reg = '    unawaited(VetAlertNotificationService.instance.registerRemotePushForAdmin());\n'
if 'VetCallKitService.instance.registerForAdmin()' not in s:
    if admin_reg not in s:
        raise SystemExit('V66: admin APNs registration anchor missing')
    s = s.replace(
        admin_reg,
        admin_reg + '    unawaited(VetCallKitService.instance.registerForAdmin());\n',
        1,
    )
p.write_text(s, encoding='utf-8')


# Disable the dedicated VoIP token on logout as well as the ordinary APNs token.
p = Path('lib/services/vet_backend.dart')
s = p.read_text(encoding='utf-8')
s = add_import(
    s,
    "import 'alert_notification_service.dart';\n",
    "import 'callkit_service.dart';\n",
    'backend CallKit',
)
if 'VetCallKitService.instance.unregister()' not in s:
    anchor = '    await VetAlertNotificationService.instance.unregisterRemotePush();\n'
    if anchor not in s:
        raise SystemExit('V66: V44 logout notification anchor missing')
    s = s.replace(
        anchor,
        '    await VetCallKitService.instance.unregister();\n' + anchor,
        1,
    )
p.write_text(s, encoding='utf-8')


# ---------------------------------------------------------------------------
# 2) Native CallKit owns incoming ringtone on iOS. Do not play the Flutter
#    fallback tone at the same time. Web/other platforms keep the local tone.
# ---------------------------------------------------------------------------
for path_str in [
    'lib/support/support_incoming_call_overlay.dart',
    'lib/support/support_call_bar.dart',
    'lib/support/support_agent_thread_v2.dart',
]:
    p = Path(path_str)
    s = p.read_text(encoding='utf-8')
    if "callkit_service.dart" not in s:
        if path_str.endswith('support_incoming_call_overlay.dart'):
            anchor = "import '../services/vet_backend.dart';\n"
            line = "import '../services/callkit_service.dart';\n"
        elif path_str.endswith('support_call_bar.dart'):
            anchor = "import '../theme/app_theme.dart';\n"
            line = "import '../services/callkit_service.dart';\n"
        else:
            anchor = "import '../services/vet_backend.dart';\n"
            line = "import '../services/callkit_service.dart';\n"
        s = add_import(s, anchor, line, f'{path_str} native ringtone guard')

    if path_str.endswith('support_incoming_call_overlay.dart'):
        old = """      if (nextId != null && mounted) {
        unawaited(VetSupportCallTone.startIncoming(nextId));
      }
"""
        new = """      if (nextId != null && mounted &&
          !VetCallKitService.instance.usesNativeCallKit) {
        unawaited(VetSupportCallTone.startIncoming(nextId));
      }
"""
        if new not in s:
            if old not in s:
                raise SystemExit('V66: global incoming tone anchor missing')
            s = s.replace(old, new, 1)
    else:
        old = "unawaited(VetSupportCallTone.startIncoming(call['id'].toString()));"
        new = """if (!VetCallKitService.instance.usesNativeCallKit) {
              unawaited(VetSupportCallTone.startIncoming(call['id'].toString()));
            }"""
        if new not in s:
            if old not in s:
                raise SystemExit(f'V66: chat ringtone anchor missing: {path_str}')
            s = s.replace(old, new, 1)
    p.write_text(s, encoding='utf-8')


# ---------------------------------------------------------------------------
# 3) iOS PushKit + CallKit. This runs only in native Codemagic builds because
#    GitHub Pages generation does not have ios/Runner.
# ---------------------------------------------------------------------------
app_delegate = Path('ios/Runner/AppDelegate.swift')
if app_delegate.exists():
    app_delegate.write_text(r'''import Flutter
import UIKit
import UserNotifications
import PushKit
import CallKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, PKPushRegistryDelegate, CXProviderDelegate {
  private var vetAiApnsToken: String?
  private var vetAiVoipToken: String?
  private var vetAiApnsChannel: FlutterMethodChannel?
  private var vetAiCallKitChannel: FlutterMethodChannel?
  private var voipRegistry: PKPushRegistry?
  private var callMetadata: [String: [String: Any]] = [:]
  private var pendingCallKitAction: [String: Any]?

  private lazy var callProvider: CXProvider = {
    let configuration = CXProviderConfiguration(localizedName: "Vet AI")
    configuration.supportsVideo = true
    configuration.maximumCallGroups = 1
    configuration.maximumCallsPerCallGroup = 1
    configuration.supportedHandleTypes = [.generic]
    configuration.includesCallsInRecents = true
    // Intentionally leave ringtoneSound unset: CallKit uses the iPhone's normal
    // system incoming-call ringtone and respects mute/Focus/accessibility rules.
    let provider = CXProvider(configuration: configuration)
    provider.setDelegate(self, queue: .main)
    return provider
  }()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    _ = callProvider
    let registry = PKPushRegistry(queue: .main)
    registry.delegate = self
    registry.desiredPushTypes = [.voIP]
    voipRegistry = registry

    DispatchQueue.main.async {
      UIApplication.shared.registerForRemoteNotifications()
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
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
        DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
        result(nil)
      }
    }
    vetAiApnsChannel = apns

    let callKit = FlutterMethodChannel(name: "vet_ai/callkit", binaryMessenger: messenger)
    callKit.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      switch call.method {
      case "getVoipToken":
        result(self.vetAiVoipToken)
      case "consumeCallKitAction":
        result(self.pendingCallKitAction)
      case "ackCallKitAction":
        let args = call.arguments as? [String: Any]
        let actionId = args?["action_id"] as? String
        if actionId == nil || actionId == self.pendingCallKitAction?["action_id"] as? String {
          self.pendingCallKitAction = nil
        }
        result(nil)
      case "endSystemCall":
        let args = call.arguments as? [String: Any]
        if let callId = args?["call_id"] as? String, let uuid = UUID(uuidString: callId) {
          self.callProvider.reportCall(with: uuid, endedAt: Date(), reason: .remoteEnded)
          self.clearMetadata(callId)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    vetAiCallKitChannel = callKit

    if let pending = pendingCallKitAction {
      callKit.invokeMethod("callKitAction", arguments: pending)
    }
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    vetAiApnsToken = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
    NSLog("Vet AI APNs token received (%ld chars)", vetAiApnsToken?.count ?? 0)
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    NSLog("Vet AI APNs registration failed: %@", error.localizedDescription)
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }

  // MARK: - PushKit

  func pushRegistry(
    _ registry: PKPushRegistry,
    didUpdate pushCredentials: PKPushCredentials,
    for type: PKPushType
  ) {
    guard type == .voIP else { return }
    vetAiVoipToken = pushCredentials.token.map { String(format: "%02.2hhx", $0) }.joined()
    NSLog("Vet AI PushKit token received (%ld chars)", vetAiVoipToken?.count ?? 0)
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didInvalidatePushTokenFor type: PKPushType
  ) {
    if type == .voIP { vetAiVoipToken = nil }
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didReceiveIncomingPushWith payload: PKPushPayload,
    for type: PKPushType,
    completion: @escaping () -> Void
  ) {
    guard type == .voIP,
          let meta = payload.dictionaryPayload["vet_ai"] as? [String: Any],
          let callId = meta["call_id"] as? String,
          let uuid = UUID(uuidString: callId) else {
      completion()
      return
    }

    let event = (meta["event"] as? String) ?? "ringing"
    if event == "ended" || event == "declined" {
      callProvider.reportCall(with: uuid, endedAt: Date(), reason: .remoteEnded)
      clearMetadata(callId)
      completion()
      return
    }

    guard event == "ringing" else {
      completion()
      return
    }

    storeMetadata(meta, callId: callId)
    let caller = ((meta["caller_name"] as? String)?.isEmpty == false)
      ? (meta["caller_name"] as! String)
      : (((meta["caller_role"] as? String) == "user") ? "Vet AI customer" : "Vet AI Support")
    let update = CXCallUpdate()
    update.remoteHandle = CXHandle(type: .generic, value: caller)
    update.localizedCallerName = caller
    update.hasVideo = (meta["call_type"] as? String) == "video"
    update.supportsHolding = false
    update.supportsGrouping = false
    update.supportsUngrouping = false
    update.supportsDTMF = false

    callProvider.reportNewIncomingCall(with: uuid, update: update) { error in
      if let error = error {
        NSLog("Vet AI CallKit report failed: %@", error.localizedDescription)
        self.clearMetadata(callId)
      }
      completion()
    }
  }

  // MARK: - CallKit

  func providerDidReset(_ provider: CXProvider) {
    callMetadata.removeAll()
  }

  func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
    let callId = action.callUUID.uuidString.lowercased()
    guard var meta = metadata(callId) else {
      action.fail()
      return
    }
    configureVoiceAudio()
    meta["action"] = "answer"
    sendCallAction(meta: meta, action: "accept")
    emitCallKitAction(meta)
    requestCallScene(meta)
    action.fulfill()
  }

  func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
    let callId = action.callUUID.uuidString.lowercased()
    if var meta = metadata(callId) {
      meta["action"] = "end"
      sendCallAction(meta: meta, action: "end")
      emitCallKitAction(meta)
    }
    clearMetadata(callId)
    action.fulfill()
  }

  func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
    configureVoiceAudio()
  }

  func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
    try? audioSession.setActive(false, options: [.notifyOthersOnDeactivation])
  }

  private func configureVoiceAudio() {
    let audio = AVAudioSession.sharedInstance()
    try? audio.setCategory(
      .playAndRecord,
      mode: .voiceChat,
      options: [.allowBluetooth, .defaultToSpeaker]
    )
  }

  private func storeMetadata(_ meta: [String: Any], callId: String) {
    let key = callId.lowercased()
    callMetadata[key] = meta
    UserDefaults.standard.set(meta, forKey: "vet_ai_call_\(key)")
  }

  private func metadata(_ callId: String) -> [String: Any]? {
    let key = callId.lowercased()
    if let value = callMetadata[key] { return value }
    if let value = UserDefaults.standard.dictionary(forKey: "vet_ai_call_\(key)") {
      callMetadata[key] = value
      return value
    }
    return nil
  }

  private func clearMetadata(_ callId: String) {
    let key = callId.lowercased()
    callMetadata.removeValue(forKey: key)
    UserDefaults.standard.removeObject(forKey: "vet_ai_call_\(key)")
  }

  private func emitCallKitAction(_ input: [String: Any]) {
    var action = input
    action["action_id"] = UUID().uuidString
    pendingCallKitAction = action
    vetAiCallKitChannel?.invokeMethod("callKitAction", arguments: action)
  }

  private func sendCallAction(meta: [String: Any], action: String) {
    guard let callId = meta["call_id"] as? String,
          let roomKey = meta["room_key"] as? String,
          let url = URL(string: "https://mzqwjyantyvizwbzetwf.supabase.co/functions/v1/support-call-action") else {
      return
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = 8
    request.httpBody = try? JSONSerialization.data(withJSONObject: [
      "call_id": callId,
      "room_key": roomKey,
      "action": action,
    ])
    URLSession.shared.dataTask(with: request).resume()
  }

  private func requestCallScene(_ meta: [String: Any]) {
    guard #available(iOS 13.0, *) else { return }
    let activity = NSUserActivity(activityType: "com.vetai.app.support-call")
    activity.userInfo = meta
    UIApplication.shared.requestSceneSessionActivation(
      nil,
      userActivity: activity,
      options: nil,
      errorHandler: { error in
        NSLog("Vet AI call scene activation failed: %@", error.localizedDescription)
      }
    )
  }
}
''', encoding='utf-8')

    info_path = Path('ios/Runner/Info.plist')
    with info_path.open('rb') as f:
        info = plistlib.load(f)
    modes = list(info.get('UIBackgroundModes', []))
    for mode in ['voip', 'audio', 'remote-notification']:
        if mode not in modes:
            modes.append(mode)
    info['UIBackgroundModes'] = modes
    with info_path.open('wb') as f:
        plistlib.dump(info, f)

    native = app_delegate.read_text(encoding='utf-8')
    for marker in [
        'PKPushRegistryDelegate',
        'CXProviderDelegate',
        'desiredPushTypes = [.voIP]',
        'reportNewIncomingCall',
        'CXAnswerCallAction',
        'vet_ai/callkit',
        'getVoipToken',
        'consumeCallKitAction',
        'support-call-action',
    ]:
        if marker not in native:
            raise SystemExit(f'V66 native CallKit marker missing: {marker}')

    with info_path.open('rb') as f:
        verify_info = plistlib.load(f)
    for mode in ['voip', 'audio', 'remote-notification']:
        if mode not in verify_info.get('UIBackgroundModes', []):
            raise SystemExit(f'V66 iOS background mode missing: {mode}')


# Dart/source verification runs in both web and native jobs.
checks = {
    'lib/services/callkit_service.dart': [
        "MethodChannel('vet_ai/callkit')",
        "'register_voip_push_device'",
        'getVoipToken',
    ],
    'lib/support/callkit_coordinator.dart': [
        'vetRootNavigatorKey',
        "kind != 'answer'",
        'VetWebRtcCallPage',
    ],
    'lib/main_v2.dart': ['VetCallKitService.instance.initialize()', 'VetCallKitCoordinator.instance.initialize()'],
    'lib/v5_app.dart': ['navigatorKey: vetRootNavigatorKey', 'registerForFarm'],
    'lib/admin/admin_entry.dart': ['navigatorKey: vetRootNavigatorKey', 'registerForAdmin'],
}
for path_str, markers in checks.items():
    text = Path(path_str).read_text(encoding='utf-8')
    for marker in markers:
        if marker not in text:
            raise SystemExit(f'V66 verification missing: {path_str} / {marker}')

print('Vet AI V66 applied: PushKit VoIP wake-up + native CallKit phone-style incoming calls + WebRTC handoff')
