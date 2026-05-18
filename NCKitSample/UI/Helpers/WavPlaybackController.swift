//
//  WavPlaybackController.swift
//  NCKit Sample — built by 5Exceptions
//
//  Plays one recorded WAV at a time for A/B listening after capture.
//

import AVFoundation
import Combine
import Foundation

@MainActor
final class WavPlaybackController: ObservableObject {

    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    /// The track currently loaded (playing or paused). Only one track exists at a time.
    @Published private(set) var activeURL: URL?

    private var player: AVAudioPlayer?
    private var progressTimer: Timer?
    private let delegateBridge = PlayerDelegateBridge()

    init() {
        delegateBridge.onFinish = { [weak self] in
            Task { @MainActor in
                self?.handlePlaybackFinished()
            }
        }
    }

    /// Play this track exclusively. Stops any other track first. Tap again to pause/resume.
    func play(url: URL) {
        if activeURL == url {
            if isPlaying {
                pause()
            } else {
                resume()
            }
            return
        }

        stopCurrentPlayer()

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)

            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = delegateBridge
            p.prepareToPlay()
            p.play()

            player = p
            activeURL = url
            duration = p.duration
            currentTime = p.currentTime
            isPlaying = true
            startProgressTimer()
        } catch {
            stopCurrentPlayer()
            activeURL = nil
            isPlaying = false
            currentTime = 0
            duration = 0
        }
    }

    func pause() {
        guard isPlaying else { return }
        player?.pause()
        isPlaying = false
        currentTime = player?.currentTime ?? currentTime
        stopProgressTimer()
    }

    func resume() {
        guard let player, activeURL != nil, !isPlaying else { return }
        player.play()
        isPlaying = true
        startProgressTimer()
    }

    func stop() {
        stopCurrentPlayer()
        activeURL = nil
        isPlaying = false
        currentTime = 0
        duration = 0
    }

    func isActive(url: URL) -> Bool {
        activeURL == url
    }

    // MARK: - Private

    private func stopCurrentPlayer() {
        player?.stop()
        player = nil
        stopProgressTimer()
    }

    private func handlePlaybackFinished() {
        isPlaying = false
        currentTime = duration
        stopProgressTimer()
    }

    private func startProgressTimer() {
        stopProgressTimer()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.player else { return }
                self.currentTime = player.currentTime
                if !player.isPlaying, self.isPlaying {
                    self.handlePlaybackFinished()
                }
            }
        }
        if let progressTimer {
            RunLoop.main.add(progressTimer, forMode: .common)
        }
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
}

// MARK: - AVAudioPlayerDelegate bridge

private final class PlayerDelegateBridge: NSObject, AVAudioPlayerDelegate {
    var onFinish: (() -> Void)?

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish?()
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        onFinish?()
    }
}
