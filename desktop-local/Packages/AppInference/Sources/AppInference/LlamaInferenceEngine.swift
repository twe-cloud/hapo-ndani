import AppCore
import Darwin
import Foundation
import LlamaSwift

public final class LlamaInferenceEngine: @unchecked Sendable, NdaniInferenceEngine {
    public let modelName: String
    public private(set) var isLoaded: Bool = false

    private let modelPath: String
    private var model: OpaquePointer?      // llama_model *
    private var context: OpaquePointer?    // llama_context *
    private let contextSize: UInt32
    private let maxOutputTokens: Int32
    private let maxGenerationSeconds: TimeInterval
    private let lock = NSLock()

    // H24: Single dedicated serial queue instead of Thread.detachNewThread per call
    private let inferenceQueue = DispatchQueue(label: "biz.nibiashara.ndani.inference", qos: .userInitiated)

    // H20: Memory pressure source to unload model under critical pressure
    private var memoryPressureSource: DispatchSourceMemoryPressure?

    public init(
        modelPath: String,
        modelName: String,
        contextSize: UInt32 = 4096,
        maxOutputTokens: Int32 = 384,
        maxGenerationSeconds: TimeInterval = 45
    ) {
        self.modelPath = modelPath
        self.modelName = modelName
        self.contextSize = contextSize
        self.maxOutputTokens = maxOutputTokens
        self.maxGenerationSeconds = maxGenerationSeconds

        // H20: Monitor memory pressure and unload model when critical
        let source = DispatchSource.makeMemoryPressureSource(eventMask: .critical, queue: .global(qos: .utility))
        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.unload()
        }
        source.activate()
        self.memoryPressureSource = source
    }

    deinit {
        memoryPressureSource?.cancel()
        memoryPressureSource = nil
        unload()
    }

    public func unload() {
        lock.lock()
        defer { lock.unlock() }

        if let c = context {
            llama_free(c)
            context = nil
        }
        if let m = model {
            llama_model_free(m)
            model = nil
        }
        isLoaded = false
    }

    public func load() throws {
        lock.lock()
        defer { lock.unlock() }

        guard !isLoaded else { return }

        // H21: Detect available memory and set n_gpu_layers appropriately
        let physicalMemoryGB = ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)

        var modelParams = llama_model_default_params()
        if physicalMemoryGB < 12 {
            modelParams.n_gpu_layers = 24
        } else {
            modelParams.n_gpu_layers = 99
        }

        guard let m = llama_model_load_from_file(modelPath, modelParams) else {
            throw InferenceError.modelLoadFailed
        }
        model = m

        var ctxParams = llama_context_default_params()
        ctxParams.n_ctx = contextSize
        // M10: Auto-tune n_batch based on available RAM
        ctxParams.n_batch = physicalMemoryGB < 12 ? 256 : 512
        ctxParams.n_threads = Int32(max(1, ProcessInfo.processInfo.activeProcessorCount - 2))
        ctxParams.n_threads_batch = Int32(max(1, ProcessInfo.processInfo.activeProcessorCount - 1))

        guard let c = llama_init_from_model(m, ctxParams) else {
            llama_model_free(m)
            model = nil
            throw InferenceError.contextCreateFailed
        }
        context = c
        isLoaded = true
    }

    /// Synchronous helper: read `isLoaded` under the lock.
    private func lockedIsLoaded() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isLoaded
    }

    /// Synchronous helper: capture model/context pointers under the lock.
    private func lockedCaptureState(
        messages: [(role: NdaniChatRole, content: String)]
    ) throws -> (prompt: String, model: OpaquePointer, context: OpaquePointer) {
        lock.lock()
        guard let capturedModel = model, let capturedContext = context else {
            lock.unlock()
            throw InferenceError.modelNotLoaded
        }
        let prompt = Self.formatPrompt(messages, model: capturedModel)
        lock.unlock()
        return (prompt, capturedModel, capturedContext)
    }

    public func generate(
        messages: [(role: NdaniChatRole, content: String)]
    ) async throws -> AsyncThrowingStream<String, Error> {
        // H2: Read isLoaded under the lock (synchronous helper avoids async context restriction)
        if !lockedIsLoaded() {
            try load()
        }

        // H1: Capture model/context pointers under the lock so unload() cannot
        // free them between the read and the inference queue dispatch.
        let captured = try lockedCaptureState(messages: messages)

        let capturedMaxOutputTokens = self.maxOutputTokens
        let capturedMaxGenerationSeconds = self.maxGenerationSeconds
        let capturedLock = self.lock

        return AsyncThrowingStream { continuation in
            // H24: Dispatch onto the dedicated serial queue instead of spawning a new thread
            self.inferenceQueue.async {
                // H1: Re-acquire lock for inference to serialize against unload()
                capturedLock.lock()
                defer { capturedLock.unlock() }

                do {
                    try Self.runInference(
                        prompt: captured.prompt,
                        model: captured.model,
                        context: captured.context,
                        maxOutputTokens: capturedMaxOutputTokens,
                        maxGenerationSeconds: capturedMaxGenerationSeconds,
                        continuation: continuation
                    )
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private static func runInference(
        prompt: String,
        model: OpaquePointer,
        context: OpaquePointer,
        maxOutputTokens: Int32,
        maxGenerationSeconds: TimeInterval,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) throws {
        // H19: Guard against nil vocab instead of force unwrap
        guard let vocab = llama_model_get_vocab(model) else {
            throw InferenceError.modelNotLoaded
        }

        // Tokenize
        let maxTokens = Int32(prompt.utf8.count + 256)
        var tokens = [llama_token](repeating: 0, count: Int(maxTokens))
        let nTokens = llama_tokenize(vocab, prompt, Int32(prompt.utf8.count), &tokens, maxTokens, true, true)

        guard nTokens > 0 else {
            throw InferenceError.tokenizationFailed
        }

        tokens = Array(tokens.prefix(Int(nTokens)))

        // Clear memory (KV cache)
        let memory = llama_get_memory(context)
        if let memory {
            llama_memory_clear(memory, true)
        }

        // Evaluate prompt using batch_get_one
        let promptCount = Int32(tokens.count)
        var batch = tokens.withUnsafeMutableBufferPointer { buf -> llama_batch in
            llama_batch_get_one(buf.baseAddress, promptCount)
        }

        let evalResult = llama_decode(context, batch)
        guard evalResult == 0 else {
            throw InferenceError.decodeFailed
        }

        // Create sampler
        let sparams = llama_sampler_chain_default_params()
        guard let sampler = llama_sampler_chain_init(sparams) else {
            throw InferenceError.decodeFailed
        }
        defer { llama_sampler_free(sampler) }

        llama_sampler_chain_add(sampler, llama_sampler_init_top_k(40))
        llama_sampler_chain_add(sampler, llama_sampler_init_top_p(0.9, 1))
        llama_sampler_chain_add(sampler, llama_sampler_init_min_p(0.02, 1))
        llama_sampler_chain_add(sampler, llama_sampler_init_temp(0.4))
        llama_sampler_chain_add(sampler, llama_sampler_init_dist(0))

        // Generate tokens
        var nGenerated: Int32 = 0
        let maxGenerate = max(1, maxOutputTokens)
        let deadline = Date().addingTimeInterval(max(1, maxGenerationSeconds))
        var rawGenerated = ""
        var visibleGenerated = ""

        while nGenerated < maxGenerate {
            guard Date() < deadline else {
                throw InferenceError.generationTimedOut
            }

            let newToken = llama_sampler_sample(sampler, context, -1)

            if llama_vocab_is_eog(vocab, newToken) { break }

            // Convert token to text
            var buf = [CChar](repeating: 0, count: 256)
            let len = llama_token_to_piece(vocab, newToken, &buf, 256, 0, true)
            if len > 0 {
                let piece = String(decoding: buf.prefix(Int(len)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
                rawGenerated += piece
                let visible = visibleResponse(from: rawGenerated)
                if visible.count > visibleGenerated.count {
                    let start = visible.index(visible.startIndex, offsetBy: visibleGenerated.count)
                    continuation.yield(String(visible[start...]))
                    visibleGenerated = visible
                }
            }

            llama_sampler_accept(sampler, newToken)

            // Decode next token
            var nextToken = newToken
            batch = withUnsafeMutablePointer(to: &nextToken) { ptr in
                llama_batch_get_one(ptr, 1)
            }

            let decodeResult = llama_decode(context, batch)
            if decodeResult != 0 { break }

            nGenerated += 1
        }

        continuation.finish()
    }

    private static func formatPrompt(_ messages: [(role: NdaniChatRole, content: String)], model: OpaquePointer) -> String {
        let lastUserIndex = messages.lastIndex { $0.role == .user }
        let cMessages: [llama_chat_message] = messages.enumerated().map { index, message in
            let role = strdup(roleTag(for: message.role))
            let content = if index == lastUserIndex {
                message.content + "\n/no_think"
            } else {
                message.content
            }
            let contentPointer = strdup(content)
            return llama_chat_message(role: role, content: contentPointer)
        }
        defer {
            for message in cMessages {
                free(UnsafeMutableRawPointer(mutating: message.role))
                free(UnsafeMutableRawPointer(mutating: message.content))
            }
        }

        let template = llama_model_chat_template(model, nil)
        var bufferSize = max(4096, messages.reduce(0) { $0 + $1.content.utf8.count + 64 } * 3)
        var buffer = [CChar](repeating: 0, count: bufferSize)
        var result = cMessages.withUnsafeBufferPointer { pointer in
            llama_chat_apply_template(template, pointer.baseAddress, pointer.count, true, &buffer, Int32(buffer.count))
        }

        if result >= Int32(buffer.count) {
            bufferSize = Int(result) + 1
            buffer = [CChar](repeating: 0, count: bufferSize)
            result = cMessages.withUnsafeBufferPointer { pointer in
                llama_chat_apply_template(template, pointer.baseAddress, pointer.count, true, &buffer, Int32(buffer.count))
            }
        }

        if result > 0 {
            return String(decoding: buffer.prefix(Int(result)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
        }

        return fallbackPrompt(messages)
    }

    private static func fallbackPrompt(_ messages: [(role: NdaniChatRole, content: String)]) -> String {
        let lastUserIndex = messages.lastIndex { $0.role == .user }
        var prompt = ""
        for (index, message) in messages.enumerated() {
            let content = if index == lastUserIndex {
                message.content + "\n/no_think"
            } else {
                message.content
            }
            prompt += "<|im_start|>\(roleTag(for: message.role))\n\(content)<|im_end|>\n"
        }
        prompt += "<|im_start|>assistant\n"
        return prompt
    }

    private static func roleTag(for role: NdaniChatRole) -> String {
        switch role {
        case .system: "system"
        case .user: "user"
        case .assistant: "assistant"
        }
    }

    // M6: Think-tag stripping for streaming output. This is the single source of truth
    // for stripping <think> tags during token generation. NdaniChatState should defer to
    // this implementation for streaming; any post-hoc stripping there is a display-only fallback.
    private static func visibleResponse(from rawResponse: String) -> String {
        var cleaned = rawResponse
        while let start = cleaned.range(of: "<think>", options: .caseInsensitive) {
            guard let end = cleaned.range(of: "</think>", options: .caseInsensitive, range: start.upperBound..<cleaned.endIndex) else {
                cleaned.removeSubrange(start.lowerBound..<cleaned.endIndex)
                break
            }
            cleaned.removeSubrange(start.lowerBound..<end.upperBound)
        }

        let tag = "<think>"
        let lowercased = cleaned.lowercased()
        let maxSuffixLength = min(tag.count - 1, lowercased.count)
        for length in stride(from: maxSuffixLength, through: 1, by: -1) {
            let suffixStart = lowercased.index(lowercased.endIndex, offsetBy: -length)
            let suffix = String(lowercased[suffixStart...])
            if tag.hasPrefix(suffix) {
                let removeStart = cleaned.index(cleaned.endIndex, offsetBy: -length)
                cleaned.removeSubrange(removeStart..<cleaned.endIndex)
                break
            }
        }

        return cleaned
    }

    public enum InferenceError: LocalizedError {
        case modelLoadFailed
        case contextCreateFailed
        case modelNotLoaded
        case tokenizationFailed
        case decodeFailed
        case generationTimedOut

        public var errorDescription: String? {
            switch self {
            case .modelLoadFailed: "Failed to load model file."
            case .contextCreateFailed: "Failed to create inference context."
            case .modelNotLoaded: "No model is loaded."
            case .tokenizationFailed: "Failed to tokenize input."
            case .decodeFailed: "Inference decode failed."
            case .generationTimedOut: "Local AI took too long to respond."
            }
        }
    }
}
