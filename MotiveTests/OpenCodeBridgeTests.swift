import Foundation
@testable import Motive
import Testing

/// Tests for OpenCodeBridge's session tracking, event routing, and text accumulation.
struct OpenCodeBridgeTests {

    /// Helper: create a bridge with an AsyncStream that collects events.
    private func makeBridge() -> (bridge: OpenCodeBridge, events: AsyncStream<OpenCodeEvent>) {
        let (stream, continuation) = AsyncStream.makeStream(of: OpenCodeEvent.self)
        let bridge = OpenCodeBridge(eventContinuation: continuation)
        return (bridge, stream)
    }

    // MARK: - Session Management

    @Test func bridgeStartsWithNoSession() async {
        let (bridge, _) = makeBridge()
        let sessionId = await bridge.getSessionId()
        #expect(sessionId == nil)
    }

    @Test func setSessionIdTracksSession() async {
        let (bridge, _) = makeBridge()
        await bridge.setSessionId("sess-1")
        let sessionId = await bridge.getSessionId()
        #expect(sessionId == "sess-1")
    }

    @Test func setSessionIdReplacesOldSession() async {
        let (bridge, _) = makeBridge()
        await bridge.setSessionId("sess-1")
        await bridge.setSessionId("sess-2")
        let sessionId = await bridge.getSessionId()
        #expect(sessionId == "sess-2")
    }

    @Test func clearSessionIdSetsNil() async {
        let (bridge, _) = makeBridge()
        await bridge.setSessionId("sess-1")
        await bridge.setSessionId(nil)
        let sessionId = await bridge.getSessionId()
        #expect(sessionId == nil)
    }

    // MARK: - Configuration

    @Test func bridgeAcceptsConfiguration() async {
        let (bridge, events) = makeBridge()

        let config = OpenCodeBridge.Configuration(
            binaryURL: URL(fileURLWithPath: "/usr/local/bin/opencode"),
            environment: ["HOME": "/Users/test"],
            model: "anthropic/claude-sonnet-4-5-20250929",
            agent: nil,
            debugMode: false,
            projectDirectory: "/Users/test/project"
        )

        await bridge.updateConfiguration(config)
        // Configuration update should not produce events — stream should be empty
        // (We can't easily check emptiness of an AsyncStream, but at least verify no crash)
        _ = events // suppress unused warning
    }

    // MARK: - Submit Without Configuration

    @Test func submitIntentWithoutConfigProducesError() async {
        let (bridge, events) = makeBridge()

        await bridge.submitIntent(text: "hello", cwd: "/tmp")

        // Collect the error event from the stream
        var collected: [OpenCodeEvent] = []
        for await event in events {
            collected.append(event)
            break // Only need the first event
        }

        #expect(collected.count == 1)
        #expect(collected[0].kind == .error)
        #expect(collected[0].text.contains("not configured"))
    }

    // MARK: - Event Handler Callback

    @Test func eventHandlerReceivesEvents() async {
        let (bridge, events) = makeBridge()

        // Without a running server, submitting will produce an error event
        await bridge.submitIntent(text: "test", cwd: "/tmp")

        var receivedEvents: [OpenCodeEvent] = []
        for await event in events {
            receivedEvents.append(event)
            break // Only need the first event
        }

        #expect(!receivedEvents.isEmpty, "Event handler should receive events")
    }

    // MARK: - OpenCodeEvent Construction for SSE Events

    @Test func textDeltaCreatesAssistantEvent() {
        let event = OpenCodeEvent(
            kind: .assistant,
            rawJson: "",
            text: "Hello ",
            sessionId: "sess-1"
        )

        #expect(event.kind == .assistant)
        #expect(event.text == "Hello ")
        #expect(event.sessionId == "sess-1")
    }

    @Test func toolRunningCreatesToolEvent() {
        let event = OpenCodeEvent(
            kind: .tool,
            rawJson: "",
            text: "/tmp/test.txt",
            toolName: "Read",
            toolInput: "/tmp/test.txt",
            toolCallId: "call-1",
            sessionId: "sess-1"
        )

        #expect(event.kind == .tool)
        #expect(event.toolName == "Read")
        #expect(event.toolInput == "/tmp/test.txt")
        #expect(event.toolCallId == "call-1")

        let message = event.toMessage()
        #expect(message?.type == .tool)
        #expect(message?.status == .running)
    }

    @Test func toolCompletedCreatesCompletedToolEvent() {
        let event = OpenCodeEvent(
            kind: .tool,
            rawJson: "",
            text: "/tmp/test.txt",
            toolName: "Read",
            toolInput: "/tmp/test.txt",
            toolOutput: "file contents here",
            toolCallId: "call-1",
            sessionId: "sess-1"
        )

        let message = event.toMessage()
        #expect(message?.status == .completed)
        #expect(message?.toolOutput == "file contents here")
    }

    @Test func sessionIdleCreatesFinishEvent() {
        let event = OpenCodeEvent(
            kind: .finish,
            rawJson: "",
            text: "Completed",
            sessionId: "sess-1"
        )

        #expect(event.kind == .finish)
        let message = event.toMessage()
        #expect(message?.type == .system)
        #expect(message?.status == .completed)
    }

    @Test func sessionErrorCreatesErrorEvent() {
        let event = OpenCodeEvent(
            kind: .error,
            rawJson: "",
            text: "Rate limit exceeded",
            sessionId: "sess-1"
        )

        #expect(event.kind == .error)
        let message = event.toMessage()
        #expect(message?.type == .system)
        #expect(message?.status == .failed)
    }

    // MARK: - Question Event Construction

    @Test func questionEventCarriesInputDict() {
        let inputDict: [String: Any] = [
            "_nativeQuestionID": "q-1",
            "_isNativeQuestion": true,
            "question": "How to proceed?",
            "custom": true,
            "multiple": false,
            "options": [
                ["label": "Option A", "description": "First option"],
                ["label": "Option B"],
            ],
        ]

        let event = OpenCodeEvent(
            kind: .tool,
            rawJson: "{}",
            text: "How to proceed?",
            toolName: "Question",
            toolInput: "How to proceed?",
            toolInputJSON: OpenCodeEvent.serializeJSON(inputDict),
            sessionId: "sess-1"
        )

        #expect(event.toolName == "Question")
        #expect(event.toolInputDict?["_isNativeQuestion"] as? Bool == true)
        #expect(event.toolInputDict?["_nativeQuestionID"] as? String == "q-1")
    }

    // MARK: - Permission Event Construction

    @Test func permissionEventCarriesInputDict() {
        let inputDict: [String: Any] = [
            "_nativePermissionID": "p-1",
            "_isNativePermission": true,
            "permission": "edit",
            "patterns": ["src/main.ts"],
            "metadata": ["diff": "changes here"],
            "always": ["src/**"],
        ]

        let event = OpenCodeEvent(
            kind: .tool,
            rawJson: "{}",
            text: "Permission: edit for src/main.ts",
            toolName: "Permission",
            toolInput: "src/main.ts",
            toolInputJSON: OpenCodeEvent.serializeJSON(inputDict),
            sessionId: "sess-1"
        )

        #expect(event.toolName == "Permission")
        #expect(event.toolInputDict?["_isNativePermission"] as? Bool == true)
        #expect(event.toolInputDict?["_nativePermissionID"] as? String == "p-1")
        #expect(event.toolInputDict?["permission"] as? String == "edit")
    }
}
