//
//  AuroraAnimations.swift
//  Motive
//
//  Aurora Design System - Animation Presets
//

import SwiftUI

// MARK: - Aurora Animations

extension Animation {
    // Spring animations - preferred for natural motion
    static let auroraSpring = Animation.spring(response: 0.3, dampingFraction: 0.7)
    static let auroraSpringBouncy = Animation.spring(response: 0.4, dampingFraction: 0.6)
    static let auroraSpringStiff = Animation.spring(response: 0.25, dampingFraction: 0.8)
    static let auroraSpringSnappy = Animation.spring(response: 0.15, dampingFraction: 0.9)

    // Spring-based replacements for timing animations (preferred)
    static let auroraInstant = Animation.spring(response: 0.1, dampingFraction: 0.9)
    static let auroraFast = Animation.spring(response: 0.15, dampingFraction: 0.85)
    static let auroraNormal = Animation.spring(response: 0.25, dampingFraction: 0.8)
    static let auroraSlow = Animation.spring(response: 0.4, dampingFraction: 0.75)

    // Legacy compatibility
    static let velvetSpring = auroraSpring
    static let quickSpring = auroraSpringStiff
}
