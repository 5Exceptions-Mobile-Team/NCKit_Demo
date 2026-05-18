//
//  WavWriter.swift
//  NCKit Sample — built by 5Exceptions
//
//  Tiny helper for writing 16-bit PCM WAV files from Float32 samples.
//  Used by AudioEngine to persist recordings for sharing/playback.
//

import Foundation

enum WavWriter {

    enum WriteError: Error { case cannotCreate, cannotWrite }

    /// Write mono Float32 samples (-1...1) as 16-bit PCM WAV.
    static func write(samples: [Float], sampleRate: Int, to url: URL) throws {
        let numSamples = samples.count
        let bytesPerSample = 2
        let dataSize = numSamples * bytesPerSample
        let fileSize = 44 + dataSize

        var header = Data(capacity: 44)
        header.append(contentsOf: "RIFF".utf8)
        header.appendLE(UInt32(fileSize - 8))
        header.append(contentsOf: "WAVE".utf8)
        header.append(contentsOf: "fmt ".utf8)
        header.appendLE(UInt32(16))            // fmt chunk size
        header.appendLE(UInt16(1))             // PCM
        header.appendLE(UInt16(1))             // mono
        header.appendLE(UInt32(sampleRate))
        header.appendLE(UInt32(sampleRate * bytesPerSample))
        header.appendLE(UInt16(2))             // block align
        header.appendLE(UInt16(16))            // bits per sample
        header.append(contentsOf: "data".utf8)
        header.appendLE(UInt32(dataSize))

        guard FileManager.default.createFile(atPath: url.path, contents: header) else {
            throw WriteError.cannotCreate
        }
        guard let fh = try? FileHandle(forWritingTo: url) else { throw WriteError.cannotWrite }
        defer { try? fh.close() }
        fh.seekToEndOfFile()

        let chunkSize = 48_000
        var offset = 0
        while offset < numSamples {
            let end = min(offset + chunkSize, numSamples)
            var chunk = Data(capacity: (end - offset) * bytesPerSample)
            for i in offset..<end {
                let clamped = max(-1, min(1, samples[i]))
                let int16: Int16 = clamped < 0
                    ? Int16(clamped * 32_768)
                    : Int16(clamped * 32_767)
                chunk.appendLE(int16)
            }
            fh.write(chunk)
            offset = end
        }
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { self.append(contentsOf: $0) }
    }
}
