from pathlib import Path

# Vet AI V44 — real Apple Push Notification service integration.
# This patch runs after `flutter create`, so it can safely configure generated iOS files.

# 1) Register the signed-in iPhone for the current farm when the dashboard opens.
app_path = Path('lib/v5_app.dart')
app = app_path.read_text(encoding='utf-8')
if 'registerRemotePushForFarm' not in app:
    class_pos = app.find('class _V5DashboardState extends State<V5Dashboard>')
    if class_pos < 0:
        raise SystemExit('V44 APNs: dashboard state marker not found')
    marker = '    farm = Map<String, dynamic>.from(widget.initialFarm);\n'
    marker_pos = app.find(marker, class_pos)
    if marker_pos < 0:
        raise SystemExit('V44 APNs: dashboard farm init marker not found')
    replacement = marker + "    unawaited(VetAlertNotificationService.instance.registerRemotePushForFarm(farm['id']?.toString() ?? ''));\n"
    app = app[:marker_pos] + app[marker_pos:].replace(marker, replacement, 1)

# Replace the old temporary APNs disclaimer with a truthful production description.
app = app.replace(
    'Background push notifications when the app is fully closed require APNs/push credentials and are a separate deployment step. This screen never fabricates sensor alerts.',
    'Real APNs push alerts are enabled for registered iPhones. When notification permission is allowed, new server-side health and sensor alerts can arrive with sound even when Vet AI is closed.',
)
app = app.replace(
    'الإشعارات في الخلفية والتطبيق مقفول تمامًا محتاجة إعداد APNs/Push منفصل. الشاشة دي ما بتختلقش إنذارات حساسات.',
    'إنذارات APNs الحقيقية مفعلة لأجهزة iPhone المسجلة. بعد السماح بالإشعارات، إنذارات الصحة والحساسات الجديدة من السيرفر ممكن توصلك بصوت حتى لو Vet AI مقفول.',
)
app = app.replace(
    'Achtergrond-pushmeldingen wanneer de app volledig gesloten is vereisen aparte APNs/pushconfiguratie. Dit scherm verzint nooit sensormeldingen.',
    'Echte APNs-pushmeldingen zijn ingeschakeld voor geregistreerde iPhones. Na toestemming kunnen nieuwe gezondheids- en sensorwaarschuwingen met geluid aankomen, ook wanneer Vet AI gesloten is.',
)
app_path.write_text(app, encoding='utf-8')

# 2) Disable the current device token before account sign-out, so another user on the
# same phone does not keep receiving the previous farm's alerts.
backend_path = Path('lib/services/vet_backend.dart')
backend = backend_path.read_text(encoding='utf-8')
backend_import = "import 'alert_notification_service.dart';\n"
if backend_import not in backend:
    import_marker = "import 'package:supabase_flutter/supabase_flutter.dart';\n"
    if import_marker not in backend:
        raise SystemExit('V44 APNs: backend import marker not found')
    backend = backend.replace(import_marker, import_marker + "\n" + backend_import, 1)
old_signout = '  Future<void> signOut() => client.auth.signOut();'
new_signout = '''  Future<void> signOut() async {
    await VetAlertNotificationService.instance.unregisterRemotePush();
    await client.auth.signOut();
  }'''
if old_signout in backend:
    backend = backend.replace(old_signout, new_signout, 1)
elif 'unregisterRemotePush()' not in backend:
    raise SystemExit('V44 APNs: sign-out marker not found')
backend_path.write_text(backend, encoding='utf-8')

# 3) Configure the generated iOS app to obtain a real APNs device token.
app_delegate = Path('ios/Runner/AppDelegate.swift')
if not app_delegate.exists():
    raise SystemExit('V44 APNs: generated AppDelegate.swift not found')
app_delegate.write_text(r'''import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var vetAiApnsToken: String?
  private var pendingTokenResult: FlutterResult?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "vet_ai/apns",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { [weak self] call, result in
        guard call.method == "getToken" else {
          result(FlutterMethodNotImplemented)
          return
        }
        if let token = self?.vetAiApnsToken, !token.isEmpty {
          result(token)
          return
        }
        self?.pendingTokenResult = result
        DispatchQueue.main.async {
          UIApplication.shared.registerForRemoteNotifications()
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
    vetAiApnsToken = token
    pendingTokenResult?(token)
    pendingTokenResult = nil
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    pendingTokenResult?(
      FlutterError(
        code: "apns_registration_failed",
        message: error.localizedDescription,
        details: nil
      )
    )
    pendingTokenResult = nil
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }
}
''', encoding='utf-8')

# 4) APNs entitlement for App Store/TestFlight builds.
entitlements = Path('ios/Runner/Runner.entitlements')
entitlements.write_text('''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>aps-environment</key>
    <string>production</string>
</dict>
</plist>
''', encoding='utf-8')

pbx_path = Path('ios/Runner.xcodeproj/project.pbxproj')
pbx = pbx_path.read_text(encoding='utf-8')
entitlement_line = 'CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;'
if entitlement_line not in pbx:
    bundle_line = 'PRODUCT_BUNDLE_IDENTIFIER = com.vetai.app;'
    count = pbx.count(bundle_line)
    if count < 1:
        raise SystemExit('V44 APNs: Runner bundle identifier build setting not found')
    pbx = pbx.replace(
        bundle_line,
        entitlement_line + '\n\t\t\t\t' + bundle_line,
    )
    pbx_path.write_text(pbx, encoding='utf-8')

# Build-time verification.
checks = {
    'dashboard registration': 'registerRemotePushForFarm',
    'sign-out cleanup': 'unregisterRemotePush()',
    'native channel': 'vet_ai/apns',
    'APNs entitlement': 'aps-environment',
}
combined = app_path.read_text(encoding='utf-8') + backend_path.read_text(encoding='utf-8') + app_delegate.read_text(encoding='utf-8') + entitlements.read_text(encoding='utf-8')
for label, marker in checks.items():
    if marker not in combined:
        raise SystemExit(f'V44 APNs verification failed: {label}')

print('Vet AI V44 real APNs background push integration applied')
