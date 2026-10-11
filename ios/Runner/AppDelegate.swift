import Flutter
import UIKit
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    registerGoogleMapsKey()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
  /// La clave sale de Info.plist (`GMSApiKey` <- `GOOGLE_MAPS_API_KEY` en
  /// ios/Flutter/Keys.xcconfig, que no se versiona). El SDK exige que se
  /// registre antes de crear el primer mapa; si falta, se registra una clave
  /// vacía para que la app no se caiga (el mapa queda sin tiles).
  private func registerGoogleMapsKey() {
    let raw = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String ?? ""
    let key = raw.trimmingCharacters(in: .whitespaces)
    if key.isEmpty || key.hasPrefix("$(") {
      NSLog("[SPLG] Falta GOOGLE_MAPS_API_KEY (ios/Flutter/Keys.xcconfig): el mapa no va a cargar.")
      GMSServices.provideAPIKey("MISSING_GOOGLE_MAPS_API_KEY")
    } else {
      GMSServices.provideAPIKey(key)
    }
  }
}
