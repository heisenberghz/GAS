//
//  MessageStoreTests.swift
//  MotiveTests
//
//  Unit tests for MessageStore message insertion, merging, deduplication, and lifecycle management.
//

@testable import Motive
import XCTest

@MainActor
final class MessageStoreTests: XCTestCase {

    var store: MessageStore!

    override func setUp() {
        super.setUp()
        store = MessageStore()
    }

    override func tearDown() {
        store = nil
        super.tearDown()
    }

    // MARK: - 1. Message Insertion Order

    func testUserMessagesAppendedInOrder() {
        let event1 = OpenCodeEvent(kind: .user, rawJson: "", text: "First message")
        let event2 = OpenCodeEvent(kind: .user, rawJson: "", text: "Second message")
        let event3 = OpenCodeEvent(kind: .user, rawJson: "", text: "Third message")

        store.insertEventMessage(event1)
        store.insertEventMessage(event2)
        store.insertEventMessage(event3)

        XCTAssertEqual(store.messages.count, 3)
        XCTAssertEqual(store.messages[0].content, "First message")
        XCTAssertEqual(store.messages[1].content, "Second message")
        XCTAssertEqual(store.messages[2].content, "Third message")
    }

    func testUserMessagesHaveCorrectType() {
        let event = OpenCodeEvent(kind: .user, rawJson: "", text: "Hello")
        store.insertEventMessage(event)

        XCTAssertEqual(store.messages.count, 1)
        XCTAssertEqual(store.messages[0].type, .user)
    }

    func testMixedMessageTypesPreserveOrder() {
        let userEvent = OpenCodeEvent(kind: .user, rawJson: "", text: "User prompt")
        let assistantEvent = OpenCodeEvent(kind: .assistant, rawJson: "", text: "Response")
        let finishEvent = OpenCodeEvent(kind: .finish, rawJson: "", text: "Completed")

        store.insertEventMessage(userEvent)
        store.insertEventMessage(assistantEvent)
        store.insertEventMessage(finishEvent)

        XCTAssertEqual(store.messages.count, 3)
        XCTAssertEqual(store.messages[0].type, .user)
        XCTAssertEqual(store.messages[1].type, .assistant)
        XCTAssertEqual(store.messages[2].type, .system)
    }

    func testEmptyUnknownEventIsSkipped() {
        let event = OpenCodeEvent(kind: .unknown, rawJson: "", text: "")
        store.insertEventMessage(event)

        XCTAssertEqual(store.messages.count, 0)
    }

    func testAssistantEventWithEmptyTextIsSkipped() {
        // toMessage() returns nil for empty text on non-finish, non-error, non-tool events
        let event = OpenCodeEvent(kind: .assistant, rawJson: "", text: "")
        store.insertEventMessage(event)

        XCTAssertEqual(store.messages.count, 0)
    }

    // MARK: - 2. Streaming Merge (Consecutive Assistant Messages)

    func testConsecutiveAssistantMessagesAreMerged() {
        let event1 = OpenCodeEvent(kind: .assistant, rawJson: "", text: "Hello ")
        let event2 = OpenCodeEvent(kind: .assistant, rawJson: "", text: "world!")

        store.insertEventMessage(event1)
        store.insertEventMessage(event2)

        XCTAssertEqual(store.messages.count, 1)
        XCTAssertEqual(store.messages[0].content, "Hello world!")
        XCTAssertEqual(store.messages[0].type, .assistant)
    }

    func testMultipleAssistantChunksMergedIntoOne() {
        let chunks = ["The ", "quick ", "brown ", "fox"]
        for chunk in chunks {
            let event = OpenCodeEvent(kind: .assistant, rawJson: "", text: chunk)
            store.insertEventMessage(event)
        }

        XCTAssertEqual(store.messages.count, 1)
        XCTAssertEqual(store.messages[0].content, "The quick brown fox")
    }

