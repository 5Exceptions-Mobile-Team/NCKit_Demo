//
//  ContentView.swift
//  NCKit Sample — built by 5Exceptions
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            AudioView()
                .tabItem { Label("Audio", systemImage: "waveform") }

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
