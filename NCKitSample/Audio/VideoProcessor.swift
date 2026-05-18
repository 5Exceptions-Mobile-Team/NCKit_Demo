//
//  VideoProcessor.swift
//  NCKit Sample
//
//  Offline noise cancellation for video files using NCKit.
//
//  Pipeline:
//    1. AVFoundation extracts mono Float32 audio from the source video.
//    2. NCKitFileProcessor denoises the audio file (handles resampling internally).
//    3. NCKitAudioNormalizer applies speech-gated makeup gain.
//    4. AVMutableComposition muxes the cleaned audio back with the video.
//

import AVFoundation
import Combine
import Foundation
import NCKit
import Photos

enum ProcessingPhase: Equatable {
    case idle
    case extracting
    case processing
    case remuxing
    case complete
    case error(String)

    var label: String {
        switch self {
        case .idle: return "Ready"
        case .extracting: return "Extracting audio..."
        case .processing: return "Denoising with NCKit..."
        case .remuxing: return "Creating output video..."
        case .complete: return "Done"
        case .error(let m): return "Error: \(m)"
        }
    }
}

struct ProcessedVideoResult {
    let originalVideoURL: URL
    let enhancedVideoURL: URL
    let originalWaveform: [WaveformGenerator.WaveformPoint]
    let enhancedWaveform: [WaveformGenerator.WaveformPoint]
    let duration: Double
}

@MainActor
final class VideoProcessor: ObservableObject {

    @Published var phase: ProcessingPhase = .idle
    @Published var progress: Double = 0
    @Published var result: ProcessedVideoResult?

    private let sampleRate: Int = 48_000

    func reset() {
        phase = .idle
        progress = 0
        result = nil
    }

