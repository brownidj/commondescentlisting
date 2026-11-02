import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var transcriptChannel: FlutterMethodChannel?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "common_descent/transcript_export",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    transcriptChannel = channel
    channel.setMethodCallHandler { call, result in
      guard call.method == "shareFiles" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let paths = call.arguments as? [String], !paths.isEmpty, paths.count <= 4 else {
        result(FlutterError(code: "invalid_files", message: "Invalid transcript files.", details: nil))
        return
      }
      let temp = URL(fileURLWithPath: NSTemporaryDirectory()).resolvingSymlinksInPath().path + "/"
      let urls = paths.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath() }
      guard urls.allSatisfy({ $0.path.hasPrefix(temp) && FileManager.default.fileExists(atPath: $0.path) }) else {
        result(FlutterError(code: "invalid_files", message: "Export files must be temporary files.", details: nil))
        return
      }
      let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }),
            var presenter = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
        result(FlutterError(code: "no_window", message: "No active window for sharing.", details: nil))
        return
      }
      while let presented = presenter.presentedViewController {
        presenter = presented
      }
      let sheet = UIActivityViewController(activityItems: urls, applicationActivities: nil)
      sheet.completionWithItemsHandler = { _, completed, _, error in
        if let error = error {
          result(FlutterError(code: "share_failed", message: error.localizedDescription, details: nil))
        } else {
          result(completed)
        }
      }
      if let popover = sheet.popoverPresentationController {
        popover.sourceView = presenter.view
        popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
        popover.permittedArrowDirections = []
      }
      presenter.present(sheet, animated: true)
    }
  }
}
