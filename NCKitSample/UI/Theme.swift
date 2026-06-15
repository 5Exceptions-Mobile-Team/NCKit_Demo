//
//  Theme.swift
//  NCKit Sample
//
//  AI-transparent glass palette, matching the NCKit docs website.
//  Cyan → violet → pink gradients, frosted glass surfaces, dark by default.
//

import SwiftUI
import UIKit

enum AITheme {

    // MARK: - Colors

    static let cyan   = Color(red: 0.13, green: 0.83, blue: 0.93) // #22d3ee
    static let violet = Color(red: 0.55, green: 0.36, blue: 0.96) // #8b5cf6
    static let blue   = Color(red: 0.23, green: 0.51, blue: 0.96) // #3b82f6
    static let pink   = Color(red: 0.93, green: 0.28, blue: 0.60) // #ec4899

    static let cyanDim   = Color(red: 0.21, green: 0.74, blue: 0.83)
    static let violetDim = Color(red: 0.49, green: 0.36, blue: 0.93)

    // MARK: - Gradients

    static let aiGradient = LinearGradient(
        colors: [cyan, violet, pink],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let aiTextGradient = LinearGradient(
        colors: [cyan, violet],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let backgroundGradient = LinearGradient(
        colors: [
            Color(red: 0.04, green: 0.06, blue: 0.11),
            Color(red: 0.06, green: 0.05, blue: 0.13),
            Color(red: 0.03, green: 0.04, blue: 0.09)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Background with mesh orbs

struct AIBackground: View {
    var body: some View {
        ZStack {
            AITheme.backgroundGradient
                .ignoresSafeArea()

            GeometryReader { geo in
                ZStack {
                    Circle()
                        .fill(AITheme.cyan.opacity(0.28))
                        .frame(width: geo.size.width * 0.85, height: geo.size.width * 0.85)
                        .blur(radius: 120)
                        .offset(x: -geo.size.width * 0.35, y: -geo.size.height * 0.20)
                    Circle()
                        .fill(AITheme.violet.opacity(0.30))
                        .frame(width: geo.size.width * 0.95, height: geo.size.width * 0.95)
                        .blur(radius: 140)
                        .offset(x: geo.size.width * 0.40, y: geo.size.height * 0.05)
                    Circle()
                        .fill(AITheme.pink.opacity(0.18))
                        .frame(width: geo.size.width * 0.70, height: geo.size.width * 0.70)
                        .blur(radius: 130)
                        .offset(x: -geo.size.width * 0.10, y: geo.size.height * 0.45)
                }
            }
            .ignoresSafeArea()
        }
    }
}

// MARK: - Glass card modifier

struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 16
    var strokeOpacity: Double = 0.18

    func body(content: Content) -> some View {
        content
            .padding()
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                AITheme.cyan.opacity(strokeOpacity),
                                AITheme.violet.opacity(strokeOpacity * 0.6),
                                .white.opacity(0.04)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 10)
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 16, strokeOpacity: Double = 0.18) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius, strokeOpacity: strokeOpacity))
    }

    /// Frosted navigation chrome matching the tab bar (`systemUltraThinMaterialDark`).
    func glassNavigationChrome() -> some View {
        modifier(GlassNavigationChromeModifier())
    }
}

// MARK: - Navigation + status-bar blur (matches tab bar)

private enum GlassChrome {
    static let blurStyle: UIBlurEffect.Style = .systemUltraThinMaterialDark
}

private struct GlassNavigationChromeModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
                .background(alignment: .top) {
                    StatusBarBlurStrip()
                }
        } else {
            content
                .background(alignment: .top) {
                    StatusBarBlurStrip()
                }
        }
    }
}

/// Blur for the safe area above the navigation bar (status bar / Dynamic Island).
private struct StatusBarBlurStrip: View {
    var body: some View {
        GeometryReader { geo in
            let height = geo.safeAreaInsets.top
            if height > 0 {
                MaterialBlurView(style: GlassChrome.blurStyle)
                    .frame(height: height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }
}

private struct MaterialBlurView: UIViewRepresentable {
    let style: UIBlurEffect.Style

    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: style)
    }
}

// MARK: - Gradient text

struct GradientText: View {
    let text: String
    let font: Font

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(AITheme.aiTextGradient)
    }
}

// MARK: - Pill / chip

struct Pill: View {
    let text: String
    var tinted: Bool = false

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundColor(tinted ? AITheme.cyan : .white.opacity(0.75))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(tinted ? AITheme.cyan.opacity(0.14) : Color.white.opacity(0.08))
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        tinted ? AITheme.cyan.opacity(0.45) : Color.white.opacity(0.12),
                        lineWidth: 1
                    )
            )
    }
}
