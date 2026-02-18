import UIKit

// AppDelegate handles the app-level lifecycle.
// Since we use UIKit scenes (iOS 13+), most window setup happens in SceneDelegate.
// AppDelegate's main job here is to return the scene configuration that tells UIKit
// which SceneDelegate class to use.

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    // Called once when the app process launches.
    // We don't need any custom setup here yet — just return true to indicate success.
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        return true
    }

    // MARK: - UISceneSession Lifecycle

    // Called when UIKit needs a new scene (window). We return a configuration
    // that points to our SceneDelegate class. The configuration name "Default Configuration"
    // must match what's declared in Info.plist under UIApplicationSceneManifest.
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role
        )
        config.delegateClass = SceneDelegate.self
        return config
    }
}