    func testAssistantMergeBreaksWhenNonAssistantIntervenes() {
        let assistantEvent1 = OpenCodeEvent(kind: .assistant, rawJson: "", text: "Part 1")
        let userEvent = OpenCodeEvent(kind: .user, rawJson: "", text: "Interruption")
        let assistantEvent2 = OpenCodeEvent(kind: .assistant, rawJson: "", text: "Part 2")

        store.insertEventMessage(assistantEvent1)
        store.insertEventMessage(userEvent)
        store.insertEventMessage(assistantEvent2)

        // assistant, user, assistant -- should NOT merge the two assistant messages
        XCTAssertEqual(store.messages.count, 3)
        XCTAssertEqual(store.messages[0].content, "Part 1")
        XCTAssertEqual(store.messages[0].type, .assistant)
        XCTAssertEqual(store.messages[1].content, "Interruption")
        XCTAssertEqual(store.messages[1].type, .user)
        XCTAssertEqual(store.messages[2].content, "Part 2")
        XCTAssertEqual(store.messages[2].type, .assistant)
    }

    func testAssistantMergeBreaksWhenToolIntervenes() {
        let assistantEvent = OpenCodeEvent(kind: .assistant, rawJson: "", text: "Before tool")

        // Insert a tool message directly to simulate a tool arriving between assistant chunks
        store.insertEventMessage(assistantEvent)
        let toolMsg = ConversationMessage(type: .tool, content: "Reading file", toolName: "Read", toolInput: "/tmp/test.txt", status: .running)
        store.messages.append(toolMsg)

        let assistantEvent2 = OpenCodeEvent(kind: .assistant, rawJson: "", text: "After tool")
        store.insertEventMessage(assistantEvent2)

        // The second assistant should be a NEW message, not merged into the first
        XCTAssertEqual(store.messages.count, 3)
        XCTAssertEqual(store.messages[0].content, "Before tool")
        XCTAssertEqual(store.messages[1].type, .tool)
        XCTAssertEqual(store.messages[2].content, "After tool")
    }

    // MARK: - 3. Tool Message Merge by toolCallId

    func testToolCallAndResultMergedByToolCallId() {
        let callId = "call_abc123"

        // Simulate a tool_call event (no output, running)
        let callEvent = OpenCodeEvent(
            kind: .tool, rawJson: "", text: "/tmp/test.txt",
            toolName: "Read", toolInput: "/tmp/test.txt", toolCallId: callId
        )
        store.insertEventMessage(callEvent)

        XCTAssertEqual(store.messages.count, 1)
        XCTAssertEqual(store.messages[0].status, .running)
        XCTAssertNil(store.messages[0].toolOutput)

        // Simulate a tool_result event (has output, same callId)
        let resultEvent = OpenCodeEvent(
            kind: .tool, rawJson: "", text: "",
            toolName: "Result", toolOutput: "file contents here", toolCallId: callId
        )
        store.insertEventMessage(resultEvent)

        // Should merge into single message, not append
        XCTAssertEqual(store.messages.count, 1)
        XCTAssertEqual(store.messages[0].toolOutput, "file contents here")
        XCTAssertEqual(store.messages[0].status, .completed)
        XCTAssertEqual(store.messages[0].toolName, "Read")
        XCTAssertEqual(store.messages[0].toolInput, "/tmp/test.txt")
    }

    func testToolCallsWithDifferentIdsNotMerged() {
        let callEvent1 = OpenCodeEvent(
            kind: .tool, rawJson: "", text: "/tmp/a.txt",
            toolName: "Read", toolInput: "/tmp/a.txt", toolCallId: "call_001"
        )
        let callEvent2 = OpenCodeEvent(
            kind: .tool, rawJson: "", text: "/tmp/b.txt",
            toolName: "Read", toolInput: "/tmp/b.txt", toolCallId: "call_002"
        )

        store.insertEventMessage(callEvent1)
        store.insertEventMessage(callEvent2)

        XCTAssertEqual(store.messages.count, 2)
        XCTAssertEqual(store.messages[0].toolInput, "/tmp/a.txt")
        XCTAssertEqual(store.messages[1].toolInput, "/tmp/b.txt")
    }

