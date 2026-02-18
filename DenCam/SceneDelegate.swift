import UIKit

// SceneDelegate manages a single UI window.
// We create the window programmatically (no storyboard) and set ViewController as the root.

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    // UIKit assigns this property when the scene connects.
    // We keep a strong reference so the window stays alive.
    var window: UIWindow?

    // Called when the scene is first created. This is where we build the window
    // and attach our root view controller.
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        // scene must be a UIWindowScene — guard against unexpected types
        guard let windowScene = scene as? UIWindowScene else { return }

        // Create the window, attach it to this scene, and set the root VC
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = ViewController()
        self.window = window

        // makeKeyAndVisible shows the window on screen
        window.makeKeyAndVisible()
    }
}
