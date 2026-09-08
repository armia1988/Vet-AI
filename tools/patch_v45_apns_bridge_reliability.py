from pathlib import Path

# Vet AI V45 — make the native APNs bridge reliable on modern Flutter/iOS startup.
# V44 created the bridge before Flutter had necessarily attached the root view controller.
# This version configures the channel after Flutter startup, retries bridge attachment,
# proactively registers with APNs, and lets Dart poll for the token safely.

app_delegate = Path('ios/Runner/AppDelegate.swift')
if not app_delegate.exists():
    raise SystemExit('V45 APNs: generated AppDelegate.swift not found')

app_delegate.write_text(r'''import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var vetAiApnsToken: String?
  private var vetAiApnsChannel: FlutterMethodChannel?
  private var bridgeAttachAttempts = 0

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    let started = super.application(
      application,
      didFinishLaunchingWithOptions: launchOptions
    )

    configureVetAiApnsBridge()
    DispatchQueue.main.async { [weak self] in
      self?.configureVetAiApnsBridge()
      UIApplication.shared.registerForRemoteNotifications()
    }
    return started
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    configureVetAiApnsBridge()
    DispatchQueue.main.async {
      UIApplication.shared.registerForRemoteNotifications()
    }
  }

  private func configureVetAiApnsBridge() {
    guard vetAiApnsChannel == nil else { return }

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

        UIApplication.shared.registerForRemoteNotifications()
        // Return immediately. Dart retries for a short window while APNs finishes registration.
        result(nil)
      }
      vetAiApnsChannel = channel
      return
    }

    bridgeAttachAttempts += 1
    if bridgeAttachAttempts <= 20 {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
        self?.configureVetAiApnsBridge()
      }
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
}
''', encoding='utf-8')

# Verify the native bridge plus the Dart retry logic are both present.
service_path = Path('lib/services/alert_notification_service.dart')
service = service_path.read_text(encoding='utf-8')
required_service = [
    '_fetchApnsTokenWithRetry',
    "invokeMethod<String>('getToken')",
    "'register_push_device'",
]
for marker in required_service:
    if marker not in service:
        raise SystemExit(f'V45 APNs: Dart registration reliability marker missing: {marker}')

native = app_delegate.read_text(encoding='utf-8')
required_native = [
    'applicationDidBecomeActive',
    'configureVetAiApnsBridge',
    'registerForRemoteNotifications',
    'vet_ai/apns',
]
for marker in required_native:
    if marker not in native:
        raise SystemExit(f'V45 APNs: native bridge reliability marker missing: {marker}')

print('Vet AI V45 reliable APNs bridge applied')
