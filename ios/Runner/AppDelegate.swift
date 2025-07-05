import GoogleMaps
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    GMSServices.provideAPIKey("AIzaSyDyGOslAte8s5hIyN5LLApFvPsyimQenH8")
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