    func testToolResultMergesIntoCorrectCallById() {
        let callEvent1 = OpenCodeEvent(
            kind: .tool, rawJson: "", text: "/tmp/a.txt",
            toolName: "Read", toolInput: "/tmp/a.txt", toolCallId: "call_001"
        )
        let callEvent2 = OpenCodeEvent(
            kind: .tool, rawJson: "", text: "/tmp/b.txt",
            toolName: "Read", toolInput: "/tmp/b.txt", toolCallId: "call_002"
        )

        store.insertEventMessage(callEvent1)
        store.insertEventMessage(callEvent2)

        // Result for the FIRST call
        let resultEvent = OpenCodeEvent(
            kind: .tool, rawJson: "", text: "",
            toolName: "Result", toolOutput: "contents of A", toolCallId: "call_001"
        )
        store.insertEventMessage(resultEvent)

        XCTAssertEqual(store.messages.count, 2)
        XCTAssertEqual(store.messages[0].toolOutput, "contents of A")
        XCTAssertEqual(store.messages[0].status, .completed)
        // Second call is still running
        XCTAssertNil(store.messages[1].toolOutput)
        XCTAssertEqual(store.messages[1].status, .running)
    }

    func testConsecutiveToolMergeFallback() {
        // When toolCallId is nil, consecutive tool messages merge by name match
        let callEvent = OpenCodeEvent(
            kind: .tool, rawJson: "", text: "echo hello",
            toolName: "Shell", toolInput: "echo hello"
        )
        store.insertEventMessage(callEvent)

        XCTAssertEqual(store.messages.count, 1)
        XCTAssertNil(store.messages[0].toolOutput)

        // Result with name "Result" (no callId) merges into last consecutive tool
        let resultEvent = OpenCodeEvent(
            kind: .tool, rawJson: "", text: "",
            toolName: "Result", toolOutput: "hello"
        )
        store.insertEventMessage(resultEvent)

        XCTAssertEqual(store.messages.count, 1)
        XCTAssertEqual(store.messages[0].toolOutput, "hello")
        XCTAssertEqual(store.messages[0].status, .completed)
    }

    func testToolWithNoMergeTargetIsAppended() {
        // An assistant message is the last item, so a tool with no callId has no merge target
        let assistantEvent = OpenCodeEvent(kind: .assistant, rawJson: "", text: "Thinking...")
        store.insertEventMessage(assistantEvent)

        let toolEvent = OpenCodeEvent(
            kind: .tool, rawJson: "", text: "ls -la",
            toolName: "Shell", toolInput: "ls -la"
        )
        store.insertEventMessage(toolEvent)

        XCTAssertEqual(store.messages.count, 2)
        XCTAssertEqual(store.messages[1].type, .tool)
        XCTAssertEqual(store.messages[1].toolName, "Shell")
    }

    // MARK: - 4. System/Finish Deduplication

    func testCompletionSystemMessageNotDuplicated() {
        let finishEvent1 = OpenCodeEvent(kind: .finish, rawJson: "", text: "Completed")
        let finishEvent2 = OpenCodeEvent(kind: .finish, rawJson: "", text: "Completed")

        store.insertEventMessage(finishEvent1)
        store.insertEventMessage(finishEvent2)

        // Only one completion message should exist
        let systemMessages = store.messages.filter { $0.type == .system }
        XCTAssertEqual(systemMessages.count, 1)
    }

    func testSecondaryFinishEventIsSkipped() {
        let secondaryFinish = OpenCodeEvent(
            kind: .finish, rawJson: "", text: "Session idle",
            isSecondaryFinish: true
        )
        store.insertEventMessage(secondaryFinish)

        XCTAssertEqual(store.messages.count, 0)
    }

    func testDifferentCompletionTextsAreDeduplicated() {
        // "Completed" and "Task completed" are both completion texts
        let finishEvent1 = OpenCodeEvent(kind: .finish, rawJson: "", text: "Completed")
        let finishEvent2 = OpenCodeEvent(kind: .finish, rawJson: "", text: "Task completed")

        store.insertEventMessage(finishEvent1)
        store.insertEventMessage(finishEvent2)

        let systemMessages = store.messages.filter { $0.type == .system }
        XCTAssertEqual(systemMessages.count, 1)
        XCTAssertEqual(systemMessages[0].content, "Completed")
    }

