//
//  CommandBarView+Actions.swift
//  Motive
//
//  Created by geezerrrr on 2026/1/19.
//

import AppKit
import SwiftUI

extension CommandBarView {
    func handleOnAppear() {
        // Window-level animation is handled by CommandBarWindowController
        // Just focus the input field
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            isInputFocused = true
        }
    }

    /// Open the chat inline in the Command Bar popup
    func enterChatMode() {
        withAnimation { mode = .chat }
    }

    /// Pop the conversation out to the floating Drawer window and close the popup
    func popOutToDrawer() {
        appState.showDrawer()
        appState.hideCommandBar()
    }

    func confirmDeleteSession() {
        guard selectedHistoryIndex < filteredHistorySessions.count else { return }
        let deleteId = filteredHistorySessions[selectedHistoryIndex].id
        removeHistorySession(id: deleteId, preferredIndex: selectedHistoryIndex)
        appState.deleteSession(id: deleteId)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            refreshHistorySessions(preferredIndex: selectedHistoryIndex)
        }
    }

    func showDeleteAlert() {
        let targetIndex = deleteCandidateIndex ?? selectedHistoryIndex
        guard targetIndex < filteredHistorySessions.count else {
            showDeleteConfirmation = false
            return
        }

        let sessionName = filteredHistorySessions[targetIndex].intent

        // Suppress auto-hide while alert is showing
        appState.setCommandBarAutoHideSuppressed(true)

        // Use NSAlert for better focus control
        let alert = NSAlert()
        alert.messageText = L10n.Alert.deleteSessionTitle
        alert.informativeText = String(format: L10n.Alert.deleteSessionMessage, sessionName)
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.CommandBar.delete)
        alert.addButton(withTitle: L10n.CommandBar.cancel)

        // Show alert attached to command bar window
        if let window = appState.commandBarWindowRef {
            // Capture values needed in closure (struct cannot use weak self)
            let deleteId = deleteCandidateId ?? filteredHistorySessions[targetIndex].id
            let preferredIndex = deleteCandidateIndex ?? targetIndex
            let appStateRef = appState

            alert.beginSheetModal(for: window) { response in
                if response == .alertFirstButtonReturn {
                    // Delete the session and refresh list/selection immediately
                    Task { @MainActor in
                        removeHistorySession(id: deleteId, preferredIndex: preferredIndex)
                        appStateRef.deleteSession(id: deleteId)
                        // Sync with persisted state after deletion
                        try? await Task.sleep(for: .milliseconds(50))
                        refreshHistorySessions(preferredIndex: selectedHistoryIndex)
                    }
                }

                // Reset state and restore focus
                appStateRef.setCommandBarAutoHideSuppressed(false)

                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(50))
                    appStateRef.refocusCommandBar()
                }
            }

            // Reset the flag (will be handled after alert closes)
            showDeleteConfirmation = false
            deleteCandidateIndex = nil
            deleteCandidateId = nil
        } else {
            showDeleteConfirmation = false
            deleteCandidateIndex = nil
            deleteCandidateId = nil
            appState.setCommandBarAutoHideSuppressed(false)
        }
    }

    // MARK: - State Handlers

    func handleInputChange(_ newValue: String) {
        // Always check for @ file completion
        checkForAtCompletion(newValue)

        // If file completion, history/projects/modes, or running — don't alter mode
        guard !showFileCompletion, !mode.isHistory, !mode.isProjects, !mode.isModes, mode != .running else { return }

        let isInSession = mode == .completed || mode == .running || mode.isFromSession

        if newValue.hasPrefix("/") {
            // Enter command mode
            if !mode.isCommand {
                mode = .command(fromSession: isInSession || !appState.messages.isEmpty)
                selectedCommandIndex = 0
            }
        } else if mode.isCommand {
            // Exiting command mode — return to previous state
            mode = (mode.isFromSession || !appState.messages.isEmpty) ? .completed : (newValue.isEmpty ? .idle : .input)
        } else if case .completed = mode {
            return // Stay in completed for follow-up
        } else if case .error = mode {
            return // Stay in error for follow-up
        } else {
            mode = newValue.isEmpty ? .idle : .input
        }
    }

    func handleModeChange(from oldMode: CommandBarMode, to newMode: CommandBarMode) {
        // Window height is auto-synced via onChange(of: currentHeight) — no manual call needed.
        if case .error = newMode {
            // keep current state
        } else {
            showErrorDetailsPopover = false
        }

        // Load data when entering specific modes
        if newMode.isHistory {
            loadHistorySessions()
        }

        // Keep input focused in all modes
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            isInputFocused = true
        }
    }

    func handleSessionStatusChange(_ status: SessionStatus) {
        // Don't change mode if user is browsing commands/history/projects/modes
        if mode.isCommand || mode.isHistory || mode.isProjects || mode.isModes {
            return
        }

        switch status {
        case .running:
            mode = .running
        case .completed:
            mode = .completed
        case .failed:
            mode = .error(appState.lastErrorMessage ?? "An error occurred")
        case .idle, .interrupted:
            if mode == .running {
                mode = .idle
            }
        }
    }

    /// Re-center window and refocus input when CommandBar is shown.
    /// Called ONLY when commandBarResetTrigger fires (hidden → visible transition).
    /// MUST unconditionally reset ALL stale state from previous interactions.
    func recenterAndFocus() {

        // 1. Reset stale file completion state
        //    (@State persists across show/hide cycles in the long-lived NSHostingView)
        showFileCompletion = false
        atQueryRange = nil
        fileCompletion.clear()

        // 2. Clear stale input text (user starts fresh on each show)
        //    This prevents stale "/" or "@" from keeping the mode wrong.
        inputText = ""

        // 3. ALWAYS sync mode with current session status.
        //    List modes (.command, .history, .projects) are only valid during active
        //    interaction. When re-showing from hidden, they MUST be reset —
        //    otherwise the stale mode produces a wrong currentHeight and the window
        //    frame desyncs from the SwiftUI content.
        switch appState.sessionStatus {
        case .running:
            mode = .running
        case .completed:
            mode = .completed
        case .failed:
            mode = .error(appState.lastErrorMessage ?? "An error occurred")
        case .idle, .interrupted:
            if appState.currentSessionRef != nil, !appState.messages.isEmpty {
                mode = .completed
            } else {
                mode = .idle
            }
        }

        // Window height is auto-synced via onChange(of: currentHeight).

        // 4. Refocus input
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            isInputFocused = true
        }
    }
}
