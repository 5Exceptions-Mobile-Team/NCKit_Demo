//
//  HowToUseView.swift
//  NCKit Sample — built by 5Exceptions
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
                            text: "NCKit ships the DeepFilterNet3 model inside the xcframework. DFN3ModelLocator returns a usable URL — no path required.",
                            code: """
                            import NCKit

                            let modelURL = try DFN3ModelLocator.modelTarGzURL()
                            """
                        )

                        SnippetCard(
                            title: "2. Create the processor once",
                            text: "LibDFProcessor holds the GRU state and the loaded model. Create it once on a background thread and reuse it.",
                            code: """
                            let processor = try LibDFProcessor(
                                modelURL: modelURL,
                                attenLimDb: 100,      // 100 = unlimited
                                postFilterBeta: 0     // 0 = off (CLI default)
                            )
                            """
                        )

                        SnippetCard(
                            title: "3. Real-time mic processing",
                            text: "Feed exactly processor.frameLength samples (480 = 10 ms @ 48 kHz mono). Call from a serial queue.",
                            code: """
                            let hop = processor.frameLength
                            var input  = [Float](repeating: 0, count: hop)
                            var output = [Float](repeating: 0, count: hop)

                            input.withUnsafeMutableBufferPointer { ib in
                                output.withUnsafeMutableBufferPointer { ob in
                                    processor.processFrame(
                                        input:  ib.baseAddress!,
                                        output: ob.baseAddress!
                                    )
                                }
                            }
                            """
                        )

                        SnippetCard(
                            title: "4. Offline file processing",
                            text: "DFN3FileProcessor streams the whole file in one call. Works for any AVFoundation-readable input.",
                            code: """
                            try DFN3FileProcessor.processFile(
                                inputURL:  noisyFile,
                                outputURL: cleanFile,
                                processor: processor
                            )
                            """
                        )

                        SnippetCard(
                            title: "5. Loudness normalization",
                            text: "After denoising, speech can sound quieter. DFN3AudioNormalizer applies speech-gated makeup gain with a tanh soft limiter.",
                            code: """
                            var samples: [Float] = readSamples()

                            DFN3AudioNormalizer.applySpeechGatedMakeupGain(
                                &samples,
                                sampleRate: 48_000,
                                targetRmsDbfs: -18
                            )
                            """
                        )

                        SnippetCard(
                            title: "6. Handle errors",
                            text: "Every NCKit operation throws DFN3Error — a typed, Sendable enum. Catch the cases that matter.",
                            code: """
                            do {
                                let processor = try LibDFProcessor(modelURL: modelURL)
                            } catch DFN3Error.missingModel(let name) {
                                print("Model not embedded: \\(name)")
                            } catch DFN3Error.libraryInit {
                                print("Engine init failed")
                            } catch {
                                print(error)
                            }
                            """
                        )

                        docsLinks
                        FiveExceptionsFooter()
                    }
                    .padding()
                }
            }
            .navigationTitle("How to Use NCKit")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.hidden, for: .navigationBar)
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
            linkRow(label: "Sample on GitHub", icon: "chevron.left.forwardslash.chevron.right", urlString: "https://github.com/5Exceptions-Mobile-Team/NCKit_Demo")
            linkRow(label: "5Exceptions", icon: "globe", urlString: "https://5exceptions.com")
            linkRow(label: "Contact sales", icon: "envelope", urlString: "mailto:sdk@5exceptions.com")
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
