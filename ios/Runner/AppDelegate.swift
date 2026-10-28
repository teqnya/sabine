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
    registerPathsChannel(engineBridge.pluginRegistry)
  }

  /// Returns the app's Documents directory as iOS reports it. Avoids relying
  /// on the HOME environment variable and avoids a path_provider dependency.
  private func registerPathsChannel(_ registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "VeltrioPaths") else { return }
    let channel = FlutterMethodChannel(
      name: "veltrio/paths", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "documentsDirectory":
        result(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
