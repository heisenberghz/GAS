//
//  AuroraTypography.swift
//  Motive
//
//  Aurora Design System - Typography
//

import SwiftUI

// MARK: - Aurora Typography

extension Font {
    enum Aurora {
        /// Display - for large titles (32pt / Bold / -0.02em)
        static let display = Font.system(size: 32, weight: .bold, design: .default)

        /// Title 1 (24pt / Semibold / -0.01em)
        static let title1 = Font.system(size: 24, weight: .semibold, design: .default)

        /// Title 2 (20pt / Semibold / -0.01em)
        static let title2 = Font.system(size: 20, weight: .semibold, design: .default)

        /// Headline (17pt / Semibold)
        static let headline = Font.system(size: 17, weight: .semibold, design: .default)

        /// Body (15pt / Regular / 1.5 line-height)
        static let body = Font.system(size: 15, weight: .regular, design: .default)

        /// Body Small (14pt / Regular)
        static let bodySmall = Font.system(size: 14, weight: .regular, design: .default)

        /// Caption (12pt / Medium)
        static let caption = Font.system(size: 12, weight: .medium, design: .default)

        /// Micro (11pt / Medium / 0.02em)
        static let micro = Font.system(size: 11, weight: .medium, design: .default)

        // Monospace for code/technical
        static let mono = Font.system(size: 13, weight: .regular, design: .monospaced)
        static let monoSmall = Font.system(size: 12, weight: .regular, design: .monospaced)
    }
}
