//
//  Compatibility.swift
//  NCKit Sample
//
//  iOS 15-safe wrappers for APIs that require newer OS versions in the demo UI.
//

import AVFoundation
import SwiftUI
import UIKit

// MARK: - Navigation

struct CompatibleNavigation<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(iOS 16.0, *) {
            NavigationStack { content() }
        } else {
            NavigationView(content: content)
                .navigationViewStyle(StackNavigationViewStyle())
        }
    }
}

// MARK: - Share

struct ShareButton<Label: View>: View {
    let items: [Any]
    @ViewBuilder var label: () -> Label

    @State private var showSheet = false

    var body: some View {
        Button { showSheet = true } label: { label() }
            .sheet(isPresented: $showSheet) {
                ActivityView(items: items)
            }
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Microphone permission (iOS 15)

enum MicPermission {
    static var isGranted: Bool {
        AVAudioSession.sharedInstance().recordPermission == .granted
    }

    static var isDenied: Bool {
        AVAudioSession.sharedInstance().recordPermission == .denied
    }

    static func request(completion: @escaping (Bool) -> Void) {
        AVAudioSession.sharedInstance().requestRecordPermission(completion)
    }
}
