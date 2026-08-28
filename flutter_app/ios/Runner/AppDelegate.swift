import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  // Held as a stored property deliberately — without a strong reference
  // here, ARC would deallocate the plugin as soon as this method returns,
  // and its method/event channel handlers would silently stop firing the
  // moment a BLE delegate callback needed `self` to still exist.
  var posPrinterPlugin: PosPrinterPlugin?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    if let controller = window?.rootViewController as? FlutterViewController {
      posPrinterPlugin = PosPrinterPlugin(messenger: controller.binaryMessenger)
    }
    return result
  }
}