    /// End-to-end video denoise using NCKit.
    func processVideo(at sourceURL: URL) async {
        reset()

        do {
            let tempDir = FileManager.default.temporaryDirectory
            let workingURL = tempDir.appendingPathComponent(
                "nckit_input_\(UUID().uuidString).\(sourceURL.pathExtension)"
            )

            // Copy source out of security-scoped sandbox if needed.
            let accessing = sourceURL.startAccessingSecurityScopedResource()
            defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }
            if FileManager.default.fileExists(atPath: workingURL.path) {
                try FileManager.default.removeItem(at: workingURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: workingURL)

            let asset = AVURLAsset(url: workingURL)
            guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
                throw ProcessingError.noAudioTrack
            }
            guard try await asset.loadTracks(withMediaType: .video).first != nil else {
                throw ProcessingError.noVideoTrack
            }
            let duration = try await asset.load(.duration).seconds

            // Step 1 — Extract original audio as 48 kHz mono Float32 WAV.
            phase = .extracting
            let originalSamples = try await extractAudio(from: asset, track: audioTrack)
            progress = 0.1

            let originalWavURL = tempDir.appendingPathComponent("nckit_orig_\(UUID().uuidString).wav")
            try WavWriter.write(samples: originalSamples, sampleRate: sampleRate, to: originalWavURL)
            let origWaveform = WaveformGenerator.generate(from: originalSamples, width: 350)
            progress = 0.2

            // Step 2 — Run NCKit on the extracted WAV.
            //
            // NCKitFileProcessor handles streaming I/O internally and is safe
            // for files of any length. We pass a fresh NCKitProcessor so GRU
            // state starts clean for this file.
            phase = .processing
            let denoisedURL = tempDir.appendingPathComponent("nckit_clean_\(UUID().uuidString).wav")

            try await Task.detached(priority: .userInitiated) {
                let modelURL = try NCKitModelLocator.modelTarGzURL()
                let processor = try NCKitProcessor(
                    modelURL: modelURL,
                    attenLimDb: 100,
                    postFilterBeta: 0
                )
                try NCKitFileProcessor.processFile(
                    inputURL: originalWavURL,
                    outputURL: denoisedURL,
                    processor: processor
                )
            }.value
            progress = 0.7

            // Step 3 — Speech-gated makeup gain via NCKit.
            let denoisedAsset = AVURLAsset(url: denoisedURL)
            guard let dAudio = try await denoisedAsset.loadTracks(withMediaType: .audio).first else {
                throw ProcessingError.noAudioTrack
            }
            var enhancedSamples = try await extractAudio(from: denoisedAsset, track: dAudio)
            NCKitAudioNormalizer.applySpeechGatedMakeupGain(&enhancedSamples, sampleRate: sampleRate)
            progress = 0.85

            let enhancedWavURL = tempDir.appendingPathComponent("nckit_enh_\(UUID().uuidString).wav")
            try WavWriter.write(samples: enhancedSamples, sampleRate: sampleRate, to: enhancedWavURL)
            let enhWaveform = WaveformGenerator.generate(from: enhancedSamples, width: 350)
            try? FileManager.default.removeItem(at: denoisedURL)

            // Step 4 — Mux enhanced audio with original video.
            phase = .remuxing
            let finalURL = tempDir.appendingPathComponent("nckit_final_\(UUID().uuidString).mp4")
            try await mux(videoURL: workingURL, audioURL: enhancedWavURL, outputURL: finalURL)
            progress = 1.0

            result = ProcessedVideoResult(
                originalVideoURL: workingURL,
                enhancedVideoURL: finalURL,
                originalWaveform: origWaveform,
                enhancedWaveform: enhWaveform,
                duration: duration
            )
            phase = .complete

        } catch is CancellationError {
            phase = .idle
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    func saveToPhotos() async throws {
        guard let url = result?.enhancedVideoURL else { return }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
    }

    // MARK: - Helpers

    private func extractAudio(from asset: AVAsset, track: AVAssetTrack) async throws -> [Float] {
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1
        ]

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        reader.add(output)

        guard reader.startReading() else {
            throw ProcessingError.readerFailed(reader.error?.localizedDescription ?? "unknown")
        }

        let duration = try await asset.load(.duration).seconds
        var samples = [Float]()
        samples.reserveCapacity(Int(duration * Double(sampleRate)))

        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            let floatCount = length / MemoryLayout<Float>.size
            var buf = [Float](repeating: 0, count: floatCount)
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: &buf)
            samples.append(contentsOf: buf)
        }

        guard reader.status == .completed else {
            throw ProcessingError.readerFailed(reader.error?.localizedDescription ?? "unknown")
        }
        return samples
    }

    private func mux(videoURL: URL, audioURL: URL, outputURL: URL) async throws {
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let vAsset = AVURLAsset(url: videoURL)
        let aAsset = AVURLAsset(url: audioURL)

        guard let vTrack = try await vAsset.loadTracks(withMediaType: .video).first else {
            throw ProcessingError.noVideoTrack
        }
        guard let aTrack = try await aAsset.loadTracks(withMediaType: .audio).first else {
            throw ProcessingError.noAudioTrack
        }

        let composition = AVMutableComposition()
        guard
            let cVideo = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ),
            let cAudio = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        else { throw ProcessingError.writerFailed("composition") }

        let vDur = try await vAsset.load(.duration)
        let aDur = try await aAsset.load(.duration)
        try cVideo.insertTimeRange(CMTimeRange(start: .zero, duration: vDur), of: vTrack, at: .zero)
        let audioRange = CMTimeCompare(aDur, vDur) >= 0
            ? CMTimeRange(start: .zero, duration: vDur)
            : CMTimeRange(start: .zero, duration: aDur)
        try cAudio.insertTimeRange(audioRange, of: aTrack, at: .zero)

        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else { throw ProcessingError.writerFailed("exporter") }

        exporter.outputURL = outputURL
        exporter.outputFileType = .mp4
        exporter.shouldOptimizeForNetworkUse = true
        await exporter.export()

        guard exporter.status == .completed else {
            throw ProcessingError.writerFailed(exporter.error?.localizedDescription ?? "export failed")
        }
    }

    enum ProcessingError: LocalizedError {
        case noAudioTrack
        case noVideoTrack
        case readerFailed(String)
        case writerFailed(String)

        var errorDescription: String? {
            switch self {
            case .noAudioTrack: return "Video has no audio track"
            case .noVideoTrack: return "File has no video track"
            case .readerFailed(let m): return "Read failed: \(m)"
            case .writerFailed(let m): return "Write failed: \(m)"
            }
        }
    }
}
