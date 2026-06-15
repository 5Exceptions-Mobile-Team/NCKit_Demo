//
//  AudioView.swift
//  NCKit Sample
//
//  Real-time mic noise cancellation + offline file import + A/B playback.
//

import AVFAudio
import SwiftUI

struct AudioView: View {

    @StateObject private var engine = AudioEngine()
    @StateObject private var offlineProcessor = OfflineAudioProcessor()
    @EnvironmentObject private var playback: WavPlaybackController

    @State private var originalURL: URL?
    @State private var enhancedURL: URL?
    @State private var recordingNotice: String?
    @State private var showMicPermissionAlert = false
    @State private var showAudioImporter = false
    @State private var importTask: Task<Void, Never>?
    @State private var showImportError = false
    @State private var importErrorMessage = ""

    var body: some View {
        CompatibleNavigation {
            ZStack {
                AIBackground()

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 18) {
                            header
                            statusBadge
                            importSection
                            micButton
                            toggleCard
                            metersCard
                            if engine.isRunning { statsCard }
                            recordingCard
                            listenExportSection
                                .id("playback")
                            SampleAppFooter()
                        }
                        .padding()
                    }
                    .onChange(of: originalURL) { _ in scrollToPlayback(proxy) }
                    .onChange(of: enhancedURL) { _ in scrollToPlayback(proxy) }
                    .onChange(of: recordingNotice) { notice in
                        if notice != nil { scrollToPlayback(proxy) }
                    }
                }

