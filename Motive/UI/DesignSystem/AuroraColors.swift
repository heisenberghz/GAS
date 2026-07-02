//
//  AuroraColors.swift
//  Motive
//
//  Aurora Design System - Color Palette
//

import AppKit
import SwiftUI

// MARK: - Aurora Color Palette

extension Color {
    enum Aurora {
        // MARK: - Background Colors (Graphite)

        /// Base canvas - deepest background
        static var backgroundDeep: Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                appearance.isDark ? NSColor(hex: "151515") : NSColor(hex: "F5F5F5")
            })
        }

        /// Main background
        static var background: Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                appearance.isDark ? NSColor(hex: "1B1B1B") : NSColor(hex: "F8F8F8")
            })
        }

        /// Cards, inputs
        static var surface: Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                appearance.isDark ? NSColor(hex: "232323") : NSColor(hex: "FFFFFF")
            })
        }

        /// Hover/raised surface
        static var surfaceElevated: Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                appearance.isDark ? NSColor(hex: "2B2B2B") : NSColor(hex: "F0F0F0")
            })
        }

        // MARK: - Accent Colors (Graphite Metallic)

        /// Accent start - Lighter Graphite
        static var accentStart: Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                appearance.isDark ? NSColor(hex: "D0D0D0") : NSColor(hex: "808080")
            })
        }

        /// Accent middle - Graphite
        static var accentMid: Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                appearance.isDark ? NSColor(hex: "A0A0A0") : NSColor(hex: "636363")
            })
        }

        /// Accent end - Deeper Graphite
        static var accentEnd: Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                appearance.isDark ? NSColor(hex: "808080") : NSColor(hex: "4A4A4A")
            })
        }

        /// Primary accent color
        static var accent: Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                appearance.isDark ? NSColor(hex: "A0A0A0") : NSColor(hex: "636363")
            })
        }

        // MARK: - Primary Colors (Graphite)

        /// Primary color - Graphite
        static var primary: Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                appearance.isDark ? NSColor(hex: "8B8B8B") : NSColor(hex: "555555")
            })
        }

        /// Primary light - for hover
        static var primaryLight: Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                appearance.isDark ? NSColor(hex: "A3A3A3") : NSColor(hex: "6E6E6E")
            })
        }

        /// Primary dark - for pressed
        static var primaryDark: Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                appearance.isDark ? NSColor(hex: "737373") : NSColor(hex: "3D3D3D")
            })
        }

        // MARK: - Semantic Colors (System-aligned)

        /// Success
        static let success = Color(nsColor: .systemGreen)

        /// Warning
        static let warning = Color(nsColor: .systemOrange)

        /// Error
        static let error = Color(nsColor: .systemRed)

        /// Info
        static let info = Color(nsColor: .systemBlue)

        /// Micro accent for focus/highlight (amber)
        static var microAccent: Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                appearance.isDark ? NSColor(hex: "F5A623") : NSColor(hex: "D28C10")
            })
        }

        /// Soft micro accent fill for selected/highlight surfaces
        static var microAccentSoft: Color {
            microAccent.opacity(0.16)
        }

        /// Focus ring accent
        static var microAccentRing: Color {
            microAccent.opacity(0.78)
        }

        /// Plan mode accent color (kept aligned with micro accent)
        static var planAccent: Color {
            microAccent
        }

        // MARK: - Text Colors (Adaptive)

        /// Primary text
        static var textPrimary: Color {
            Color(nsColor: .labelColor)
        }

        /// Secondary text — slightly boosted in light mode for readability
        static var textSecondary: Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                appearance.isDark
                    ? NSColor.secondaryLabelColor
                    : NSColor(hex: "6B6B6B")
            })
        }

        /// Muted text — boosted in light mode (system tertiaryLabel is too faint on white)
        static var textMuted: Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                appearance.isDark
                    ? NSColor.tertiaryLabelColor
                    : NSColor(hex: "8A8A8A")
            })
        }

        /// Disabled text
        static var textDisabled: Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                appearance.isDark
                    ? NSColor.quaternaryLabelColor
                    : NSColor(hex: "ABABAB")
            })
        }

        // MARK: - Border Colors

        /// Default border - subtle
        static var border: Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                let base = NSColor.separatorColor
                return base.withAlphaComponent(appearance.isDark ? 0.4 : 0.6)
            })
        }

        /// Hover border
        static var borderHover: Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                let base = NSColor.separatorColor
                return base.withAlphaComponent(appearance.isDark ? 0.55 : 0.8)
            })
        }

        /// Focus border (Brand accent for visibility)
        static var borderFocus: Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                appearance.isDark
                    ? NSColor(hex: "F5A623").withAlphaComponent(0.62)
                    : NSColor(hex: "D28C10").withAlphaComponent(0.5)
            })
        }

        // MARK: - Gradient Helpers

        /// Aurora gradient colors array
        static var auroraGradientColors: [Color] {
            [accentStart, accentMid, accentEnd]
        }

        /// Aurora gradient
        static var auroraGradient: LinearGradient {
            LinearGradient(
                colors: auroraGradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        /// Horizontal aurora gradient
        static var auroraGradientHorizontal: LinearGradient {
            LinearGradient(
                colors: auroraGradientColors,
                startPoint: .leading,
                endPoint: .trailing
            )
        }

        // MARK: - Glass Overlay Color

        /// Adaptive overlay for glass/translucent surfaces.
        /// White in dark mode, black in light mode — used at low opacity
        /// for separators, subtle button backgrounds, and border tints
        /// so they remain visible against both light and dark backdrops.
        static var glassOverlay: Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                (appearance.isDark ? NSColor.white : NSColor.black).withAlphaComponent(appearance.isDark ? 0.08 : 0.05)
            })
        }

        // MARK: - Status Colors

        static var idle: Color {
            textMuted
        }

        static var reasoning: Color {
            primary
        }

        static var executing: Color {
            primary
        }
    }
}

// MARK: - Color Hex Initializer

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255
        )
    }
}
