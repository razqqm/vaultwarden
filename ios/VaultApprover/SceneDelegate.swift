import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {

    /// Tag used to find the privacy overlay view.
    private let privacyTag = 99_887_766

    // MARK: - Privacy screen

    /// Called when the scene is about to resign active state (e.g. app switcher,
    /// notification centre pull-down, transition to background).
    /// We add an opaque overlay so the iOS snapshot does not capture sensitive content.
    override func sceneWillResignActive(_ scene: UIScene) {
        super.sceneWillResignActive(scene)
        guard let windowScene = scene as? UIWindowScene,
              let window = windowScene.windows.first else { return }

        // Avoid adding a duplicate overlay
        if window.viewWithTag(privacyTag) != nil { return }

        let blur = UIBlurEffect(style: .systemMaterial)
        let overlay = UIVisualEffectView(effect: blur)
        overlay.tag = privacyTag
        overlay.frame = window.bounds
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(overlay)
    }

    /// Called when the scene becomes active again.  Remove the overlay.
    override func sceneDidBecomeActive(_ scene: UIScene) {
        super.sceneDidBecomeActive(scene)
        guard let windowScene = scene as? UIWindowScene,
              let window = windowScene.windows.first else { return }
        window.viewWithTag(privacyTag)?.removeFromSuperview()
    }
}
