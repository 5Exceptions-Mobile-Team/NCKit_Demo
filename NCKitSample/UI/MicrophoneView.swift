//
//  MicrophoneView.swift
//  NCKit Sample — built by 5Exceptions
//
//  Demonstrates real-time mic noise cancellation using NCKit's LibDFProcessor.
//

import AVFAudio
import SwiftUI

struct MicrophoneView: View {

    @StateObject private var engine = AudioEngine()
    @State private var recordingTime: TimeInterval = 0
    @State private var recordingTimer: Timer?
    @State private var originalURL: URL?
    @State private var enhancedURL: URL?
    @State private var showMicPermissionAlert = false

    var body: some View {
        NavigationStack {
            ZStack {
                AIBackground()

                ScrollView {
                    VStack(spacing: 18) {
                        header
                        statusBadge
                        micButton
                        toggleCard
                        metersCard
                        statsCard
                        recordingCard
                        if originalURL != nil || enhancedURL != nil {
                            playbackCard
                        }
                        FiveExceptionsFooter()
                    }
                    .padding()
                }
            }
            .navigationTitle("NCKit Sample")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .onAppear { engine.loadModel() }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Pill(text: "iOS 16+", tinted: true)
                Pill(text: "on-device")
                Pill(text: "DeepFilterNet3")
            }
            GradientText(text: "Real-Time Noise Cancellation",
                         font: .title3.weight(.bold))
            Text("LibDFProcessor processes each 10 ms hop directly from the mic.")
                .font(.caption)
                .foregroundColor(.white.opacity(0.65))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
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
        .background(
            Capsule().fill(Color.white.opacity(0.06))
        )
        .overlay(
            Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
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
        .disabled(engine.status == .loading)
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
                        .shadow(color: AITheme.cyan.opacity(0.5), radius: 4)
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
        HStack {
            Button(action: toggleRecording) {
                HStack(spacing: 8) {
                    Image(systemName: engine.isRecording ? "stop.circle.fill" : "record.circle")
                        .foregroundColor(engine.isRecording ? .red : .white.opacity(0.85))
                    Text(engine.isRecording ? "Stop Recording" : "Record A/B")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white)
                }
            }
            .disabled(!engine.isRunning)
            Spacer()
            if engine.isRecording {
                Text(formatTime(recordingTime))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.red)
            }
        }
        .glassCard()
    }

    private var playbackCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Last Recording")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
            if let url = originalURL { rowFor("Original", url: url) }
            if let url = enhancedURL { rowFor("Enhanced (NCKit)", url: url) }
        }
        .glassCard()
    }

    private func rowFor(_ label: String, url: URL) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.85))
            Spacer()
            ShareLink(item: url) {
                Image(systemName: "square.and.arrow.up")
                    .foregroundStyle(AITheme.aiTextGradient)
            }
        }
    }

    // MARK: - Actions

    private func toggleMic() {
        if engine.isRunning {
            engine.stop()
            stopTimer()
        } else {
            switch AVAudioApplication.shared.recordPermission {
            case .granted:
                engine.start()
            case .denied:
                showMicPermissionAlert = true
            case .undetermined:
                AVAudioApplication.requestRecordPermission { granted in
                    Task { @MainActor in
                        if granted { engine.start() }
                    }
                }
            @unknown default: break
            }
        }
    }

    private func toggleRecording() {
        if engine.isRecording {
            if let result = engine.stopRecording() {
                originalURL = result.original
                enhancedURL = result.enhanced
            }
            stopTimer()
        } else {
            engine.startRecording()
            recordingTime = 0
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
                Task { @MainActor in
                    recordingTime = engine.recordingDuration
                }
            }
        }
    }

    private func stopTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%02d:%02d", m, s)
    }
}

#Preview {
    MicrophoneView()
        .preferredColorScheme(.dark)
}
