//
//  AppState+CommandBar.swift
//  Motive
//
//  Created by geezerrrr on 2026/1/19.
//

import SwiftUI

extension AppState {
    /// Whether the command bar is currently visible
    var isCommandBarVisible: Bool {
        commandBarController?.isVisible ?? false
    }

    func showCommandBar() {
        guard let commandBarController else {
            Log.debug("commandBarController is nil!")
            return
        }

        if !commandBarController.isVisible {
            // Pre-compute the correct window height BEFORE showing.
            // Without this, the window briefly shows at the stale height
            // from a previous mode (e.g., 450px from /command list) because
            // SwiftUI's onChange(commandBarResetTrigger) fires AFTER show().
            let targetHeight = expectedCommandBarHeight()
            commandBarController.updateHeight(to: targetHeight, animated: false)

            // Trigger recenterAndFocus() which syncs mode and resets stale state
            commandBarResetTrigger += 1
        }

        commandBarController.show()
    }

    /// Pre-compute the expected command bar height based on current session state.
    /// Mirrors the mode-selection logic in CommandBarView.recenterAndFocus().
    private func expectedCommandBarHeight() -> CGFloat {
        switch sessionStatus {
        case .running:
            CommandBarWindowController.heights["running"] ?? 160
        case .completed:
            CommandBarWindowController.heights["completed"] ?? 160
        case .failed:
            CommandBarWindowController.heights["error"] ?? 160
        case .idle, .interrupted:
            if currentSessionRef != nil, !messages.isEmpty {
                CommandBarWindowController.heights["completed"] ?? 160
            } else {
                CommandBarWindowController.heights["idle"] ?? 100
            }
        }
    }

    func hideCommandBar() {
        commandBarController?.hide()
    }

    /// Update the command bar window frame height.
    /// Called automatically by CommandBarView's onChange(of: currentHeight).
    /// Also called during showCommandBar() for pre-show sizing.
    func updateCommandBarHeight(to height: CGFloat) {
        commandBarController?.updateHeight(to: height, animated: false)
    }

    /// Suppress or allow auto-hide when command bar loses focus
    func setCommandBarAutoHideSuppressed(_ suppressed: Bool) {
        commandBarController?.suppressAutoHide = suppressed
    }

    /// Refocus the command bar input field
    func refocusCommandBar() {
        commandBarController?.focusFirstResponder()
    }
}
