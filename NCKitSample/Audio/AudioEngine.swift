//
//  AudioEngine.swift
//  NCKit Sample
//
//  Real-time microphone noise cancellation using NCKitStreamProcessor.
//

import AVFoundation
import Combine
import Foundation
import NCKit
import os

final class AudioEngine: ObservableObject {

    private static let log = Logger(subsystem: "com.fiveexceptions.nckitsample", category: "AudioEngine")

    // MARK: - Published state for SwiftUI

    @Published private(set) var isRunning = false
    @Published private(set) var isRecording = false
    @Published private(set) var isNCEnabled = true
    @Published private(set) var inputLevelDb: Float = -100
    @Published private(set) var outputLevelDb: Float = -100
    @Published private(set) var processingTimeMs: Double = 0
    @Published private(set) var framesProcessed: Int = 0
    @Published private(set) var status: Status = .loading

    enum Status: Equatable {
        case loading
        case ready
        case error(String)
    }

    // MARK: - NCKit

    private var ncProcessor: NCKitProcessor?
    private var streamProcessor: NCKitStreamProcessor?

    // MARK: - AVFoundation

    private let avEngine = AVAudioEngine()
    private var ncFormat: AVAudioFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 48_000,
        channels: 1,
        interleaved: false
    )!

    private var srcNode: AVAudioSourceNode?
    /// Drives the input node so HW format is non-zero; volume 0 avoids dry-mic bleed to speakers.
    private var inputMixer: AVAudioMixerNode?
    private var isTapInstalled = false
    private var reportedTapError = false

    // MARK: - Ring buffer for output

    private let outputRingCapacity = 48_000
    private var outputRing: [Float] = []
    private var outputReadPos = 0
    private var outputWritePos = 0
    private var outputAvailable = 0
    private let bufferLock = NSLock()

    // MARK: - Recording (thread-safe — mic tap runs on audio thread)

    private let recordingCapture = RecordingCapture()
    private var isCaptureActive = false
    private var recordStartDate: Date?

    private let ncLock = NSLock()
    private var ncEnabled = true

    private var smoothedProcMs: Double = 0
    private let sampleRate: Double = 48_000

    /// True while A/B capture is active (use for UI; updated synchronously on main).
    var isCapturing: Bool { isCaptureActive }

    init() {
        outputRing = [Float](repeating: 0, count: outputRingCapacity)
    }

    // MARK: - Model loading

    func loadModel() {
        publishOnMain { self.status = .loading }
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let modelURL = try NCKitModelLocator.modelTarGzURL()
                let processor = try NCKitProcessor(
                    modelURL: modelURL,
                    attenLimDb: 100,
                    postFilterBeta: 0
                )

                await MainActor.run {
                    self.ncProcessor = processor
                    self.streamProcessor = NCKitStreamProcessor(processor: processor)
                    self.status = .ready
                }
            } catch {
                await MainActor.run {
                    self.status = .error(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Start / stop

    func start() {
        guard !isRunning, let ncProcessor else { return }

        do {
            teardownAudioGraph()

            streamProcessor = NCKitStreamProcessor(processor: ncProcessor)
            reportedTapError = false

            try configureAudioSession()
            try setupGraph()
            avEngine.prepare()
            try installMicTap()
            try avEngine.start()

            isRunning = true
            framesProcessed = 0
            status = .ready
            startRecording()
        } catch {
            teardownAudioGraph()
            isRunning = false
            status = .error(error.localizedDescription)
            Self.log.error("Failed to start audio engine: \(error.localizedDescription, privacy: .public)")
        }
    }

    @discardableResult
    func stop() -> (original: URL?, enhanced: URL?)? {
        guard isRunning else { return nil }

        let recorded = isCaptureActive ? stopRecording() : nil
        teardownAudioGraph()

        bufferLock.lock()
        outputRing = [Float](repeating: 0, count: outputRingCapacity)
        outputReadPos = 0
        outputWritePos = 0
        outputAvailable = 0
        bufferLock.unlock()

        streamProcessor?.reset()
        streamProcessor = nil
        isRunning = false
        inputLevelDb = -100
        outputLevelDb = -100
        if ncProcessor != nil {
            status = .ready
        }
        return recorded
    }

    // MARK: - Audio graph lifecycle

    /// Fully tear down taps, nodes, and engine state so a second `start()` is safe.
    private func teardownAudioGraph() {
        removeMicTapIfNeeded()

        if let src = srcNode {
            avEngine.disconnectNodeOutput(src)
            avEngine.detach(src)
        }
        srcNode = nil

        if let inputMixer {
            avEngine.disconnectNodeInput(inputMixer)
            avEngine.disconnectNodeOutput(avEngine.inputNode)
            avEngine.detach(inputMixer)
        }
        inputMixer = nil

        if avEngine.isRunning {
            avEngine.stop()
        }
        avEngine.reset()
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        // Use .allowBluetooth (HFP) for mic — .allowBluetoothA2DP can break the input chain.
        try session.setCategory(
            .playAndRecord,
            mode: .measurement,
            options: [.defaultToSpeaker, .allowBluetooth]
        )
        try session.setPreferredSampleRate(sampleRate)
        try session.setPreferredIOBufferDuration(0.01)
        try session.setActive(true)
    }

    private func setupGraph() throws {
        let mainMixer = avEngine.mainMixerNode
        let input = avEngine.inputNode

        // Connect mic into the graph so input HW format is initialized (not 0 Hz).
        // inputMixer is not wired to mainMixer — only denoised srcNode is heard.
        let im = AVAudioMixerNode()
        inputMixer = im
        avEngine.attach(im)
        avEngine.connect(input, to: im, format: nil)
        im.outputVolume = 0

        let src = AVAudioSourceNode(format: ncFormat) { [weak self] _, _, frameCount, ablPointer in
            guard let self else { return noErr }
            let buffers = UnsafeMutableAudioBufferListPointer(ablPointer)
            let count = Int(frameCount)
            guard let dst = buffers[0].mData?.assumingMemoryBound(to: Float.self) else { return noErr }

            self.bufferLock.lock()
            let available = self.outputAvailable
            for i in 0..<count {
                if i < available {
                    dst[i] = self.outputRing[self.outputReadPos]
                    self.outputReadPos = (self.outputReadPos + 1) % self.outputRingCapacity
                } else {
                    dst[i] = 0
                }
            }
            self.outputAvailable = max(0, available - count)
            self.bufferLock.unlock()

            self.measureLevel(dst, count: count, channel: .output)
            return noErr
        }

        srcNode = src
        avEngine.attach(src)
        avEngine.connect(src, to: mainMixer, format: ncFormat)
        mainMixer.outputVolume = 1.0
    }

    private func installMicTap() throws {
        guard !isTapInstalled else { return }

        let input = avEngine.inputNode
        let hwFormat = input.outputFormat(forBus: 0)

        // installTap format must match HW format exactly — nil fails when HW is still 0 Hz.
        guard hwFormat.sampleRate > 0, hwFormat.channelCount > 0 else {
            throw NSError(
                domain: "AudioEngine",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey:
                    "Microphone not available (0 Hz format). Use a physical iPhone and allow microphone access."]
            )
        }

        try streamProcessor?.prepare(inputFormat: hwFormat)

        input.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.handleTapBuffer(buffer)
        }
        isTapInstalled = true
    }

    private func removeMicTapIfNeeded() {
        guard isTapInstalled else { return }
        avEngine.inputNode.removeTap(onBus: 0)
        isTapInstalled = false
    }

    // MARK: - NC toggle and recording

    func setNCEnabled(_ enabled: Bool) {
        ncLock.lock()
        ncEnabled = enabled
        ncLock.unlock()
        isNCEnabled = enabled
    }

    func startRecording() {
        guard isRunning, !isCaptureActive else { return }
        isCaptureActive = true
        isRecording = true
        recordingCapture.begin()
        recordStartDate = Date()
    }

    func stopRecording() -> (original: URL?, enhanced: URL?)? {
        guard isCaptureActive else { return nil }
        isCaptureActive = false
        isRecording = false

        let (origSamples, enhSamples) = recordingCapture.end()
        recordStartDate = nil

        guard !origSamples.isEmpty else {
            return (nil, nil)
        }

        let exportDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NCKitRecordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)

        let stamp = Int(Date().timeIntervalSince1970)
        let origURL = exportDir.appendingPathComponent("nckit_original_\(stamp).wav")
        let enhURL = exportDir.appendingPathComponent("nckit_enhanced_\(stamp).wav")

        let origOK = (try? WavWriter.write(samples: origSamples, sampleRate: Int(sampleRate), to: origURL)) != nil
        let enhSamplesToWrite = enhSamples.isEmpty ? origSamples : enhSamples
        let enhOK = (try? WavWriter.write(samples: enhSamplesToWrite, sampleRate: Int(sampleRate), to: enhURL)) != nil

        return (origOK ? origURL : nil, enhOK ? enhURL : nil)
    }

    var recordingDuration: TimeInterval {
        guard let start = recordStartDate, isCaptureActive else { return 0 }
        return Date().timeIntervalSince(start)
    }

    // MARK: - Frame processing (audio thread)

    private func handleTapBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let streamProcessor else { return }

        do {
            try streamProcessor.prepare(inputFormat: buffer.format)
            let dry = try streamProcessor.convertToTargetFormat(buffer)
            guard !dry.isEmpty else { return }

            measureLevel(dry, channel: .input)
            recordingCapture.appendOriginal(dry)

            ncLock.lock()
            let ncOn = ncEnabled
            ncLock.unlock()

            let outFrames: [[Float]]
            if ncOn {
                let t0 = CFAbsoluteTimeGetCurrent()
                outFrames = try streamProcessor.processConverted(dry)
                let elapsedMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0
                publishOnMain {
                    self.smoothedProcMs = self.smoothedProcMs * 0.85 + elapsedMs * 0.15
                    self.processingTimeMs = self.smoothedProcMs
                    self.framesProcessed += outFrames.count
                }
            } else {
                outFrames = chunk(dry, hop: streamProcessor.frameLength)
            }

            bufferLock.lock()
            for frame in outFrames {
                recordingCapture.appendEnhanced(frame)
                for sample in frame {
                    outputRing[outputWritePos] = sample
                    outputWritePos = (outputWritePos + 1) % outputRingCapacity
                    if outputAvailable < outputRingCapacity {
                        outputAvailable += 1
                    } else {
                        outputReadPos = (outputReadPos + 1) % outputRingCapacity
                    }
                }
            }
            bufferLock.unlock()
        } catch {
            Self.log.error("Tap processing failed: \(error.localizedDescription, privacy: .public)")
            if !reportedTapError {
                reportedTapError = true
                publishOnMain {
                    self.status = .error("Mic processing failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func chunk(_ samples: [Float], hop: Int) -> [[Float]] {
        guard hop > 0, !samples.isEmpty else { return [] }
        var frames: [[Float]] = []
        var idx = 0
        while idx + hop <= samples.count {
            frames.append(Array(samples[idx..<(idx + hop)]))
            idx += hop
        }
        return frames
    }

    // MARK: - Level metering

    private enum Channel { case input, output }

    private func measureLevel(_ samples: [Float], channel: Channel) {
        let db = rmsDb(samples)
        publishOnMain {
            switch channel {
            case .input: self.inputLevelDb = db
            case .output: self.outputLevelDb = db
            }
        }
    }

    private func measureLevel(_ pointer: UnsafeMutablePointer<Float>, count: Int, channel: Channel) {
        let buf = UnsafeBufferPointer(start: pointer, count: count)
        measureLevel(Array(buf), channel: channel)
    }

    private func rmsDb(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return -100 }
        var sum: Float = 0
        for s in samples { sum += s * s }
        let rms = sqrtf(sum / Float(samples.count))
        return rms < 1e-10 ? -100 : 20 * log10f(rms)
    }

    private func publishOnMain(_ update: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated(update)
        } else {
            Task { @MainActor in update() }
        }
    }
}

// MARK: - Thread-safe recording buffers

private final class RecordingCapture: @unchecked Sendable {
    private var active = false
    private var original: [Float] = []
    private var enhanced: [Float] = []
    private let lock = NSLock()

    func begin() {
        lock.lock()
        active = true
        original.removeAll(keepingCapacity: true)
        enhanced.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    func appendOriginal(_ samples: [Float]) {
        lock.lock()
        if active { original.append(contentsOf: samples) }
        lock.unlock()
    }

    func appendEnhanced(_ samples: [Float]) {
        lock.lock()
        if active { enhanced.append(contentsOf: samples) }
        lock.unlock()
    }

    func end() -> (original: [Float], enhanced: [Float]) {
        lock.lock()
        active = false
        let capturedOriginal = original
        let capturedEnhanced = enhanced
        original = []
        enhanced = []
        lock.unlock()
        return (capturedOriginal, capturedEnhanced)
    }
}
