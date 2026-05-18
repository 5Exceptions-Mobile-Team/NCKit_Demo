//
//  RecordingTrackRow.swift
//  NCKit Sample — built by 5Exceptions
//
//  Play / share / save row for one recorded WAV track.
//

import SwiftUI

struct RecordingTrackRow: View {
    let label: String
    let url: URL
    let accent: Color
    @ObservedObject var playback: WavPlaybackController

    @State private var showExportPicker = false

    private var isThisTrackActive: Bool {
        playback.isActive(url: url)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle()
                    .fill(accent)
                    .frame(width: 8, height: 8)
                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                Spacer()
            }

            if isThisTrackActive, playback.isPlaying || playback.currentTime > 0, playback.duration > 0 {
                ProgressView(value: playback.currentTime, total: max(playback.duration, 0.01))
                    .tint(accent)
                HStack {
                    Text(formatTime(playback.currentTime))
                    Spacer()
                    Text(formatTime(playback.duration))
                }
                .font(.caption2.monospacedDigit())
                .foregroundColor(.white.opacity(0.55))
            }

            HStack(spacing: 12) {
                Button(action: { playback.play(url: url) }) {
                    Label(
                        isThisTrackActive && playback.isPlaying ? "Pause" : "Play",
                        systemImage: isThisTrackActive && playback.isPlaying
                            ? "pause.circle.fill" : "play.circle.fill"
                    )
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(accent)
                }

                ShareLink(item: url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white.opacity(0.85))
                }

                Button {
                    showExportPicker = true
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white.opacity(0.85))
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isThisTrackActive ? accent.opacity(0.10) : Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(accent.opacity(isThisTrackActive ? 0.35 : 0.12), lineWidth: 1)
        )
        .sheet(isPresented: $showExportPicker) {
            DocumentExportPicker(url: url)
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let s = Int(max(0, seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
