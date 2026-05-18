//
//  NCKitSampleApp.swift
//  NCKit Sample — built by 5Exceptions
//
//  Entry point. The app showcases two integrations of NCKit:
//    1. Real-time microphone NC via LibDFProcessor.
//    2. Offline video NC via DFN3FileProcessor.
//

import SwiftUI
import UIKit

@main
struct NCKitSampleApp: App {

    init() {
        // Match the docs site: dark default with translucent glass surfaces.
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = UIColor.clear
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance

        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithTransparentBackground()
        tabAppearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .tint(Color(red: 0.13, green: 0.83, blue: 0.93)) // AI cyan
        }
    }
}