                if offlineProcessor.phase == .processing {
                    processingOverlay
                }
            }
            .navigationTitle("NCKit Sample")
            .navigationBarTitleDisplayMode(.large)
            .glassNavigationChrome()
        }
        .onAppear { engine.loadModel() }
        .onDisappear {
            playback.stop()
            importTask?.cancel()
        }
        .sheet(isPresented: $showAudioImporter) {
            AudioDocumentPickerView(onPick: { url in
                startImport(url: url)
            })
        }
        .alert("Microphone Access", isPresented: $showMicPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("NCKit Sample needs microphone access. Enable it in Settings.")
        }
        .alert("Import Error", isPresented: $showImportError) {
            Button("OK") {}
        } message: {
            Text(importErrorMessage)
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Pill(text: "iOS 15+", tinted: true)
                Pill(text: "on-device")
                Pill(text: "NCKit")
            }
            GradientText(text: "Real-Time Noise Cancellation",
                         font: .title3.weight(.bold))
            Text("Record from the mic or import an audio file, then compare original vs NCKit-enhanced output.")
                .font(.caption)
                .foregroundColor(.white.opacity(0.65))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var importSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Import audio file")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)

            Button {
                playback.stop()
                showAudioImporter = true
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "doc.badge.plus")
                        .font(.title3)
                        .foregroundStyle(AITheme.aiTextGradient)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Choose from Files")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text("WAV, M4A, MP3, AAC, CAF")
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
            .disabled(offlineProcessor.phase == .processing || engine.isRunning)
        }
    }

    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(AITheme.cyan)
                Text(offlineProcessor.phase.label)
                    .font(.headline)
                    .foregroundColor(.white)
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 8) {
            Circle().fill(statusColor).frame(width: 8, height: 8)
                .shadow(color: statusColor.opacity(0.8), radius: 6)
            Text(statusText)
                .font(.caption.weight(.medium))
                .foregroundColor(.white.opacity(0.75))
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
    }

    private var statusColor: Color {
        switch engine.status {
        case .loading: return .orange
        case .ready:   return engine.isRunning ? AITheme.cyan : AITheme.violet
        case .error:   return .red
        }
    }

    private var statusText: String {
        switch engine.status {
        case .loading:        return "Loading NCKit model..."
        case .ready:          return engine.isRunning ? "Processing audio" : "Ready"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    private var micButton: some View {
        Button(action: toggleMic) {
            ZStack {
                Circle()
                    .fill(AITheme.aiGradient.opacity(engine.isRunning ? 0.45 : 0.22))
                    .frame(width: 150, height: 150)
                    .blur(radius: 18)
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 140, height: 140)
                    .overlay(
                        Circle().strokeBorder(
                            AITheme.aiGradient,
                            lineWidth: engine.isRunning ? 3 : 1.5
                        )
                    )
                VStack(spacing: 6) {
                    Image(systemName: engine.isRunning ? "mic.fill" : "mic")
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(AITheme.aiTextGradient)
                    Text(engine.isRunning ? "Tap to stop" : "Tap to start")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.70))
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(engine.status == .loading || offlineProcessor.phase == .processing)
    }

    private var toggleCard: some View {
        HStack {
            Text("Noise Cancellation")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
            Spacer()
            Toggle("", isOn: Binding(
                get: { engine.isNCEnabled },
                set: { engine.setNCEnabled($0) }
            ))
            .labelsHidden()
            .tint(AITheme.cyan)
            Text(engine.isNCEnabled ? "ON" : "OFF")
                .font(.caption.weight(.bold))
                .foregroundColor(engine.isNCEnabled ? AITheme.cyan : .white.opacity(0.5))
        }
        .glassCard()
    }

    private var metersCard: some View {
        VStack(spacing: 14) {
            meterRow(label: "Input", db: engine.inputLevelDb)
            meterRow(label: "Output", db: engine.outputLevelDb)
        }
        .glassCard()
    }

    private func meterRow(label: String, db: Float) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundColor(.white.opacity(0.6))
                Spacer()
                Text(db > -100 ? String(format: "%.1f dB", db) : "-- dB")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.white.opacity(0.8))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08)).frame(height: 6)
                    Capsule()
                        .fill(AITheme.aiGradient)
                        .frame(width: max(0, meterWidth(db: db, total: geo.size.width)), height: 6)
                }
            }
            .frame(height: 6)
        }
    }

    private func meterWidth(db: Float, total: CGFloat) -> CGFloat {
        let pct = max(0, min(1, CGFloat((db + 60) / 60)))
        return pct * total
    }

    private var statsCard: some View {
        HStack(spacing: 14) {
            stat("Frame", "\(engine.framesProcessed)")
            stat("Process", engine.processingTimeMs > 0
                ? String(format: "%.1f ms", engine.processingTimeMs)
                : "-- ms")
            stat("Hop", "10 ms")
        }
        .glassCard()
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(AITheme.aiTextGradient)
            Text(label)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
    }

    private var recordingCard: some View {
        HStack(spacing: 10) {
            Image(systemName: engine.isCapturing ? "waveform.circle.fill" : "waveform.circle")
                .foregroundColor(engine.isCapturing ? .red : .white.opacity(0.5))
            VStack(alignment: .leading, spacing: 4) {
                Text(engine.isCapturing ? "Capturing original + enhanced" : "Live mic (optional)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                Text(engine.isCapturing
                     ? "Tap the mic button above to stop and open playback."
                     : "Tap the mic to record a live demo, or import a file above.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.55))
            }
            Spacer()
            if engine.isCapturing {
                TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                    Text(formatTime(engine.recordingDuration))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.red)
                }
            }
        }
        .glassCard()
    }

    private var listenExportSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Listen & export")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)

            if let recordingNotice {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(recordingNotice)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }
            } else if originalURL == nil && enhancedURL == nil {
                Text("Import a file or record from the mic to compare original vs enhanced audio.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.55))
            }

            if let url = originalURL {
                RecordingTrackRow(
                    label: "Original",
                    url: url,
                    accent: AITheme.violet,
                    playback: playback
                )
            }
            if let url = enhancedURL {
                RecordingTrackRow(
                    label: "Enhanced (NCKit)",
                    url: url,
                    accent: AITheme.cyan,
                    playback: playback
                )
            }
        }
        .glassCard()
    }

    // MARK: - Actions

    private func startImport(url: URL) {
        importTask?.cancel()
        recordingNotice = nil
        offlineProcessor.reset()

        importTask = Task {
            if let result = await offlineProcessor.process(at: url) {
                originalURL = result.original
                enhancedURL = result.enhanced
            } else if case .error(let message) = offlineProcessor.phase {
                importErrorMessage = message
                showImportError = true
            }
        }
    }

    private func toggleMic() {
        if engine.isRunning {
            playback.stop()
            let result = engine.stop() ?? (nil, nil)
            applyRecordingResult(result)
        } else {
            if MicPermission.isGranted {
                playback.stop()
                recordingNotice = nil
                engine.start()
            } else if MicPermission.isDenied {
                showMicPermissionAlert = true
            } else {
                MicPermission.request { granted in
                    Task { @MainActor in
                        if granted {
                            playback.stop()
                            engine.start()
                        }
                    }
                }
            }
        }
    }

    private func applyRecordingResult(_ result: (original: URL?, enhanced: URL?)) {
        originalURL = result.original
        enhancedURL = result.enhanced

        if originalURL != nil || enhancedURL != nil {
            recordingNotice = nil
        } else {
            recordingNotice = "No audio captured. Speak for a few seconds while recording, then try again."
        }
    }

    private func scrollToPlayback(_ proxy: ScrollViewProxy) {
        withAnimation(.easeInOut(duration: 0.35)) {
            proxy.scrollTo("playback", anchor: .top)
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%02d:%02d", m, s)
    }
}

#Preview {
    AudioView()
        .environmentObject(WavPlaybackController())
        .preferredColorScheme(.dark)
}
