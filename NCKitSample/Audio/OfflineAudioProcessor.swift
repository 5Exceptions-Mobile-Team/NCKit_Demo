//
//  OfflineAudioProcessor.swift
//  NCKit Sample
//
//  Offline file denoise for imported audio using NCKitFileProcessor.
//

import Combine
import Foundation
import NCKit

enum OfflineAudioPhase: Equatable {
    case idle
    case processing
    case complete
    case error(String)

    var label: String {
        switch self {
        case .idle: return "Ready"
        case .processing: return "Denoising with NCKit..."
        case .complete: return "Done"
        case .error(let message): return "Error: \(message)"
        }
    }
}

@MainActor
final class OfflineAudioProcessor: ObservableObject {

    @Published var phase: OfflineAudioPhase = .idle

    private static var sharedProcessor: NCKitProcessor?

    func reset() {
        phase = .idle
    }

    /// Copies `sourceURL` to temp, denoises to a 48 kHz mono WAV, returns both URLs for A/B playback.
    func process(at sourceURL: URL) async -> (original: URL, enhanced: URL)? {
        phase = .processing

        do {
            let accessing = sourceURL.startAccessingSecurityScopedResource()
            defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }

            let tempDir = FileManager.default.temporaryDirectory
            let ext = sourceURL.pathExtension.isEmpty ? "m4a" : sourceURL.pathExtension
            let workingURL = tempDir.appendingPathComponent("import_\(UUID().uuidString).\(ext)")
            if FileManager.default.fileExists(atPath: workingURL.path) {
                try FileManager.default.removeItem(at: workingURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: workingURL)

            let outputURL = tempDir.appendingPathComponent("clean_\(UUID().uuidString).wav")
            let processor = try Self.processorInstance()

            try await Task.detached(priority: .userInitiated) {
                try NCKitFileProcessor.processFile(
                    inputURL: workingURL,
                    outputURL: outputURL,
                    processor: processor
                )
            }.value

            phase = .complete
            return (workingURL, outputURL)
        } catch {
            phase = .error(error.localizedDescription)
            return nil
        }
    }

    private static func processorInstance() throws -> NCKitProcessor {
        if let sharedProcessor { return sharedProcessor }
        let modelURL = try NCKitModelLocator.modelTarGzURL()
        let processor = try NCKitProcessor(modelURL: modelURL, attenLimDb: 100, postFilterBeta: 0)
        sharedProcessor = processor
        return processor
    }
}
