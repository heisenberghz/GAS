//
//  MessageStore.swift
//  Motive
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class MessageStore: ObservableObject {
    @Published var messages: [ConversationMessage] = []

    // MARK: - Message Insertion

    /// Insert an event into the live messages array.
    /// Handles streaming merge for assistant deltas, tool lifecycle, and finish deduplication.
    func insertEventMessage(_ event: OpenCodeEvent) {
        insertEventIntoBuffer(event, buffer: &messages)
    }

    /// Insert an event into an arbitrary message buffer.
    /// Same logic as insertEventMessage but targets a passed-in array (for parallel sessions).
    func insertEventIntoBuffer(_ event: OpenCodeEvent, buffer: inout [ConversationMessage]) {
        // Skip empty/unparseable events
        if event.kind == .unknown, event.text.isEmpty { return }
        guard let message = event.toMessage() else { return }

        // --- System / Finish deduplication ---
        if message.type == .system {
            if isCompletionText(message.content) {
                // Allow one "Completed" per turn: deduplicate only if no user message
                // has been sent since the last "Completed" (same turn).
                if let lastCompletedIdx = buffer.lastIndex(where: { $0.type == .system && isCompletionText($0.content) }) {
                    let hasUserMessageAfter = buffer[lastCompletedIdx...].contains { $0.type == .user }
                    if !hasUserMessageAfter { return }
                }
            }
        }

        // --- User messages ---
        if message.type == .user {
            buffer.append(message)
            return
        }

        // --- Assistant message streaming merge ---
        if message.type == .assistant {
            if let lastIndex = buffer.lastIndex(where: { $0.type == .assistant }),
               lastIndex == buffer.count - 1
            {
                buffer[lastIndex] = buffer[lastIndex].withContent(
                    buffer[lastIndex].content + message.content
                )
            } else {
                buffer.append(message)
            }
            return
        }

        // Reasoning is transient (handled via currentReasoningText), skip if it arrives here
        if message.type == .reasoning {
            return
        }

        // --- Tool message merge ---
        if message.type == .tool {
            processToolMessage(message, into: &buffer)
            return
        }

        // --- Everything else: append ---
        buffer.append(message)
    }

    /// Process tool messages with proper lifecycle: running -> completed
    func processToolMessage(_ message: ConversationMessage) {
        processToolMessage(message, into: &messages)
    }

    /// Process tool messages into a given buffer.
    func processToolMessage(_ message: ConversationMessage, into buffer: inout [ConversationMessage]) {
        // Strategy 1: Merge by toolCallId (most reliable)
        if let toolCallId = message.toolCallId,
           let idx = buffer.lastIndex(where: { $0.type == .tool && $0.toolCallId == toolCallId })
        {
            Log.debug("Tool merge [callId]: \(buffer[idx].toolName ?? "?") \(buffer[idx].status.rawValue) -> \(message.toolOutput != nil ? "completed" : buffer[idx].status.rawValue)")
            buffer[idx] = buffer[idx].mergingToolData(from: message)
        }
        // Strategy 2: Merge consecutive tool messages (fallback for missing toolCallId)
        else if let lastIdx = buffer.lastIndex(where: { $0.type == .tool }),
                lastIdx == buffer.count - 1,
                buffer[lastIdx].toolOutput == nil,
                message.toolOutput != nil,
                message.toolName == "Result" || message.toolName == buffer[lastIdx].toolName
        {
            Log.debug("Tool merge [consecutive]: \(buffer[lastIdx].toolName ?? "?") -> completed")
            buffer[lastIdx] = buffer[lastIdx].mergingToolData(from: message)
        }
        // No merge target — append as new message
        else {
            Log.debug("Tool append [new]: \(message.toolName ?? "?") status=\(message.status.rawValue) hasOutput=\(message.toolOutput != nil)")
            buffer.append(message)
        }
    }

    /// Check if text represents a completion message
    func isCompletionText(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower == "completed"
            || lower == "session idle"
            || lower == "task completed"
            || lower.hasPrefix("task completed with exit code")
    }

    // MARK: - TodoWrite Handling

    func handleTodoWriteEvent(_ event: OpenCodeEvent) {
        handleTodoWriteEvent(event, buffer: &messages)
    }

    func handleTodoWriteEvent(_ event: OpenCodeEvent, buffer: inout [ConversationMessage]) {
        let todoItems = parseTodoItems(from: event)
        guard !todoItems.isEmpty else {
            Log.debug("TodoWrite: no items parsed from event, skipping")
            finalizeTodoWriteToolMessages(event: event, buffer: &buffer)
            return
        }

        let merge = parseTodoMerge(from: event)
        Log.debug("TodoWrite: \(todoItems.count) items, merge=\(merge)")
        for item in todoItems {
            Log.debug("  todo[\(item.id)]: status=\(item.status.rawValue), content=\"\(item.content.prefix(40))\"")
        }

        if let existingIndex = buffer.lastIndex(where: { $0.type == .todo }) {
            let existing = buffer[existingIndex]
            let finalItems: [TodoItem]
            if merge, let existingItems = existing.todoItems {
                var itemMap = Dictionary(uniqueKeysWithValues: existingItems.map { ($0.id, $0) })
                for item in todoItems {
                    if let existingItem = itemMap[item.id], item.content.isEmpty {
                        itemMap[item.id] = TodoItem(id: item.id, content: existingItem.content, status: item.status)
                    } else {
                        itemMap[item.id] = item
                    }
                }
                finalItems = itemMap.values.sorted { $0.id < $1.id }
            } else {
                finalItems = todoItems
            }
            buffer[existingIndex] = existing.withTodos(finalItems, summary: todoSummary(finalItems))
        } else {
            buffer.append(ConversationMessage(
                type: .todo, content: todoSummary(todoItems),
                status: .completed, todoItems: todoItems
            ))
        }

        finalizeTodoWriteToolMessages(event: event, buffer: &buffer)
    }

    /// Mark any `.tool` messages belonging to TodoWrite as `.completed`.
    func finalizeTodoWriteToolMessages(event: OpenCodeEvent) {
        finalizeTodoWriteToolMessages(event: event, buffer: &messages)
    }

    func finalizeTodoWriteToolMessages(event: OpenCodeEvent, buffer: inout [ConversationMessage]) {
        for i in buffer.indices where buffer[i].type == .tool && buffer[i].status == .running {
            let matchesByCallId = event.toolCallId != nil
                && buffer[i].toolCallId == event.toolCallId
            let matchesByName = buffer[i].toolName?.isTodoWriteTool == true
            if matchesByCallId || matchesByName {
                Log.debug("TodoWrite: finalizing stale .tool message at index \(i)")
                buffer[i] = buffer[i].withStatus(.completed)
            }
        }
    }

    func parseTodoItems(from event: OpenCodeEvent) -> [TodoItem] {
        if let inputDict = event.toolInputDict {
            return parseTodoItemsFromDict(inputDict)
        }

        guard let data = event.rawJson.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let part = object["part"] as? [String: Any]
        else {
            return []
        }

        if let input = extractToolInput(from: part) {
            return parseTodoItemsFromDict(input)
        }
        if let state = part["state"] as? [String: Any],
           let input = extractToolInput(from: state)
        {
            return parseTodoItemsFromDict(input)
        }

        return []
    }

    func parseTodoMerge(from event: OpenCodeEvent) -> Bool {
        if let inputDict = event.toolInputDict {
            return inputDict["merge"] as? Bool ?? false
        }
        guard let data = event.rawJson.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let part = object["part"] as? [String: Any]
        else {
            return false
        }
        if let input = extractToolInput(from: part) {
            return input["merge"] as? Bool ?? false
        }
        if let state = part["state"] as? [String: Any],
           let input = extractToolInput(from: state)
        {
            return input["merge"] as? Bool ?? false
        }
        return false
    }

    /// Extract tool input dictionary from a container (used by TodoWrite parsing).
    func extractToolInput(from container: [String: Any]) -> [String: Any]? {
        let keys = ["input", "arguments", "args"]
        for key in keys {
            if let dict = container[key] as? [String: Any] { return dict }
        }
        for key in keys {
            if let str = container[key] as? String,
               let data = str.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            {
                return dict
            }
        }
        return nil
    }

    func parseTodoItemsFromDict(_ dict: [String: Any]) -> [TodoItem] {
        guard let todosArray = dict["todos"] as? [[String: Any]] else {
            return []
        }
        return todosArray.compactMap { TodoItem(from: $0) }
    }

    func todoSummary(_ items: [TodoItem]) -> String {
        let completed = items.count(where: { $0.status == .completed })
        let total = items.count
        return "\(completed)/\(total) tasks completed"
    }

    // MARK: - Dedup-Safe Append (for NativePromptHandler)

    /// Append a message to the live messages array, guarded by toolCallId dedup.
    /// If a message with the same toolCallId already exists, the append is skipped.
    func appendMessageIfNeeded(_ message: ConversationMessage) {
        appendMessageIfNeeded(message, to: &messages)
    }

    /// Append a message to a given buffer, guarded by toolCallId dedup.
    func appendMessageIfNeeded(_ message: ConversationMessage, to buffer: inout [ConversationMessage]) {
        if let callId = message.toolCallId, !callId.isEmpty {
            if buffer.contains(where: { $0.toolCallId == callId }) {
                Log.debug("Dedup: skipping duplicate message for toolCallId=\(callId)")
                return
            }
        }
        buffer.append(message)
    }

    // MARK: - Question/Permission Message Updates

    /// Update the pending question/permission message with the user's response.
    func updateQuestionMessage(messageId: UUID?, response: String) {
        updateQuestionMessage(messageId: messageId, response: response, in: &messages)
    }

    func updateQuestionMessage(messageId: UUID?, response: String, in buffer: inout [ConversationMessage]) {
        guard let messageId,
              let index = buffer.firstIndex(where: { $0.id == messageId }) else { return }
        let existing = buffer[index]
        let displayResponse = response.isEmpty ? "User declined to answer." : response
        buffer[index] = ConversationMessage(
            id: existing.id,
            type: .tool,
            content: existing.content,
            timestamp: existing.timestamp,
            toolName: existing.toolName,
            toolInput: existing.toolInput,
            toolOutput: displayResponse,
            toolCallId: existing.toolCallId,
            status: .completed
        )
    }

    // MARK: - Tool Lifecycle Helpers

    /// When a step/task finishes, mark any still-running tool messages as completed
    /// and finalize todo item statuses.
    func finalizeRunningMessages() {
        finalizeRunningMessages(in: &messages)
    }

    func finalizeRunningMessages(in buffer: inout [ConversationMessage]) {
        for i in buffer.indices {
            if buffer[i].type == .tool, buffer[i].status == .running {
                buffer[i] = buffer[i].withStatus(.completed)
            } else if buffer[i].type == .todo, let items = buffer[i].todoItems {
                let finalized = items.map { item -> TodoItem in
                    switch item.status {
                    case .inProgress, .pending:
                        TodoItem(id: item.id, content: item.content, status: .completed)
                    case .completed, .cancelled:
                        item
                    }
                }
                if finalized != items {
                    buffer[i] = buffer[i].withTodos(finalized, summary: todoSummary(finalized))
                }
            }
        }
    }
}
