import Foundation

/// Generates downsampled waveform data for rendering.
enum WaveformGenerator {

    struct WaveformPoint {
        let min: Float
        let max: Float
    }

    /// Downsample audio samples to min/max envelope pairs for the given width.
    /// - Parameters:
    ///   - samples: Full audio buffer (Float32)
    ///   - width: Number of points to generate (typically view width in points)
    /// - Returns: Array of min/max pairs, one per column
    static func generate(from samples: [Float], width: Int) -> [WaveformPoint] {
        guard !samples.isEmpty, width > 0 else { return [] }

        var points = [WaveformPoint]()
        points.reserveCapacity(width)

        for i in 0..<width {
            let start = i * samples.count / width
            let end = min((i + 1) * samples.count / width, samples.count)

            guard start < end else {
                points.append(WaveformPoint(min: 0, max: 0))
                continue
            }

            var lo: Float = samples[start]
            var hi: Float = samples[start]

            // For efficiency, stride through samples
            let step = max(1, (end - start) / 64) // at most 64 samples per point
            var j = start
            while j < end {
                let v = samples[j]
                if v < lo { lo = v }
                if v > hi { hi = v }
                j += step
            }

            points.append(WaveformPoint(min: lo, max: hi))
        }

        return points
    }
}
