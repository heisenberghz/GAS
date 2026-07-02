//
//  CommandBarSubmission.swift
//  Motive
//
//  Created by geezerrrr on 2026/1/19.
//

import SwiftUI

extension CommandBarView {
    func handleSubmit() {
        // File completion takes priority
        if showFileCompletion, !fileCompletion.items.isEmpty {
            if selectedFileIndex < fileCompletion.items.count {
                selectFileCompletion(fileCompletion.items[selectedFileIndex])
            }
            return
        }

        switch mode {
        case .command:
            submitCommandMode()
        case .history:
            if selectedHistoryIndex < filteredHistorySessions.count {
                selectHistorySession(filteredHistorySessions[selectedHistoryIndex])
            }
        case .projects:
            submitProjectSelection()
        case .modes:
            submitModeSelection()
        case .completed:
            sendFollowUp()
        default:
            submitIntent()
        }
    }

    /// Handle submit in command mode — check for inline path argument first.
    private func submitCommandMode() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("/project ") || text.hasPrefix("/p ") {
            let pathArg = text
                .replacingOccurrences(of: "^/p(roject)?\\s+", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !pathArg.isEmpty {
                inputText = ""
                mode = appState.switchProjectDirectory(pathArg) ? .idle : .error("Directory not found: \(pathArg)")
                return
            }
        }
        executeSelectedCommand()
    }

    /// Handle submit in modes mode — switch agent/plan.
    private func submitModeSelection() {
        let modes = availableModeChoices
        guard selectedModeIndex >= 0, selectedModeIndex < modes.count else { return }
        let modeName = modes[selectedModeIndex].value
        configManager.currentAgent = modeName
        configManager.generateOpenCodeConfig()
        appState.reconfigureBridge()
        let wasFromSession = mode.isFromSession || !appState.messages.isEmpty
        mode = wasFromSession ? .completed : .idle
        inputText = ""
    }

    /// Handle submit in projects mode — Choose folder / Default / Recent.
    private func submitProjectSelection() {
        switch selectedProjectIndex {
        case 0:
            appState.showProjectPicker()
        case 1:
            selectProject(nil)
        default:
            let projectIndex = selectedProjectIndex - 2
            if projectIndex < configManager.recentProjects.count {
                selectProject(configManager.recentProjects[projectIndex].path)
            }
        }
    }

    func submitIntent() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        appState.submitIntent(text)
        // Mode will change to .running via sessionStatus observer
        // CommandBar stays visible - only ESC or focus loss hides it
    }

    func executeSelectedCommand() {
        guard selectedCommandIndex < filteredCommands.count else { return }
        executeCommand(filteredCommands[selectedCommandIndex])
    }

    func executeCommand(_ command: CommandDefinition) {
        let wasFromSession = mode.isFromSession || !appState.messages.isEmpty
        switch command.id {
        case "mode":
            inputText = ""
            mode = .modes(fromSession: wasFromSession)
            // Pre-select the current mode
            selectedModeIndex = availableModeChoices.firstIndex(where: { $0.value == configManager.currentAgent }) ?? 0
        case "project":
            inputText = ""
            configManager.ensureCurrentProjectInRecents()
            appState.seedRecentProjectsFromSessions()
            mode = .projects(fromSession: wasFromSession)
            selectedProjectIndex = 0
        case "history":
            inputText = ""
            showFileCompletion = false // Ensure file completion doesn't intercept keyboard
            mode = .history(fromSession: wasFromSession)
            selectedHistoryIndex = 0
        case "settings":
            inputText = ""
            appState.hideCommandBar()
            SettingsWindowController.shared.show(tab: .general)
        case "new":
            inputText = ""
            appState.startNewEmptySession()
            mode = .idle
        case "clear":
            inputText = ""
            appState.clearCurrentSession()
            mode = .idle
        default:
            break
        }
    }

    func sendFollowUp() {
        // Use the main inputText for follow-up messages
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        appState.resumeSession(with: text)
        // CommandBar stays visible - mode will change to .running via sessionStatus observer
    }
}