    func testNonCompletionSystemMessagesAreNotDeduplicated() {
        // Error messages are system type but NOT completion text, so they should not be deduped
        let errorEvent1 = OpenCodeEvent(kind: .error, rawJson: "", text: "Error occurred")
        let errorEvent2 = OpenCodeEvent(kind: .error, rawJson: "", text: "Another error")

        store.insertEventMessage(errorEvent1)
        store.insertEventMessage(errorEvent2)

        let systemMessages = store.messages.filter { $0.type == .system }
        XCTAssertEqual(systemMessages.count, 2)
    }

    // MARK: - 5. isCompletionText

    func testIsCompletionTextCompleted() {
        XCTAssertTrue(store.isCompletionText("completed"))
        XCTAssertTrue(store.isCompletionText("Completed"))
        XCTAssertTrue(store.isCompletionText("COMPLETED"))
    }

    func testIsCompletionTextSessionIdle() {
        XCTAssertTrue(store.isCompletionText("session idle"))
        XCTAssertTrue(store.isCompletionText("Session Idle"))
        XCTAssertTrue(store.isCompletionText("SESSION IDLE"))
    }

    func testIsCompletionTextTaskCompleted() {
        XCTAssertTrue(store.isCompletionText("task completed"))
        XCTAssertTrue(store.isCompletionText("Task Completed"))
        XCTAssertTrue(store.isCompletionText("TASK COMPLETED"))
    }

    func testIsCompletionTextWithExitCode() {
        XCTAssertTrue(store.isCompletionText("task completed with exit code 0"))
        XCTAssertTrue(store.isCompletionText("Task Completed with Exit Code 1"))
        XCTAssertTrue(store.isCompletionText("task completed with exit code 137"))
    }

    func testIsCompletionTextReturnsFalseForNonCompletion() {
        XCTAssertFalse(store.isCompletionText("Processing..."))
        XCTAssertFalse(store.isCompletionText("Hello world"))
        XCTAssertFalse(store.isCompletionText(""))
        XCTAssertFalse(store.isCompletionText("Error occurred"))
        XCTAssertFalse(store.isCompletionText("still running"))
        XCTAssertFalse(store.isCompletionText("complete")) // not "completed"
    }

    // MARK: - 6. todoSummary

    func testTodoSummaryAllPending() {
        let items = [
            TodoItem(id: "1", content: "Task A", status: .pending),
            TodoItem(id: "2", content: "Task B", status: .pending),
            TodoItem(id: "3", content: "Task C", status: .pending),
        ]
        XCTAssertEqual(store.todoSummary(items), "0/3 tasks completed")
    }

    func testTodoSummaryAllCompleted() {
        let items = [
            TodoItem(id: "1", content: "Task A", status: .completed),
            TodoItem(id: "2", content: "Task B", status: .completed),
        ]
        XCTAssertEqual(store.todoSummary(items), "2/2 tasks completed")
    }

    func testTodoSummaryMixedStatuses() {
        let items = [
            TodoItem(id: "1", content: "Done task", status: .completed),
            TodoItem(id: "2", content: "In progress task", status: .inProgress),
            TodoItem(id: "3", content: "Pending task", status: .pending),
            TodoItem(id: "4", content: "Cancelled task", status: .cancelled),
        ]
        XCTAssertEqual(store.todoSummary(items), "1/4 tasks completed")
    }

    func testTodoSummarySingleItem() {
        let items = [
            TodoItem(id: "1", content: "Only task", status: .completed),
        ]
        XCTAssertEqual(store.todoSummary(items), "1/1 tasks completed")
    }

    func testTodoSummaryEmptyList() {
        let items: [TodoItem] = []
        XCTAssertEqual(store.todoSummary(items), "0/0 tasks completed")
    }

    // MARK: - 7. updateQuestionMessage

    func testUpdateQuestionMessageSetsResponseText() {
        let messageId = UUID()
        let questionMsg = ConversationMessage(
            id: messageId, type: .tool, content: "What color?",
            toolName: "Question", toolInput: "What color?", status: .running
        )
        store.messages.append(questionMsg)

        store.updateQuestionMessage(messageId: messageId, response: "Blue")

        XCTAssertEqual(store.messages.count, 1)
        XCTAssertEqual(store.messages[0].toolOutput, "Blue")
        XCTAssertEqual(store.messages[0].status, .completed)
        XCTAssertEqual(store.messages[0].content, "What color?")
        XCTAssertEqual(store.messages[0].id, messageId)
    }

