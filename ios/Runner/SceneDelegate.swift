import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  /// Covers the window while the app is not active when the app lock is on.
  ///
  /// iOS takes the App Switcher snapshot as the app leaves the foreground,
  /// before Flutter can draw its lock screen (the engine tears the surface
  /// down first), so the cover has to be native. The Dart lock itself still
  /// engages on paused/hidden (lib/widgets/app_lock_gate.dart). This also
  /// shows behind the Face ID sheet, which is harmless.
  private var privacyCover: UIView?

  override func sceneWillResignActive(_ scene: UIScene) {
    super.sceneWillResignActive(scene)
    // shared_preferences stores Dart's 'app_lock_enabled' under this key.
    guard UserDefaults.standard.bool(forKey: "flutter.app_lock_enabled"),
      privacyCover == nil, let window = window
    else { return }
    let cover =
      UIStoryboard(name: "LaunchScreen", bundle: nil).instantiateInitialViewController()?.view
      ?? UIView()
    cover.backgroundColor = cover.backgroundColor ?? .systemBackground
    cover.frame = window.bounds
    cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    window.addSubview(cover)
    privacyCover = cover
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    privacyCover?.removeFromSuperview()
    privacyCover = nil
  }
}
