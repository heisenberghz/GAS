//
//  AppState+Drawer.swift
//  Motive
//
//  Created by geezerrrr on 2026/1/19.
//

import AppKit

extension AppState {
    func toggleDrawer() {
        Log.debug("toggleDrawer called, drawerWindowController exists: \(drawerWindowController != nil)")
        guard let drawerWindowController else {
            Log.debug("drawerWindowController is nil!")
            return
        }
        if drawerWindowController.isVisible {
            Log.debug("Hiding drawer")
            drawerWindowController.hide()
        } else {
            Log.debug("Showing drawer")
            // Pass status bar button position for proper positioning
            drawerWindowController.updateStatusBarButtonFrame(statusBarController?.buttonFrame)
            drawerWindowController.show()
        }
    }

    func hideDrawer() {
        drawerWindowController?.hide()
    }

    /// Show the Drawer (no-op if already visible)
    func showDrawer() {
        guard let drawerWindowController, !drawerWindowController.isVisible else { return }
        drawerWindowController.updateStatusBarButtonFrame(statusBarController?.buttonFrame)
        drawerWindowController.show()
    }

    /// Get the Drawer window for showing alerts as sheets
    var drawerWindowRef: NSWindow? {
        drawerWindowController?.getWindow()
    }

    /// Temporarily suppress auto-hide for Drawer (e.g., during alert display)
    func setDrawerAutoHideSuppressed(_ suppressed: Bool) {
        drawerWindowController?.suppressAutoHide = suppressed
    }
}