    func testUpdateQuestionMessageEmptyResponseShowsDeclined() {
        let messageId = UUID()
        let questionMsg = ConversationMessage(
            id: messageId, type: .tool, content: "Continue?",
            toolName: "Question", toolInput: "Continue?", status: .running
        )
        store.messages.append(questionMsg)

        store.updateQuestionMessage(messageId: messageId, response: "")

        XCTAssertEqual(store.messages[0].toolOutput, "User declined to answer.")
        XCTAssertEqual(store.messages[0].status, .completed)
    }

    func testUpdateQuestionMessageWithNilIdDoesNothing() {
        let questionMsg = ConversationMessage(
            type: .tool, content: "Continue?",
            toolName: "Question", status: .running
        )
        store.messages.append(questionMsg)

        store.updateQuestionMessage(messageId: nil, response: "Yes")

        // Message should be unchanged
        XCTAssertEqual(store.messages[0].status, .running)
        XCTAssertNil(store.messages[0].toolOutput)
    }

    func testUpdateQuestionMessageWithNonExistentIdDoesNothing() {
        let messageId = UUID()
        let questionMsg = ConversationMessage(
            id: messageId, type: .tool, content: "Continue?",
            toolName: "Question", status: .running
        )
        store.messages.append(questionMsg)

        let wrongId = UUID()
        store.updateQuestionMessage(messageId: wrongId, response: "Yes")

        // Message should be unchanged
        XCTAssertEqual(store.messages[0].status, .running)
        XCTAssertNil(store.messages[0].toolOutput)
    }

    func testUpdateQuestionMessagePreservesOriginalFields() {
        let messageId = UUID()
        let callId = "call_q1"
        let questionMsg = ConversationMessage(
            id: messageId, type: .tool, content: "Pick an option",
            toolName: "Question", toolInput: "Pick an option", toolCallId: callId, status: .running
        )
        store.messages.append(questionMsg)

        store.updateQuestionMessage(messageId: messageId, response: "Option A")

        XCTAssertEqual(store.messages[0].toolName, "Question")
        XCTAssertEqual(store.messages[0].toolInput, "Pick an option")
        XCTAssertEqual(store.messages[0].toolCallId, callId)
        XCTAssertEqual(store.messages[0].toolOutput, "Option A")
    }

    // MARK: - 8. finalizeRunningMessages

    func testFinalizeRunningMessagesMarksToolsAsCompleted() {
        let toolMsg1 = ConversationMessage(
            type: .tool, content: "Reading file",
            toolName: "Read", toolInput: "/tmp/a.txt", status: .running
        )
        let toolMsg2 = ConversationMessage(
            type: .tool, content: "Executing command",
            toolName: "Shell", toolInput: "ls", status: .running
        )
        store.messages.append(toolMsg1)
        store.messages.append(toolMsg2)

        store.finalizeRunningMessages()

        XCTAssertEqual(store.messages[0].status, .completed)
        XCTAssertEqual(store.messages[1].status, .completed)
    }

    func testFinalizeRunningMessagesDoesNotAffectCompletedTools() {
        let completedMsg = ConversationMessage(
            type: .tool, content: "Done",
            toolName: "Read", toolOutput: "file contents", status: .completed
        )
        let runningMsg = ConversationMessage(
            type: .tool, content: "Still going",
            toolName: "Shell", status: .running
        )
        store.messages.append(completedMsg)
        store.messages.append(runningMsg)

        store.finalizeRunningMessages()

        XCTAssertEqual(store.messages[0].status, .completed)
        XCTAssertEqual(store.messages[0].toolOutput, "file contents")
        XCTAssertEqual(store.messages[1].status, .completed)
    }

