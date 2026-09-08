from pathlib import Path

# Vet AI V46 — Flutter 3.41+ uses the UIScene lifecycle by default on iOS.
# In that lifecycle AppDelegate.window can be nil during launch, so platform
# channels must be created from FlutterImplicitEngineDelegate instead of
# window?.rootViewController. This patch replaces the older V45 bridge with
# the current Flutter-supported UIScene bridge and keeps APNs registration.

app_delegate = Path('ios/Runner/AppDelegate.swift')
if not app_delegate.exists():
    raise SystemExit('V46 APNs: generated AppDelegate.swift not found')

app_delegate.write_text(r'''import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var vetAiApnsToken: String?
  private var vetAiApnsChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    DispatchQueue.main.async {
      UIApplication.shared.registerForRemoteNotifications()
    }
    return super.application(
      application,
      didFinishLaunchingWithOptions: launchOptions
    )
  }

  func didInitializeImplicitFlutterEngine(
    _ engineBridge: FlutterImplicitEngineBridge
  ) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(
      name: "vet_ai/apns",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
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

      DispatchQueue.main.async {
        UIApplication.shared.registerForRemoteNotifications()
      }
      // Dart retries while APNs finishes registration.
      result(nil)
    }

    vetAiApnsChannel = channel

    DispatchQueue.main.async {
      UIApplication.shared.registerForRemoteNotifications()
    }
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    vetAiApnsToken = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
    NSLog("Vet AI APNs token received (%ld chars)", vetAiApnsToken?.count ?? 0)
    super.application(
      application,
      didRegisterForRemoteNotificationsWithDeviceToken: deviceToken
    )
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    NSLog("Vet AI APNs registration failed: %@", error.localizedDescription)
    super.application(
      application,
      didFailToRegisterForRemoteNotificationsWithError: error
    )
  }
}
''', encoding='utf-8')

native = app_delegate.read_text(encoding='utf-8')
required_native = [
    'FlutterImplicitEngineDelegate',
    'didInitializeImplicitFlutterEngine',
    'engineBridge.applicationRegistrar.messenger()',
    'registerForRemoteNotifications',
    'didRegisterForRemoteNotificationsWithDeviceToken',
    'vet_ai/apns',
]
for marker in required_native:
    if marker not in native:
        raise SystemExit(f'V46 APNs: UIScene bridge marker missing: {marker}')

# Guard against accidentally reintroducing the pre-UIScene channel path.
if 'window?.rootViewController as? FlutterViewController' in native:
    raise SystemExit('V46 APNs: old window/rootViewController bridge is still present')

service_path = Path('lib/services/alert_notification_service.dart')
service = service_path.read_text(encoding='utf-8')
for marker in [
    '_fetchApnsTokenWithRetry',
    "invokeMethod<String>('getToken')",
    "'register_push_device'",
]:
    if marker not in service:
        raise SystemExit(f'V46 APNs: Dart registration marker missing: {marker}')

print('Vet AI V46 Flutter UIScene APNs bridge applied')
