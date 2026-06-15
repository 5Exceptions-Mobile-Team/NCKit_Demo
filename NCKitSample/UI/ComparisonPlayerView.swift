//
//  ComparisonPlayerView.swift
//  NCKit Sample
//
//  A/B comparison player for original vs NCKit-enhanced video.
//

import AVFoundation
import AVKit
import SwiftUI

struct ComparisonPlayerView: View {
    let result: ProcessedVideoResult
    let onSave: () -> Void

    @State private var activeTrack: TrackSelection = .enhanced
    @State private var isPlaying = false
    @State private var currentTime: Double = 0
    @State private var isSeeking = false

    @State private var originalPlayer: AVPlayer?
    @State private var enhancedPlayer: AVPlayer?
    @State private var timeObserver: Any?
    @State private var observedPlayer: AVPlayer?
    @State private var showExportOriginal = false
    @State private var showExportEnhanced = false

    private var originalWaveform: [WaveformGenerator.WaveformPoint] { result.originalWaveform }
    private var enhancedWaveform: [WaveformGenerator.WaveformPoint] { result.enhancedWaveform }

    enum TrackSelection: String, CaseIterable {
        case original = "Original"
        case enhanced = "Enhanced"
    }

    private var activePlayer: AVPlayer? {
        activeTrack == .original ? originalPlayer : enhancedPlayer
    }

    private var accent: Color {
        activeTrack == .original ? AITheme.violet : AITheme.cyan
    }

    private var duration: Double { result.duration }

    var body: some View {
        ZStack {
            AIBackground()

            ScrollView {
                VStack(spacing: 16) {
                    videoPlayerSection
                    abToggle.padding(.horizontal)
                    waveformSection.padding(.horizontal)
                    transportSection.padding(.horizontal)
                    actionsSection.padding(.horizontal)
                }
                .padding(.vertical, 12)
            }
        }
        .navigationTitle("Compare A/B")
        .navigationBarTitleDisplayMode(.inline)
        .glassNavigationChrome()
        .onAppear {
            configurePlaybackSession()
            setupPlayers()
        }
        .onDisappear(perform: teardownPlayers)
    }

    // MARK: - Video player