    func testFinalizeRunningMessagesDoesNotAffectNonToolTypes() {
        let userMsg = ConversationMessage(type: .user, content: "Hello", status: .completed)
        let assistantMsg = ConversationMessage(type: .assistant, content: "Hi", status: .completed)
        let runningTool = ConversationMessage(
            type: .tool, content: "Working",
            toolName: "Shell", status: .running
        )
        store.messages.append(userMsg)
        store.messages.append(assistantMsg)
        store.messages.append(runningTool)

        store.finalizeRunningMessages()

        XCTAssertEqual(store.messages.count, 3)
        XCTAssertEqual(store.messages[0].type, .user)
        XCTAssertEqual(store.messages[1].type, .assistant)
        XCTAssertEqual(store.messages[2].status, .completed)
    }

    func testFinalizeRunningMessagesOnEmptyStore() {
        store.finalizeRunningMessages()
        XCTAssertEqual(store.messages.count, 0)
    }

    func testFinalizeRunningMessagesDoesNotAffectFailedTools() {
        let failedMsg = ConversationMessage(
            type: .tool, content: "Error",
            toolName: "Shell", status: .failed
        )
        store.messages.append(failedMsg)

        store.finalizeRunningMessages()

        // .failed should remain .failed (only .running is finalized)
        XCTAssertEqual(store.messages[0].status, .failed)
    }

    // MARK: - Reasoning Events Are Skipped

    func testReasoningEventsAreSkippedByInsertEventMessage() {
        // thought events produce .reasoning messages, which insertEventMessage discards
        let reasoningEvent = OpenCodeEvent(kind: .thought, rawJson: "", text: "Thinking about this...")
        store.insertEventMessage(reasoningEvent)

        XCTAssertEqual(store.messages.count, 0, "Reasoning messages should be skipped")
    }

    // MARK: - Integration: Full Conversation Flow

    func testFullConversationFlow() {
        // User sends a message
        let userEvent = OpenCodeEvent(kind: .user, rawJson: "", text: "Read my file")
        store.insertEventMessage(userEvent)

        // Assistant starts responding
        let assistantEvent1 = OpenCodeEvent(kind: .assistant, rawJson: "", text: "I'll read ")
        store.insertEventMessage(assistantEvent1)
        let assistantEvent2 = OpenCodeEvent(kind: .assistant, rawJson: "", text: "your file now.")
        store.insertEventMessage(assistantEvent2)

        // Tool call
        let toolCall = OpenCodeEvent(
            kind: .tool, rawJson: "", text: "/tmp/test.txt",
            toolName: "Read", toolInput: "/tmp/test.txt", toolCallId: "call_001"
        )
        store.insertEventMessage(toolCall)

        // Tool result
        let toolResult = OpenCodeEvent(
            kind: .tool, rawJson: "", text: "",
            toolName: "Result", toolOutput: "Hello World", toolCallId: "call_001"
        )
        store.insertEventMessage(toolResult)

        // Assistant continues (new message because tool intervened)
        let assistantEvent3 = OpenCodeEvent(kind: .assistant, rawJson: "", text: "The file contains 'Hello World'.")
        store.insertEventMessage(assistantEvent3)

        // Finish
        let finishEvent = OpenCodeEvent(kind: .finish, rawJson: "", text: "Completed")
        store.insertEventMessage(finishEvent)

        // Verify final state
        XCTAssertEqual(store.messages.count, 5)

        // 0: user
        XCTAssertEqual(store.messages[0].type, .user)
        XCTAssertEqual(store.messages[0].content, "Read my file")

        // 1: merged assistant
        XCTAssertEqual(store.messages[1].type, .assistant)
        XCTAssertEqual(store.messages[1].content, "I'll read your file now.")

        // 2: merged tool (call + result)
        XCTAssertEqual(store.messages[2].type, .tool)
        XCTAssertEqual(store.messages[2].toolName, "Read")
        XCTAssertEqual(store.messages[2].toolOutput, "Hello World")
        XCTAssertEqual(store.messages[2].status, .completed)

        // 3: new assistant (after tool)
        XCTAssertEqual(store.messages[3].type, .assistant)
        XCTAssertEqual(store.messages[3].content, "The file contains 'Hello World'.")

        // 4: system finish
        XCTAssertEqual(store.messages[4].type, .system)
    }
}
