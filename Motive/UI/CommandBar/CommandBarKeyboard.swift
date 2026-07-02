//
//  CommandBarKeyboard.swift
//  Motive
//
//  Created by geezerrrr on 2026/1/19.
//

import SwiftUI

extension CommandBarView {
    // MARK: - Keyboard Navigation

    func handleUpArrow() {
        // File completion takes priority
        if showFileCompletion, !fileCompletion.items.isEmpty {
            if selectedFileIndex > 0 {
                selectedFileIndex -= 1
            }
            return
        }

        if mode.isCommand {
            if selectedCommandIndex > 0 {
                selectedCommandIndex -= 1
            }
        } else if mode.isHistory {
            if selectedHistoryIndex > 0 {
                selectedHistoryIndex -= 1
            }
            if selectedHistoryIndex < filteredHistorySessions.count {
                selectedHistoryId = filteredHistorySessions[selectedHistoryIndex].id
            }
        } else if mode.isProjects {
            if selectedProjectIndex > 0 {
                selectedProjectIndex -= 1
            }
        } else if mode.isModes {
            if selectedModeIndex > 0 {
                selectedModeIndex -= 1
            }
        }
    }

    func handleDownArrow() {
        // File completion takes priority
        if showFileCompletion, !fileCompletion.items.isEmpty {
            if selectedFileIndex < fileCompletion.items.count - 1 {
                selectedFileIndex += 1
            }
            return
        }

        if mode.isCommand {
            if selectedCommandIndex < filteredCommands.count - 1 {
                selectedCommandIndex += 1
            }
        } else if mode.isHistory {
            if selectedHistoryIndex < filteredHistorySessions.count - 1 {
                selectedHistoryIndex += 1
            }
            if selectedHistoryIndex < filteredHistorySessions.count {
                selectedHistoryId = filteredHistorySessions[selectedHistoryIndex].id
            }
        } else if mode.isProjects {
            // 2 fixed items (Choose folder + Default) + recent projects
            let totalItems = 2 + configManager.recentProjects.count
            if selectedProjectIndex < totalItems - 1 {
                selectedProjectIndex += 1
            }
        } else if mode.isModes {
            let maxIndex = max(availableModeChoices.count - 1, 0)
            if selectedModeIndex < maxIndex {
                selectedModeIndex += 1
            }
        }
    }

    func handleTab() {
        // File completion takes priority
        if showFileCompletion, !fileCompletion.items.isEmpty {
            if selectedFileIndex < fileCompletion.items.count {
                selectFileCompletion(fileCompletion.items[selectedFileIndex])
            }
            return
        }

        // Tab completion: complete the autocomplete hint
        if let hint = autocompleteHint {
            inputText = hint
        }
    }

    func handleCmdN() {
        // Cmd+N to create new session (works in any mode)
        appState.startNewEmptySession()
        inputText = ""
        mode = .completed // Show "New Task" status
    }

    func handleCmdDelete() {
        // Cmd+Delete to delete selected session in history mode
        if mode.isHistory, selectedHistoryIndex < filteredHistorySessions.count {
            deleteCandidateIndex = selectedHistoryIndex
            deleteCandidateId = filteredHistorySessions[selectedHistoryIndex].id
            selectedHistoryId = filteredHistorySessions[selectedHistoryIndex].id
            showDeleteConfirmation = true
        }
    }

    func handleEscape() {
        // File completion: ESC closes it first
        if showFileCompletion {
            hideFileCompletion()
            return
        }

        if mode.isCommand || mode.isHistory || mode.isProjects || mode.isModes {
            // Return to previous mode (session or idle)
            if appState.sessionStatus == .running {
                mode = .running
            } else if mode.isFromSession || !appState.messages.isEmpty {
                mode = .completed
            } else {
                mode = .idle
            }
            inputText = ""
        } else {
            // ESC = hide CommandBar (task continues running in background)
            appState.hideCommandBar()
        }
    }
}
