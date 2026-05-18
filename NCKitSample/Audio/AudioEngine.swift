//
//  AudioEngine.swift
//  NCKit Sample — built by 5Exceptions
//
//  Real-time microphone noise cancellation using NCKit (LibDFProcessor).
//
//  Integration recipe:
//    1. let modelURL = try DFN3ModelLocator.modelTarGzURL()
//    2. let processor = try LibDFProcessor(modelURL: modelURL)
//    3. For each 10 ms hop (480 samples @ 48 kHz mono Float32):
//         processor.processFrame(input: ptr, output: ptr)
//
//  This file shows the recommended pattern for live mic processing.
//

import AVFoundation
import Combine
import Foundation
import NCKit

@MainActor
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

    /// The single LibDFProcessor instance for real-time processing.
    /// Reusing one instance preserves GRU hidden state across frames.
    private var processor: LibDFProcessor?
    private var hopSize: Int = 480 // updated on load to processor.frameLength

    // MARK: - AVFoundation

    private let avEngine = AVAudioEngine()
    private var converterIn: AVAudioConverter?
    private var converterOut: AVAudioConverter?
    private var inputFormat: AVAudioFormat?
    private var ncFormat: AVAudioFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 48_000,
        channels: 1,
        interleaved: false
    )!

    /// Source node feeds the speaker from `outputRing`.
    private var srcNode: AVAudioSourceNode?

    // MARK: - Ring buffer for output

    private let outputRingCapacity = 48_000 // 1 s @ 48 kHz
    private var outputRing: [Float] = []
    private var outputReadPos = 0
    private var outputWritePos = 0
    private var outputAvailable = 0
    private let bufferLock = NSLock()

    // MARK: - Hop accumulator (incomplete frame buffer)

    private var hopAccumulator: [Float] = []

    // MARK: - Recording

    private var recordedOriginal: [Float] = []
    private var recordedEnhanced: [Float] = []
    private var recordStartDate: Date?

    // MARK: - Stats

    private var smoothedProcMs: Double = 0
    private let sampleRate: Double = 48_000

    init() {
        outputRing = [Float](repeating: 0, count: outputRingCapacity)
    }

    // MARK: - Model loading

    func loadModel() {
        status = .loading
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            do {
                // 1. NCKit ships the DeepFilterNet3 model inside the xcframework.
                //    DFN3ModelLocator finds it and materialises a usable URL.
                let modelURL = try DFN3ModelLocator.modelTarGzURL()

                // 2. Create the processor once. Reuse across all frames.
                //    attenLimDb = 100 (unlimited), postFilterBeta = 0 (off)
                //    are the deep-filter CLI defaults — start here.
                let processor = try LibDFProcessor(
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
            try avEngine.start()
            isRunning = true
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    func stop() {
        guard isRunning else { return }

        if isRecording { _ = stopRecording() }

        avEngine.inputNode.removeTap(onBus: 0)
        if let src = srcNode { avEngine.detach(src) }
        avEngine.stop()
        srcNode = nil

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

    private func setupGraph() throws {
        let input = avEngine.inputNode
        let hwFormat = input.outputFormat(forBus: 0)
        inputFormat = hwFormat

        // Converters between hardware format and 48 kHz mono Float32 (NCKit input).
        if hwFormat.sampleRate != sampleRate || hwFormat.channelCount != 1 {
            converterIn = AVAudioConverter(from: hwFormat, to: ncFormat)
        }

        let mainMixer = avEngine.mainMixerNode
        let mixerFormat = mainMixer.outputFormat(forBus: 0)
        if mixerFormat.sampleRate != sampleRate || mixerFormat.channelCount != ncFormat.channelCount {
            converterOut = AVAudioConverter(from: ncFormat, to: mixerFormat)
        }

        // Source node that pulls from our output ring buffer.
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

        // Tap mic input.
        input.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let samples = self.convertToMono48k(buffer)
            self.measureLevel(samples, channel: .input)
            self.handleInputSamples(samples)
        }
    }

    // MARK: - NC toggle and recording

    func setNCEnabled(_ enabled: Bool) { isNCEnabled = enabled }

    func startRecording() {
        guard isRunning, !isRecording else { return }
        recordedOriginal.removeAll(keepingCapacity: false)
        recordedEnhanced.removeAll(keepingCapacity: false)
        recordStartDate = Date()
        isRecording = true
    }

    /// Stop recording and return WAV URLs for original + enhanced.
    func stopRecording() -> (original: URL?, enhanced: URL?)? {
        guard isRecording else { return nil }
        isRecording = false

        let tempDir = FileManager.default.temporaryDirectory
        let stamp = Int(Date().timeIntervalSince1970)

        let origURL = tempDir.appendingPathComponent("nckit_original_\(stamp).wav")
        let enhURL = tempDir.appendingPathComponent("nckit_enhanced_\(stamp).wav")

        let origOK = (try? WavWriter.write(samples: recordedOriginal, sampleRate: Int(sampleRate), to: origURL)) != nil
        let enhOK = (try? WavWriter.write(samples: recordedEnhanced, sampleRate: Int(sampleRate), to: enhURL)) != nil

        return (origOK ? origURL : nil, enhOK ? enhURL : nil)
    }

    var recordingDuration: TimeInterval {
        guard let start = recordStartDate, isRecording else { return 0 }
        return Date().timeIntervalSince(start)
    }

    // MARK: - Frame processing

    /// Feed mic samples through LibDFProcessor 480 samples at a time.
    private func handleInputSamples(_ samples: [Float]) {
        if isRecording { recordedOriginal.append(contentsOf: samples) }

        bufferLock.lock()
        hopAccumulator.append(contentsOf: samples)

        while hopAccumulator.count >= hopSize {
            let inFrame = Array(hopAccumulator.prefix(hopSize))
            hopAccumulator.removeFirst(hopSize)
            bufferLock.unlock()

            let outFrame = processOneFrame(inFrame)

            // Push processed frame into output ring.
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

        if isRecording { /* recordedEnhanced appended inside processOneFrame */ }
    }

    /// Run one 10 ms hop through LibDFProcessor. This is the core NCKit call.
    private func processOneFrame(_ input: [Float]) -> [Float] {
        guard isNCEnabled, let processor else {
            if isRecording { recordedEnhanced.append(contentsOf: input) }
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

        if isRecording { recordedEnhanced.append(contentsOf: outBuf) }

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.smoothedProcMs = self.smoothedProcMs * 0.85 + elapsedMs * 0.15
            self.processingTimeMs = self.smoothedProcMs
            self.framesProcessed += 1
        }

        return outBuf
    }

    // MARK: - Format conversion

    private func convertToMono48k(_ buffer: AVAudioPCMBuffer) -> [Float] {
        guard let converter = converterIn else {
            // Already 48 kHz mono Float32.
            guard let data = buffer.floatChannelData?[0] else { return [] }
            return Array(UnsafeBufferPointer(start: data, count: Int(buffer.frameLength)))
        }

        let inputSR = buffer.format.sampleRate
        let frameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * sampleRate / inputSR + 64)

        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: ncFormat, frameCapacity: frameCapacity) else {
            return []
        }

        var error: NSError?
        var consumed = false
        let status = converter.convert(to: outBuffer, error: &error) { _, statusPtr in
            if consumed {
                statusPtr.pointee = .noDataNow
                return nil
            }
            consumed = true
            statusPtr.pointee = .haveData
            return buffer
        }
        guard status != .error, let data = outBuffer.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: data, count: Int(outBuffer.frameLength)))
    }

    // MARK: - Level metering

    private enum Channel { case input, output }

    private func measureLevel(_ samples: [Float], channel: Channel) {
        let db = rmsDb(samples)
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch channel {
            case .input: self.inputLevelDb = db
            case .output: self.outputLevelDb = db
            }
        }
    }

    private func measureLevel(_ pointer: UnsafeMutablePointer<Float>, count: Int, channel: Channel) {
        let buf = UnsafeBufferPointer(start: pointer, count: count)
        let db = rmsDb(Array(buf))
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch channel {
            case .input: self.inputLevelDb = db
            case .output: self.outputLevelDb = db
            }
        }
    }

    private func rmsDb(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return -100 }
        var sum: Float = 0
        for s in samples { sum += s * s }
        let rms = sqrtf(sum / Float(samples.count))
        return rms < 1e-10 ? -100 : 20 * log10f(rms)
    }
}
