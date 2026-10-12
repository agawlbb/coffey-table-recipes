import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    for context in connectionOptions.urlContexts where context.url.isFileURL {
      RecipeDocumentInbox.receive(context.url)
    }
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    let other = Set(URLContexts.filter { !$0.url.isFileURL })
    if !other.isEmpty { super.scene(scene, openURLContexts: other) }
    for context in URLContexts where context.url.isFileURL {
      RecipeDocumentInbox.receive(context.url)
    }
  }
}
