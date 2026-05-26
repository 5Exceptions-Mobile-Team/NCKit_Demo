//
//  HowToUseView.swift
//  NCKit Sample
//
//  Copy-paste code snippets that show how to integrate NCKit in your own app.
//

import SwiftUI

struct HowToUseView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                AIBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        intro

                        SnippetCard(
                            title: "1. Locate the bundled model",
                            text: "NCKit ships the NCKit model inside the xcframework. NCKitModelLocator returns a usable URL — no path required.",
                            code: """
                            import NCKit

                            let modelURL = try NCKitModelLocator.modelTarGzURL()
                            """
                        )

                        SnippetCard(
                            title: "2. Create the processor once",
                            text: "NCKitProcessor holds the GRU state and the loaded model. Create it once on a background thread and reuse it.",
                            code: """
                            let processor = try NCKitProcessor(
                                modelURL: modelURL,
                                attenLimDb: 100,      // 100 = unlimited
                                postFilterBeta: 0     // 0 = off (CLI default)
                            )
                            """
                        )

                        SnippetCard(
                            title: "3. Real-time mic processing",
                            text: "Pass AVAudioEngine tap buffers to NCKitStreamProcessor — resampling and 480-sample framing are handled in the SDK.",
                            code: """
                            import AVFoundation

                            let stream = NCKitStreamProcessor(processor: processor)

                            inputNode.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { buffer, _ in
                                try stream.prepare(inputFormat: buffer.format)
                                let frames = try stream.process(buffer: buffer)
                                // each frame: 480 samples @ 48 kHz mono
                            }
                            """
                        )

                        SnippetCard(
                            title: "4. Offline file processing",
                            text: "NCKitFileProcessor streams the whole file in one call. Works for any AVFoundation-readable input.",
                            code: """
                            try NCKitFileProcessor.processFile(
                                inputURL:  noisyFile,
                                outputURL: cleanFile,
                                processor: processor
                            )
                            """
                        )

                        SnippetCard(
                            title: "5. Loudness normalization",
                            text: "After denoising, speech can sound quieter. NCKitAudioNormalizer applies speech-gated makeup gain with a tanh soft limiter.",
                            code: """
                            var samples: [Float] = readSamples()

                            NCKitAudioNormalizer.applySpeechGatedMakeupGain(
                                &samples,
                                sampleRate: 48_000,
                                targetRmsDbfs: -18
                            )
                            """
                        )

                        SnippetCard(
                            title: "6. Handle errors",
                            text: "Every NCKit operation throws NCKitError — a typed, Sendable enum. Catch the cases that matter.",
                            code: """
                            do {
                                let processor = try NCKitProcessor(modelURL: modelURL)
                            } catch NCKitError.missingModel(let name) {
                                print("Model not embedded: \\(name)")
                            } catch NCKitError.libraryInit {
                                print("Engine init failed")
                            } catch {
                                print(error)
                            }
                            """
                        )

                        docsLinks
                        SampleAppFooter()
                    }
                    .padding()
                }
            }
            .navigationTitle("How to Use NCKit")
            .navigationBarTitleDisplayMode(.large)
            .glassNavigationChrome()
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.subheadline)
                    .foregroundStyle(AITheme.aiTextGradient)
                Text("Enterprise on-device noise cancellation for iOS.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.75))
            }

            HStack(spacing: 6) {
                Pill(text: "iOS 16+", tinted: true)
                Pill(text: "Swift 5.9+")
                Pill(text: "arm64")
                Pill(text: "on-device")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var docsLinks: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("More Resources")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
            linkRow(label: "Documentation", icon: "doc.text", urlString: "https://docs.nckit.io")
            linkRow(label: "SDK repository", icon: "chevron.left.forwardslash.chevron.right", urlString: "https://github.com/5Exceptions-Mobile-Team/NCKit")
        }
        .glassCard()
    }

    private func linkRow(label: String, icon: String, urlString: String) -> some View {
        Group {
            if let url = URL(string: urlString) {
                Link(destination: url) {
                    HStack(spacing: 12) {
                        Image(systemName: icon)
                            .frame(width: 22)
                            .foregroundStyle(AITheme.aiTextGradient)
                        Text(label)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.85))
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
            }
        }
    }
}

// MARK: - Snippet card

struct SnippetCard: View {
    let title: String
    let text: String
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.65))

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(AITheme.cyan)
                    .padding(12)
                    .frame(minWidth: 0, alignment: .leading)
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.35))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(AITheme.cyan.opacity(0.20), lineWidth: 1)
            )
        }
        .glassCard()
    }
}

#Preview {
    HowToUseView()
        .preferredColorScheme(.dark)
}
