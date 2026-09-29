import AppInference
import AppUI
import SwiftUI

@main
struct NdaniMobileApp: App {
    var body: some Scene {
        WindowGroup {
            NdaniMobileRootView(
                inferenceEngineFactory: NdaniRuntimeLoader.makeEngine(for:)
            )
        }
    }
}