    private var videoPlayerSection: some View {
        ZStack {
            Color.black

            if let player = activePlayer {
                VideoPlayer(player: player).disabled(true)
            }

            VStack {
                HStack {
                    Spacer()
                    Text(activeTrack.rawValue)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(accent.opacity(0.85)))
                        .foregroundColor(.white)
                        .padding(12)
                }
                Spacer()
            }
        }
        .aspectRatio(16/9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AITheme.aiGradient.opacity(0.35), lineWidth: 1)
        )
        .padding(.horizontal)
        .padding(.top, 4)
    }

    // MARK: - A/B toggle

    private var abToggle: some View {
        HStack(spacing: 0) {
            ForEach(TrackSelection.allCases, id: \.self) { track in
                Button { switchTrack(to: track) } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(track == .original ? AITheme.violet : AITheme.cyan)
                            .frame(width: 8, height: 8)
                        Text(track.rawValue)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(activeTrack == track ? .white : .white.opacity(0.55))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(activeTrack == track
                                  ? (track == .original ? AITheme.violet.opacity(0.18) : AITheme.cyan.opacity(0.18))
                                  : Color.clear)
                    )
                }
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    // MARK: - Waveforms

    private var waveformSection: some View {
        VStack(spacing: 10) {
            waveformRow(label: "Original",
                        data: originalWaveform,
                        color: AITheme.violet,
                        isActive: activeTrack == .original)
            waveformRow(label: "Enhanced (NCKit)",
                        data: enhancedWaveform,
                        color: AITheme.cyan,
                        isActive: activeTrack == .enhanced)
        }
    }

    private func waveformRow(label: String, data: [WaveformGenerator.WaveformPoint], color: Color, isActive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundColor(color)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Canvas { context, size in
                        guard !data.isEmpty else { return }
                        let w = size.width
                        let h = size.height
                        let mid = h / 2

                        for (i, point) in data.enumerated() {
                            let x = CGFloat(i) / CGFloat(data.count) * w
                            let minY = mid - CGFloat(point.min) * mid
                            let maxY = mid - CGFloat(point.max) * mid
                            context.fill(
                                Path { p in
                                    p.addRect(CGRect(
                                        x: x, y: maxY,
                                        width: max(1, w / CGFloat(data.count)),
                                        height: max(1, minY - maxY)
                                    ))
                                },
                                with: .color(color.opacity(isActive ? 0.8 : 0.35))
                            )
                        }
                    }

                    if duration > 0 {
                        let fraction = currentTime / duration
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: 2)
                            .offset(x: CGFloat(fraction) * geo.size.width)
                            .shadow(color: color.opacity(0.8), radius: 4)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0).onChanged { value in
                        let fraction = max(0, min(1, value.location.x / geo.size.width))
                        seekTo(fraction * duration)
                    }
                )
            }
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(color.opacity(0.18), lineWidth: 1)
            )
        }
    }

    // MARK: - Transport

    private var transportSection: some View {
        VStack(spacing: 10) {
            Slider(
                value: Binding(get: { currentTime }, set: { seekTo($0) }),
                in: 0...max(duration, 0.01)
            )
            .tint(accent)

            HStack {
                Text(formatTime(currentTime))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.white.opacity(0.65))
                Spacer()
                Text(formatTime(duration))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.white.opacity(0.65))
            }

            HStack(spacing: 32) {
                Button { seekTo(max(0, currentTime - 10)) } label: {
                    Image(systemName: "gobackward.10")
                        .font(.title2)
                        .foregroundColor(.white.opacity(0.85))
                }

                Button { togglePlayPause() } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(AITheme.aiTextGradient)
                }

                Button { seekTo(min(duration, currentTime + 10)) } label: {
                    Image(systemName: "goforward.10")
                        .font(.title2)
                        .foregroundColor(.white.opacity(0.85))
                }
            }
            .padding(.vertical, 4)
        }
        .glassCard()
    }

    // MARK: - Actions

    private var actionsSection: some View {
        VStack(spacing: 12) {
            Text("Export")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                videoActionButton(
                    title: "Original",
                    color: AITheme.violet,
                    shareURL: result.originalVideoURL,
                    saveAction: { showExportOriginal = true }
                )
                videoActionButton(
                    title: "Enhanced",
                    color: AITheme.cyan,
                    shareURL: result.enhancedVideoURL,
                    saveAction: { showExportEnhanced = true }
                )
            }

            Button(action: onSave) {
                Label("Save Enhanced to Photos", systemImage: "photo")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(AITheme.aiGradient)
                    )
            }
        }
        .sheet(isPresented: $showExportOriginal) {
            DocumentExportPicker(url: result.originalVideoURL)
        }
        .sheet(isPresented: $showExportEnhanced) {
            DocumentExportPicker(url: result.enhancedVideoURL)
        }
    }

    private func videoActionButton(
        title: String,
        color: Color,
        shareURL: URL,
        saveAction: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundColor(color)
            HStack(spacing: 8) {
                ShareButton(items: [shareURL]) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body)
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(color.opacity(0.2)))
                }
                Button(action: saveAction) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.body)
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(color.opacity(0.2)))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }

    // MARK: - Player logic

    private func configurePlaybackSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func setupPlayers() {
        originalPlayer = AVPlayer(url: result.originalVideoURL)
        enhancedPlayer = AVPlayer(url: result.enhancedVideoURL)
        updateMuteState()
        attachTimeObserver()
    }

    private func teardownPlayers() {
        removeTimeObserver()
        originalPlayer?.pause()
        enhancedPlayer?.pause()
        originalPlayer = nil
        enhancedPlayer = nil
    }

    private func attachTimeObserver() {
        removeTimeObserver()
        guard let player = activePlayer else { return }
        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            guard !isSeeking else { return }
            currentTime = time.seconds.isFinite ? time.seconds : 0
        }
        observedPlayer = player
    }

    private func removeTimeObserver() {
        if let obs = timeObserver, let player = observedPlayer {
            player.removeTimeObserver(obs)
        }
        timeObserver = nil
        observedPlayer = nil
    }

    private func updateMuteState() {
        originalPlayer?.isMuted = (activeTrack != .original)
        enhancedPlayer?.isMuted = (activeTrack != .enhanced)
    }

    private func switchTrack(to track: TrackSelection) {
        guard track != activeTrack else { return }
        let wasPlaying = isPlaying
        if wasPlaying {
            originalPlayer?.pause()
            enhancedPlayer?.pause()
        }

        removeTimeObserver()
        activeTrack = track
        updateMuteState()

        let time = CMTime(seconds: currentTime, preferredTimescale: 600)
        originalPlayer?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        enhancedPlayer?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)

        attachTimeObserver()

        if wasPlaying { activePlayer?.play() }
    }

    private func togglePlayPause() {
        if isPlaying {
            originalPlayer?.pause()
            enhancedPlayer?.pause()
            isPlaying = false
        } else {
            let time = CMTime(seconds: currentTime, preferredTimescale: 600)
            originalPlayer?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
            enhancedPlayer?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
            originalPlayer?.play()
            enhancedPlayer?.play()
            isPlaying = true
        }
    }

    private func seekTo(_ time: Double) {
        let clamped = max(0, min(time, duration))
        currentTime = clamped
        isSeeking = true

        let cmTime = CMTime(seconds: clamped, preferredTimescale: 600)
        let group = DispatchGroup()
        group.enter(); originalPlayer?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { _ in group.leave() }
        group.enter(); enhancedPlayer?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { _ in group.leave() }
        group.notify(queue: .main) { isSeeking = false }
    }

    private func formatTime(_ seconds: Double) -> String {
        let s = Int(max(0, seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
