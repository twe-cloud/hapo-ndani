import AppCore
import Foundation

public enum NdaniRuntimeLoader {
    public static func makeEngine(for status: NdaniLocalModelStatus) -> NdaniInferenceEngine? {
        guard status.canLaunchRuntime,
              status.package.runtimeAdapter.id == NdaniLocalRuntimeAdapter.llamaCpp.id
        else {
            return nil
        }

        return LlamaInferenceEngine(
            modelPath: status.path,
            modelName: status.package.title,
            maxOutputTokens: 384,
            maxGenerationSeconds: 90
        )
    }
}
