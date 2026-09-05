// WhisperKit wrapper — owns the model lifecycle and transcription.
//
// The app does NOT capture audio itself (the G2 mic belongs to Even Hub);
// it receives 16 kHz f32 mono PCM from the loopback server. Model files are
// downloaded once by WhisperKit on first load, then run fully offline.
//
// API verified against argmaxinc/WhisperKit (main):
//   WhisperKit(model: String?, ..., verbose: Bool, logLevel: Logging.LogLevel, ...)
//   transcribe(audioArray: [Float], decodeOptions: DecodingOptions?, ...)
//       -> [TranscriptionResult]   (each has .text and .language)
//   DecodingOptions(task: DecodingTask, language: String?, ...)

import Foundation
import WhisperKit

final class WhisperEngine: @unchecked Sendable {
    struct Result: Sendable {
        let text: String
        let language: String?
    }

    private let lock = NSLock()
    private var kit: WhisperKit?
    private(set) var modelName = ""

    /// "ready" once a model is loaded, otherwise "idle".
    var state: String {
        lock.lock()
        defer { lock.unlock() }
        return kit == nil ? "idle" : "ready"
    }

    var currentModel: String {
        lock.lock()
        defer { lock.unlock() }
        return modelName
    }

    /// Downloads (first time) and loads the named WhisperKit model
    /// (e.g. "openai_whisper-small"). First run downloads ~500 MB.
    func load(modelName name: String) async throws {
        lock.lock()
        let alreadyLoaded = (kit != nil && modelName == name)
        lock.unlock()
        guard !alreadyLoaded else { return }

        // Plain convenience init — proven by Argmax's own sample app.
        // (verbose/logLevel params pull in swift-log types; keep it minimal.)
        let wk = try await WhisperKit(model: name)

        lock.lock()
        kit = wk
        modelName = name
        lock.unlock()
        NSLog("g2local: model loaded: \(name)")
    }

    /// Transcribes 16 kHz f32 mono audio. `language` nil = auto-detect.
    func transcribe(floats: [Float], task: String, language: String?) async throws -> Result {
        lock.lock()
        let wk = kit
        lock.unlock()
        guard let wk else {
            throw NSError(domain: "g2local", code: 503,
                          userInfo: [NSLocalizedDescriptionKey: "model not loaded"])
        }
        let decodingTask: DecodingTask = (task == "translation") ? .translate : .transcribe
        let options = DecodingOptions(task: decodingTask, language: language)
        let results = try await wk.transcribe(audioArray: floats, decodeOptions: options)

        let text = results
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let detected = results.first { !$0.language.isEmpty }?.language
        return Result(text: text, language: detected)
    }
}
