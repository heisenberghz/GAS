//
//  CommandBarHistoryActions.swift
//  Motive
//
//  Created by geezerrrr on 2026/1/19.
//

import SwiftUI

extension CommandBarView {
    // MARK: - Histories

    func requestDeleteHistorySession(at index: Int) {
        guard index < filteredHistorySessions.count else { return }
        // Set the selected index to the one being deleted
        selectedHistoryIndex = index
        deleteCandidateIndex = index
        deleteCandidateId = filteredHistorySessions[index].id
        selectedHistoryId = filteredHistorySessions[index].id
        // Show confirmation dialog
        showDeleteConfirmation = true
    }

    var filteredHistorySessions: [Session] {
        if inputText.isEmpty {
            return Array(historySessions.prefix(20))
        }
        return historySessions.filter { $0.intent.localizedCaseInsensitiveContains(inputText) }.prefix(20).map(\.self)
    }

    func loadHistorySessions() {
        refreshHistorySessions(preferredIndex: nil)
    }

    func refreshHistorySessions(preferredIndex: Int?) {
        historySessions = appState.getAllSessions()
        let list = filteredHistorySessions
        guard !list.isEmpty else {
            selectedHistoryIndex = 0
            selectedHistoryId = nil
            return
        }

        if let selectedHistoryId,
           let index = list.firstIndex(where: { $0.id == selectedHistoryId })
        {
            selectedHistoryIndex = index
            return
        }

        if let preferredIndex {
            selectedHistoryIndex = min(preferredIndex, list.count - 1)
            selectedHistoryId = list[selectedHistoryIndex].id
            return
        }

        // Select current session if exists, otherwise default to first
        if let currentSession = appState.currentSessionRef,
           let index = list.firstIndex(where: { $0.id == currentSession.id })
        {
            selectedHistoryIndex = index
            selectedHistoryId = currentSession.id
        } else {
            selectedHistoryIndex = 0
            selectedHistoryId = list[0].id
        }
    }

    func selectHistorySession(_ session: Session) {
        appState.switchToSession(session)
        inputText = ""
        if let index = filteredHistorySessions.firstIndex(where: { $0.id == session.id }) {
            selectedHistoryIndex = index
        }
        selectedHistoryId = session.id
        // Stay in CommandBar, switch to appropriate mode based on session status
        if appState.sessionStatus == .running {
            mode = .running
        } else {
            mode = .completed
        }
    }

    func deleteHistorySession(at index: Int) {
        guard index < filteredHistorySessions.count else { return }
        let deleteId = filteredHistorySessions[index].id
        removeHistorySession(id: deleteId, preferredIndex: index)
        appState.deleteSession(id: deleteId)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            refreshHistorySessions(preferredIndex: selectedHistoryIndex)
        }
    }

    func removeHistorySession(id: UUID, preferredIndex: Int) {
        historySessions.removeAll { $0.id == id }
        let list = filteredHistorySessions
        if list.isEmpty {
            selectedHistoryIndex = 0
            selectedHistoryId = nil
        } else {
            selectedHistoryIndex = min(preferredIndex, list.count - 1)
            selectedHistoryId = list[selectedHistoryIndex].id
        }
    }

    // MARK: - Projects

    func selectProject(_ path: String?) {
        appState.switchProjectDirectory(path)
        inputText = ""
        mode = .idle
    }
}
