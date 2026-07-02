//
//  LiquidGlassBackground.swift
//  Motive
//
//  Uses Apple's native .glassEffect() on macOS 26+ for authentic Liquid Glass,
//  with a .ultraThinMaterial fallback for older OS versions.
//  Pass `mode` directly to avoid @EnvironmentObject propagation issues.
//

import AppKit
import SwiftUI

// MARK: - Core Primitive (direct mode parameter — safe everywhere)

struct LiquidGlassBackground: View {
    var mode: ConfigManager.LiquidGlassMode = .clear
    var cornerRadius: CGFloat = 16
    var showBorder: Bool = true

    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool {
        colorScheme == .dark
    }

    var body: some View {
        if #available(macOS 26, *) {
            nativeGlass
        } else {
            legacyGlass
        }
    }

    // MARK: macOS 26+  — Native Liquid Glass

    @available(macOS 26, *)
    private var nativeGlass: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.clear)
            .glassEffect(
                mode == .tinted
                    ? .regular.tint(Color.primary.opacity(isDark ? 0.15 : 0.10))
                    : .regular,
                in: .rect(cornerRadius: cornerRadius)
            )
    }

    // MARK: Legacy fallback (pre-macOS 26)

    private var legacyGlass: some View {
        ZStack {
            VisualEffectView(
                material: mode == .tinted ? .menu : .fullScreenUI,
                blendingMode: .behindWindow,
                state: .active,
                cornerRadius: cornerRadius,
                masksToBounds: true
            )

            if mode == .tinted {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(isDark ? 0.08 : 0.06))
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(isDark ? 0.03 : 0.02))
            }

            if showBorder {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(isDark ? 0.28 : 0.50), location: 0.0),
                                .init(color: .white.opacity(isDark ? 0.06 : 0.12), location: 0.45),
                                .init(color: .white.opacity(isDark ? 0.12 : 0.22), location: 1.0),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Convenience Wrapper (reads mode from @EnvironmentObject — main view tree only)

struct LiquidGlassBackgroundAuto: View {
    @EnvironmentObject var configManager: ConfigManager
    var cornerRadius: CGFloat = 16
    var showBorder: Bool = true

    var body: some View {
        LiquidGlassBackground(
            mode: configManager.liquidGlassMode,
            cornerRadius: cornerRadius,
            showBorder: showBorder
        )
    }
}
