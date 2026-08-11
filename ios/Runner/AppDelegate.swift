import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    excludeLocalDatabaseFromBackup()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Keeps the local Isar database out of iCloud / iTunes backups.
  ///
  /// The DB lives in `Documents` (that's where `path_provider` points Isar) and
  /// holds real financial figures with no encryption at rest — Isar 3 has no
  /// encryption support — so allowing the platform to copy it off-device is the
  /// iOS counterpart of `android:allowBackup="true"`. Nothing is lost by
  /// opting out: a restored device signs in and re-syncs from Supabase.
  ///
  /// Runs on every launch because the flag is per-file and the files are
  /// created by Isar after the first launch, not by us.
  private func excludeLocalDatabaseFromBackup() {
    guard let documents = FileManager.default.urls(
      for: .documentDirectory, in: .userDomainMask
    ).first else { return }

    for name in ["default.isar", "default.isar.lock"] {
      var url = documents.appendingPathComponent(name)
      guard FileManager.default.fileExists(atPath: url.path) else { continue }
      do {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
      } catch {
        // Non-fatal: the app is still fully usable, the file just stays in
        // the backup set. Surfaced in the log rather than crashing launch.
        NSLog("Could not exclude \(name) from backup: \(error)")
      }
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
