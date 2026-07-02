//
//  NSColor+Hex.swift
//  Motive
//
//  Aurora Design System - NSColor and NSAppearance Extensions
//

import AppKit

// MARK: - NSColor Helpers

extension NSColor {
    convenience init(hex: String) {
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
            srgbRed: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: 1
        )
    }
}

extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
