//
//  NCKitSampleApp.swift
//  NCKit Sample — built by 5Exceptions
//
//  Entry point. The app showcases two integrations of NCKit:
//    1. Real-time microphone NC via NCKitProcessor.
//    2. Offline video NC via NCKitFileProcessor.
//

import SwiftUI
import UIKit

@main
struct NCKitSampleApp: App {

    @StateObject private var wavPlayback = WavPlaybackController()

    init() {
        configureGlassChrome()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(wavPlayback)
                .preferredColorScheme(.dark)
                .tint(Color(red: 0.13, green: 0.83, blue: 0.93)) // AI cyan
        }
    }

    private func configureGlassChrome() {
        let blur = UIBlurEffect(style: .systemUltraThinMaterialDark)

        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithTransparentBackground()
        navAppearance.backgroundEffect = blur
        navAppearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        navAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]

        let navBar = UINavigationBar.appearance()
        navBar.standardAppearance = navAppearance
        navBar.scrollEdgeAppearance = navAppearance
        navBar.compactAppearance = navAppearance

        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithTransparentBackground()
        tabAppearance.backgroundEffect = blur
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
    }
}
