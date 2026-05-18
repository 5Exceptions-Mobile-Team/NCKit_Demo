//
//  ContentView.swift
//  NCKit Sample — built by 5Exceptions
//
//  Root tab view. Each tab demonstrates a different NCKit integration:
//    • Microphone — real-time per-frame processing with LibDFProcessor
//    • Video      — offline file processing with DFN3FileProcessor
//    • How to Use — code snippets to copy into your own app
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            MicrophoneView()
                .tabItem { Label("Microphone", systemImage: "mic.fill") }

            VideoImportView()
                .tabItem { Label("Video", systemImage: "video.fill") }

            HowToUseView()
                .tabItem { Label("How to Use", systemImage: "doc.text.fill") }
        }
        .tint(AITheme.cyan)
    }
}

// MARK: - 5Exceptions branding footer

struct FiveExceptionsFooter: View {
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(AITheme.aiTextGradient)
                GradientText(text: "Powered by NCKit", font: .caption2.weight(.bold))
            }
            Text("Built by 5Exceptions • All processing on-device")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.55))
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    ContentView()
        .preferredColorScheme(.dark)
}
