//
//  VideoImportView.swift
//  NCKit Sample
//
//  Demonstrates NCKitFileProcessor for offline video noise cancellation.
//

import AVFoundation
import SwiftUI

struct VideoImportView: View {

    @StateObject private var processor = VideoProcessor()
    @State private var showPhotoPicker = false
    @State private var showDocumentPicker = false
    @State private var showComparison = false
    @State private var processingTask: Task<Void, Never>?
    @State private var showSaveSuccess = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            ZStack {
                AIBackground()
                mainContent
                if shouldShowOverlay { processingOverlay }
            }
            .navigationTitle("Video NC")
            .navigationBarTitleDisplayMode(.large)
            .glassNavigationChrome()
            .sheet(isPresented: $showPhotoPicker) {
                PhotoPickerView(
                    onPick: { url in startProcessing(url: url) },
                    onFailure: { message in
                        VideoImportLogger.error("Photo picker failed: \(message)")
                        errorMessage = message
                        showError = true
                    }
                )
            }
            .sheet(isPresented: $showDocumentPicker) {
                DocumentPickerView(
                    onPick: { url in startProcessing(url: url) },
                    onFailure: { message in
                        VideoImportLogger.error("Document picker failed: \(message)")
                        errorMessage = message
                        showError = true
                    }
                )
            }
            .navigationDestination(isPresented: $showComparison) {
                if let result = processor.result {
                    ComparisonPlayerView(result: result) {
                        Task {
                            do {
                                try await processor.saveToPhotos()
                                showSaveSuccess = true
                            } catch {
                                errorMessage = error.localizedDescription
                                showError = true
                            }
                        }
                    }
                }
            }
            .alert("Saved", isPresented: $showSaveSuccess) { Button("OK") {} } message: {
                Text("Enhanced video saved to Photos.")
            }
            .alert("Error", isPresented: $showError) { Button("OK") {} } message: {
                Text(errorMessage)
            }
            .onChange(of: processor.phase) { _, newPhase in
                if case .complete = newPhase { showComparison = true }
                if case .error(let msg) = newPhase {
                    errorMessage = msg
                    showError = true
                }
            }
        }
    }

    private var shouldShowOverlay: Bool {
        switch processor.phase {
        case .idle, .complete, .error: return false
        default: return true
        }
    }

    // MARK: - Main content

    private var mainContent: some View {
        ScrollView {
            VStack(spacing: 26) {
                Spacer(minLength: 16)
                heroIcon
                heroText

                VStack(spacing: 12) {
                    sourceButton(
                        title: "Photo Library",
                        icon: "photo.on.rectangle",
                        description: "Camera roll (4K supported — may download from iCloud)"
                    ) {
                        VideoImportLogger.info("User tapped Photo Library")
                        showPhotoPicker = true
                    }

                    sourceButton(
                        title: "Files",
                        icon: "folder",
                        description: "Browse MP4, MOV, M4V"
                    ) { showDocumentPicker = true }
                }
                .padding(.horizontal)

                HStack(spacing: 8) {
                    Pill(text: "MP4", tinted: true)
                    Pill(text: "MOV", tinted: true)
                    Pill(text: "M4V", tinted: true)
                }

                SampleAppFooter()
                Spacer(minLength: 12)
            }
            .padding(.horizontal)
        }
    }

    private var heroIcon: some View {
        ZStack {
            Circle()
                .fill(AITheme.aiGradient.opacity(0.35))
                .frame(width: 130, height: 130)
                .blur(radius: 30)
            Image(systemName: "video.badge.waveform")
                .font(.system(size: 60, weight: .light))
                .foregroundStyle(AITheme.aiTextGradient)
        }
    }

    private var heroText: some View {
        VStack(spacing: 6) {
            GradientText(text: "Denoise a Video", font: .title2.weight(.bold))
            Text("NCKit extracts the audio, runs NCKit on-device, and mixes the clean track back in.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
    }

    private func sourceButton(title: String, icon: String, description: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(AITheme.aiGradient.opacity(0.18))
                        .frame(width: 48, height: 48)
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(AITheme.aiTextGradient)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.white)
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.white.opacity(0.4))
            }
            .glassCard()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Processing overlay

    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()

            VStack(spacing: 22) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.10), lineWidth: 6)
                        .frame(width: 100, height: 100)
                    Circle()
                        .trim(from: 0, to: processor.progress)
                        .stroke(
                            AITheme.aiGradient,
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .frame(width: 100, height: 100)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.3), value: processor.progress)
                    Text("\(Int(processor.progress * 100))%")
                        .font(.title2.monospacedDigit().weight(.bold))
                        .foregroundStyle(AITheme.aiTextGradient)
                }

                Text(processor.phase.label)
                    .font(.headline)
                    .foregroundColor(.white)

                HStack(spacing: 8) {
                    phaseDot("Extract", active: processor.phase == .extracting, done: processor.progress > 0.2)
                    phaseDot("Denoise", active: processor.phase == .processing, done: processor.progress > 0.7)
                    phaseDot("Remux",   active: processor.phase == .remuxing,   done: processor.progress >= 1.0)
                }

                Button("Cancel") {
                    processingTask?.cancel()
                    processor.reset()
                }
                .foregroundColor(.white.opacity(0.7))
                .padding(.top, 4)
            }
            .padding(36)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(AITheme.aiGradient.opacity(0.4), lineWidth: 1)
            )
        }
        .transition(.opacity)
    }

    private func phaseDot(_ label: String, active: Bool, done: Bool) -> some View {
        VStack(spacing: 4) {
            Circle()
                .fill(done ? AITheme.cyan : (active ? AITheme.violet : Color.white.opacity(0.15)))
                .frame(width: 10, height: 10)
                .shadow(color: (done || active) ? AITheme.cyan.opacity(0.7) : .clear, radius: 4)
            Text(label).font(.caption2).foregroundColor(.white.opacity(0.65))
        }
    }

    private func startProcessing(url: URL) {
        VideoImportLogger.fileSummary(url: url, label: "Starting processing")
        processingTask = Task { await processor.processVideo(at: url) }
    }
}

#Preview {
    VideoImportView()
        .preferredColorScheme(.dark)
}
