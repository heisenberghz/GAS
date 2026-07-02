//
//  AuroraTokens.swift
//  Motive
//
//  Aurora Design System - Spacing, Corner Radius, and Shadow Tokens
//

import SwiftUI

// MARK: - Aurora Spacing (Base Unit: 4px)

enum AuroraSpacing {
    static let space0_5: CGFloat = 2 // micro gaps
    static let space1: CGFloat = 4 // tight
    static let space2: CGFloat = 8 // compact
    static let space3: CGFloat = 12 // default gap
    static let space4: CGFloat = 16 // standard
    static let space5: CGFloat = 20 // comfortable
    static let space6: CGFloat = 24 // sections
    static let space7: CGFloat = 28 // detail pane horizontal rhythm
    static let space8: CGFloat = 32 // large sections
    static let space10: CGFloat = 40 // page padding
    static let space12: CGFloat = 48 // hero spacing
}

/// Legacy Spacing namespace
enum Spacing {
    static let xxs: CGFloat = AuroraSpacing.space0_5
    static let xs: CGFloat = AuroraSpacing.space1
    static let sm: CGFloat = AuroraSpacing.space2
    static let md: CGFloat = AuroraSpacing.space3
    static let lg: CGFloat = AuroraSpacing.space4
    static let xl: CGFloat = AuroraSpacing.space6
    static let xxl: CGFloat = AuroraSpacing.space8
}

// MARK: - Aurora Corner Radius

enum AuroraRadius {
    static let xs: CGFloat = 4 // badges, tags
    static let sm: CGFloat = 6 // buttons, inputs
    static let md: CGFloat = 10 // cards
    static let lg: CGFloat = 14 // modals, panels
    static let xl: CGFloat = 20 // main containers
    static let full: CGFloat = 9999 // pills, avatars
}

// MARK: - Aurora Border & Prompt Styling

enum AuroraStroke {
    static let hairline: CGFloat = 0.5
    static let soft: CGFloat = 0.75
    static let regular: CGFloat = 1
    static let emphasis: CGFloat = 1.25
}

enum AuroraPromptStyle {
    static var borderColor: Color {
        Color.Aurora.border.opacity(0.45)
    }

    static var subtleBorderColor: Color {
        Color.Aurora.border.opacity(0.35)
    }

    static var dividerColor: Color {
        Color.Aurora.glassOverlay.opacity(0.10)
    }

    static let borderWidth: CGFloat = AuroraStroke.soft
    static let subtleBorderWidth: CGFloat = AuroraStroke.hairline
    static let emphasisBorderWidth: CGFloat = AuroraStroke.regular
}

/// Legacy CornerRadius namespace
enum CornerRadius {
    static let small: CGFloat = AuroraRadius.sm
    static let medium: CGFloat = AuroraRadius.md
    static let large: CGFloat = AuroraRadius.lg
    static let xlarge: CGFloat = AuroraRadius.xl
}

// MARK: - Aurora Shadow System

extension View {
    /// Large ambient glow shadow
    func auroraShadowLarge() -> some View {
        self.shadow(color: Color.black.opacity(0.18), radius: 24, x: 0, y: 12)
    }

    /// Medium shadow for cards
    func auroraShadowMedium() -> some View {
        self.shadow(color: Color.black.opacity(0.2), radius: 16, x: 0, y: 8)
    }

    /// Small shadow for buttons
    func auroraShadowSmall() -> some View {
        self.shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 3)
    }

    /// Glow effect with aurora colors
    func auroraGlow(intensity: Double = 0.3) -> some View {
        self.shadow(color: Color.Aurora.accent.opacity(intensity * 0.2), radius: 12, x: 0, y: 0)
    }

    /// Legacy shadows
    func velvetShadow(opacity: Double = 0.15, radius: CGFloat = 20, y: CGFloat = 8) -> some View {
        self.shadow(color: Color.black.opacity(opacity), radius: radius, x: 0, y: y)
    }

    func subtleShadow() -> some View {
        self.shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
    }
}
