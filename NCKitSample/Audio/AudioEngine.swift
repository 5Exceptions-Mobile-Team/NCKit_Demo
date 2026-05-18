//
//  AudioEngine.swift
//  NCKit Sample
//
//  Real-time microphone noise cancellation using NCKit (NCKitProcessor).
//

import AVFoundation
import Combine
import Foundation
import NCKit

final class AudioEngine: ObservableObject {

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

    private var processor: NCKitProcessor?
    private var hopSize: Int = 480

    // MARK: - AVFoundation

    private let avEngine = AVAudioEngine()
    private var converterIn: AVAudioConverter?
    private var converterOut: AVAudioConverter?
    private var ncFormat: AVAudioFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 48_000,
        channels: 1,
        interleaved: false
    )!

    private var srcNode: AVAudioSourceNode?
    private var isTapInstalled = false

    // MARK: - Ring buffer for output

    private let outputRingCapacity = 48_000
    private var outputRing: [Float] = []
    private var outputReadPos = 0
    private var outputWritePos = 0
    private var outputAvailable = 0
    private let bufferLock = NSLock()

    // MARK: - Hop accumulator

    private var hopAccumulator: [Float] = []

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
                    self.processor = processor
                    self.hopSize = processor.frameLength
                    self.hopAccumulator.reserveCapacity(processor.frameLength)
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
        guard !isRunning, processor != nil else { return }

        do {
            try configureAudioSession()
            try setupGraph()
            avEngine.prepare()
            try avEngine.start()
            try installMicTap()
            isRunning = true
            framesProcessed = 0
            startRecording()
        } catch {
            removeMicTapIfNeeded()
            isRunning = false
            status = .error(error.localizedDescription)
        }
    }

    @discardableResult
    func stop() -> (original: URL?, enhanced: URL?)? {
        guard isRunning else { return nil }

        let recorded = isCaptureActive ? stopRecording() : nil

        removeMicTapIfNeeded()
        if let src = srcNode { avEngine.detach(src) }
        avEngine.stop()
        srcNode = nil
        converterIn = nil
        converterOut = nil

        bufferLock.lock()
        outputRing = [Float](repeating: 0, count: outputRingCapacity)
        outputReadPos = 0
        outputWritePos = 0
        outputAvailable = 0
        hopAccumulator.removeAll(keepingCapacity: true)
        bufferLock.unlock()

        isRunning = false
        inputLevelDb = -100
        outputLevelDb = -100
        return recorded
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.defaultToSpeaker, .allowBluetoothA2DP]
        )
        try session.setPreferredSampleRate(sampleRate)
        try session.setPreferredIOBufferDuration(0.01)
        try session.setActive(true)
    }

    /// Build graph only — install the mic tap **after** `avEngine.start()` so formats are valid.
    private func setupGraph() throws {
        let input = avEngine.inputNode
        let mainMixer = avEngine.mainMixerNode
        let mixerFormat = mainMixer.outputFormat(forBus: 0)

        if mixerFormat.sampleRate != sampleRate || mixerFormat.channelCount != ncFormat.channelCount {
            converterOut = AVAudioConverter(from: ncFormat, to: mixerFormat)
        }

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
    }

    private func installMicTap() throws {
        guard !isTapInstalled else { return }

        let input = avEngine.inputNode
        let hwFormat = input.outputFormat(forBus: 0)
        let tapFormat: AVAudioFormat? = (hwFormat.sampleRate > 0 && hwFormat.channelCount > 0) ? hwFormat : nil

        if let tapFormat, tapFormat.sampleRate != sampleRate || tapFormat.channelCount != 1 {
            guard let converter = AVAudioConverter(from: tapFormat, to: ncFormat) else {
                throw NSError(
                    domain: "AudioEngine",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Could not create audio converter"]
                )
            }
            converterIn = converter
        } else {
            converterIn = nil
        }

        input.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let samples = self.convertToMono48k(buffer)
            guard !samples.isEmpty else { return }
            self.measureLevel(samples, channel: .input)
            self.handleInputSamples(samples)
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

    private func handleInputSamples(_ samples: [Float]) {
        recordingCapture.appendOriginal(samples)

        bufferLock.lock()
        hopAccumulator.append(contentsOf: samples)

        while hopAccumulator.count >= hopSize {
            let inFrame = Array(hopAccumulator.prefix(hopSize))
            hopAccumulator.removeFirst(hopSize)
            bufferLock.unlock()

            let outFrame = processOneFrame(inFrame)

            bufferLock.lock()
            for sample in outFrame {
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
    }

    private func processOneFrame(_ input: [Float]) -> [Float] {
        ncLock.lock()
        let ncOn = ncEnabled
        ncLock.unlock()

        guard ncOn, let processor else {
            recordingCapture.appendEnhanced(input)
            return input
        }

        var inBuf = input
        var outBuf = [Float](repeating: 0, count: hopSize)

        let t0 = CFAbsoluteTimeGetCurrent()
        inBuf.withUnsafeMutableBufferPointer { ib in
            outBuf.withUnsafeMutableBufferPointer { ob in
                if let ip = ib.baseAddress, let op = ob.baseAddress {
                    processor.processFrame(input: ip, output: op)
                }
            }
        }
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0

        recordingCapture.appendEnhanced(outBuf)

        publishOnMain {
            self.smoothedProcMs = self.smoothedProcMs * 0.85 + elapsedMs * 0.15
            self.processingTimeMs = self.smoothedProcMs
            self.framesProcessed += 1
        }

        return outBuf
    }

    private func convertToMono48k(_ buffer: AVAudioPCMBuffer) -> [Float] {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return [] }

        if buffer.format.channelCount > 1, converterIn == nil,
           let channels = buffer.floatChannelData {
            var mono = [Float](repeating: 0, count: frameCount)
            let chCount = Int(buffer.format.channelCount)
            for ch in 0..<chCount {
                let ptr = channels[ch]
                for i in 0..<frameCount {
                    mono[i] += ptr[i]
                }
            }
            let scale = 1 / Float(chCount)
            for i in 0..<frameCount { mono[i] *= scale }
            return mono
        }

        guard let converter = converterIn else {
            guard let data = buffer.floatChannelData?[0] else { return [] }
            return Array(UnsafeBufferPointer(start: data, count: frameCount))
        }

        let inputSR = buffer.format.sampleRate
        guard inputSR > 0 else { return [] }

        let frameCapacity = AVAudioFrameCount(
            Double(buffer.frameLength) * sampleRate / inputSR + 64
        )

        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: ncFormat, frameCapacity: frameCapacity) else {
            return []
        }

        var error: NSError?
        var consumed = false
        let inputCopy = buffer
        let status = converter.convert(to: outBuffer, error: &error) { _, statusPtr in
            if consumed {
                statusPtr.pointee = .noDataNow
                return nil
            }
            consumed = true
            statusPtr.pointee = .haveData
            return inputCopy
        }

        guard status != .error, error == nil else { return [] }
        let frames = Int(outBuffer.frameLength)
        guard frames > 0, let data = outBuffer.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: data, count: frames))
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
