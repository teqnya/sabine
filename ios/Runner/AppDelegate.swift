import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerPlatformChannel(engineBridge.pluginRegistry)
  }

  /// Small native helpers without third-party plugins:
  /// - documentsDirectory: the app's Documents path as iOS reports it (HOME is
  ///   not reliable when launched via devicectl).
  /// - setIdleTimerDisabled: keeps the screen on during long spike runs; iOS
  ///   suspends apps on lock and Metal work is not allowed in the background.
  private func registerPlatformChannel(_ registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "VeltrioPlatform") else { return }
    let channel = FlutterMethodChannel(
      name: "veltrio/platform", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "documentsDirectory":
        result(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path)
      case "setIdleTimerDisabled":
        UIApplication.shared.isIdleTimerDisabled = (call.arguments as? Bool) ?? false
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
