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
  /// The DB lives in `Library/Application Support` (see `lib/services/local_db.dart`;
  /// Documents is visible in Files and holds only the encrypted vault) and
  /// holds real financial figures with no encryption at rest — Isar 3 has no
  /// encryption support — so allowing the platform to copy it off-device is the
  /// iOS counterpart of `android:allowBackup="true"`. Nothing is lost by
  /// opting out: a restored device signs in and re-syncs from Supabase.
  ///
  /// Runs on every launch because the flag is per-file and the files are
  /// created by Isar after the first launch, not by us.
  private func excludeLocalDatabaseFromBackup() {
    guard let support = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask
    ).first else { return }

    for name in ["default.isar", "default.isar.lock"] {
      var url = support.appendingPathComponent(name)
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
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "VaultOpenIn") {
      VaultOpenIn.register(with: registrar)
    }
  }
}

/// Hands `.lmvault` files opened from Files / AirDrop to Dart
/// (`lib/vault/vault_open_in.dart`), on cold and warm start.
///
/// With `LSSupportsOpeningDocumentsInPlace` the URL can point outside the
/// sandbox (iCloud Drive) and is only readable inside a security-scoped access,
/// which Dart's `File` can't open. So the file is copied into tmp here and Dart
/// gets that path.
final class VaultOpenIn: NSObject, FlutterPlugin, FlutterSceneLifeCycleDelegate {
  private var channel: FlutterMethodChannel?
  private var pending: [String] = []
  private var dartReady = false

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = VaultOpenIn()
    let channel = FlutterMethodChannel(
      name: "life_manager/vault_open_in", binaryMessenger: registrar.messenger())
    instance.channel = channel
    registrar.addMethodCallDelegate(instance, channel: channel)
    registrar.addSceneDelegate(instance)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "ready" else { return result(FlutterMethodNotImplemented) }
    dartReady = true
    result(pending)
    pending.removeAll()
  }

  func scene(
    _ scene: UIScene, willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions?
  ) -> Bool {
    guard let contexts = connectionOptions?.urlContexts else { return false }
    return self.scene(scene, openURLContexts: contexts)
  }

  func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) -> Bool {
    var handled = false
    for context in URLContexts where context.url.pathExtension.lowercased() == "lmvault" {
      guard let path = copyToTemp(context.url) else { continue }
      handled = true
      if dartReady {
        channel?.invokeMethod("open", arguments: path)
      } else {
        pending.append(path)
      }
    }
    return handled
  }

  private func copyToTemp(_ url: URL) -> String? {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    // A fresh folder per open keeps the original name for the sheet.
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("opened-vaults/\(UUID().uuidString)", isDirectory: true)
    let dest = dir.appendingPathComponent(url.lastPathComponent)
    do {
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      // Coordinated read: the file may still be downloading from iCloud.
      var copyError: Error?
      var coordError: NSError?
      NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordError) {
        do { try FileManager.default.copyItem(at: $0, to: dest) } catch { copyError = error }
      }
      if let e = coordError ?? copyError { throw e }
      return dest.path
    } catch {
      NSLog("Could not open vault \(url.lastPathComponent): \(error)")
      return nil
    }
  }
}
