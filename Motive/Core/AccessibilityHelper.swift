//
//  AccessibilityHelper.swift
//  Motive
//
//  Created by geezerrrr on 2026/1/19.
//

import AppKit
import ApplicationServices

enum AccessibilityHelper {

    /// Check if the app has accessibility permission
    static var hasPermission: Bool {
        AXIsProcessTrusted()
    }

    /// Request accessibility permission with a prompt
    /// Returns true if already has permission, false if needs to be granted
    @discardableResult
    static func requestPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Open System Settings to the Accessibility pane
    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
