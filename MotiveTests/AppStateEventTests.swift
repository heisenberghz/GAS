//
//  AppStateEventTests.swift
//  MotiveTests
//
//  Tests for AppState event handling logic.
//

import Foundation
@testable import Motive
import SwiftData
import Testing

@MainActor
struct AppStateEventTests {

    private func makeAppState() throws -> AppState {
        let configManager = ConfigManager()
        let appState = AppState(configManager: configManager)

        // Create in-memory SwiftData container
        let schema = Schema([Session.self, LogEntry.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [config])
        appState.attachModelContext(container.mainContext)

        // Set up a session with a known openCodeSessionId so events can route correctly
        let session = Session(intent: "test", openCodeSessionId: "test-session")
        container.mainContext.insert(session)
        appState.currentSession = session
        appState.runningSessions["test-session"] = session

        return appState
    }

    @Test func handleFinishEvent_setsSessionCompleted() throws {
        let appState = try makeAppState()
        appState.sessionStatus = .running

        let event = OpenCodeEvent(
            kind: .finish,
            rawJson: "",
            text: "Completed",
            sessionId: "test-session"
        )

        appState.handle(event: event)

        #expect(appState.sessionStatus == .completed)
        #expect(appState.menuBarState == .idle)
        #expect(appState.currentToolName == nil)
    }

    @Test func handleErrorEvent_setsSessionFailed() throws {
        let appState = try makeAppState()
        appState.sessionStatus = .running

        let event = OpenCodeEvent(
            kind: .error,
            rawJson: "",
            text: "Something went wrong",
            sessionId: "test-session"
        )

        appState.handle(event: event)

        #expect(appState.sessionStatus == .failed)
        #expect(appState.lastErrorMessage == "Something went wrong")
        #expect(appState.menuBarState == .idle)
        #expect(appState.currentToolName == nil)
    }

    @Test func handleToolEvent_updatesToolState() throws {
        let appState = try makeAppState()
        appState.sessionStatus = .running

        let event = OpenCodeEvent(
            kind: .tool,
            rawJson: "",
            text: "/path/to/file.swift",
            toolName: "Read",
            toolInput: "/path/to/file.swift",
            sessionId: "test-session"
        )

        appState.handle(event: event)

        #expect(appState.menuBarState == .executing)
        #expect(appState.currentToolName == "Read")
        #expect(appState.currentToolInput == "/path/to/file.swift")
    }

    @Test func handleAssistantEvent_setsResponding() throws {
        let appState = try makeAppState()
        appState.sessionStatus = .running

        let event = OpenCodeEvent(
            kind: .assistant,
            rawJson: "",
            text: "Here is the answer...",
            sessionId: "test-session"
        )

        appState.handle(event: event)

        #expect(appState.menuBarState == .responding)
        #expect(appState.currentToolName == nil)
    }

    @Test func handleThoughtEvent_setsReasoning() throws {
        let appState = try makeAppState()
        appState.sessionStatus = .running

        let event = OpenCodeEvent(
            kind: .thought,
            rawJson: "",
            text: "Let me think about this...",
            sessionId: "test-session"
        )

        appState.handle(event: event)

        #expect(appState.menuBarState == .reasoning)
        #expect(appState.currentReasoningText == "Let me think about this...")
    }

    @Test func interruptedSession_ignoresSubsequentEvents() throws {
        let appState = try makeAppState()
        appState.sessionStatus = .interrupted

        let event = OpenCodeEvent(
            kind: .assistant,
            rawJson: "",
            text: "This should be ignored",
            sessionId: "test-session"
        )

        appState.handle(event: event)

        // Should remain interrupted, not switch to responding
        #expect(appState.sessionStatus == .interrupted)
        #expect(appState.menuBarState != .responding)
    }
}
