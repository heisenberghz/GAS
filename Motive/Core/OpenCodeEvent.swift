//
//  OpenCodeEvent.swift
//  Motive
//
//  Created by geezerrrr on 2026/1/19.
//

import Foundation

// MARK: - Tool Name Display Mapping

extension String {
    /// Simplify tool names for better UI display
    var simplifiedToolName: String {
        switch self {
        case "ReadFile", "Read": "Read"
        case "WriteFile", "Write": "Write"
        case "EditFile", "Edit": "Edit"
        case "DeleteFile", "Delete": "Delete"
        case "ListFiles", "Glob": "List"
        case "SearchFiles", "Grep": "Search"
        case "Shell", "Bash": "Shell"
        case "TodoWrite", "todo_write": "Todo"
        default: self
        }
    }

    /// Whether this tool name represents a TodoWrite operation
    var isTodoWriteTool: Bool {
        let normalized = self.lowercased().filter { $0.isLetter || $0.isNumber }
        return normalized == "todowrite" || normalized.hasSuffix("todowrite")
    }
}

// MARK: - Todo Item Model

struct TodoItem: Identifiable, Sendable, Equatable, Codable {
    let id: String
    let content: String
    let status: Status

    enum Status: String, Sendable, Codable {
        case pending
        case inProgress = "in_progress"
        case completed
        case cancelled
    }

    /// Parse from dictionary (agent tool input format).
    /// Only `id` is required. `content` defaults to empty (preserved during merge).
    /// `status` defaults to `.pending` if missing or unrecognized.
    init?(from dict: [String: Any]) {
        guard let id = dict["id"] as? String else {
            return nil
        }
        self.id = id
        self.content = dict["content"] as? String ?? ""
        let statusStr = dict["status"] as? String ?? "pending"
        self.status = Status(rawValue: statusStr) ?? .pending
    }

    init(id: String, content: String, status: Status) {
        self.id = id
        self.content = content
        self.status = status
    }
}

// MARK: - Message Type for Conversation UI

struct ConversationMessage: Identifiable, Sendable, Codable {
    enum MessageType: String, Sendable, Codable {
        case user
        case assistant
        case tool
        case system
        case todo // Dedicated type for todo list display
        case reasoning // Reasoning/thinking stream
    }

    enum Status: String, Sendable, Codable {
        case pending // Created, not yet started
        case running // In progress (tool executing, step processing)
        case completed // Finished successfully
        case failed // Finished with error
    }

    let id: UUID
    let type: MessageType
    let content: String
    let timestamp: Date
    let toolName: String?
    let toolInput: String?
    let toolOutput: String?
    let toolCallId: String?
    let status: Status // Lifecycle status (replaces isStreaming)
    let todoItems: [TodoItem]? // Parsed todo items for .todo type
    let diffContent: String? // Unified diff for file-editing tools

    init(
        id: UUID = UUID(),
        type: MessageType,
        content: String,
        timestamp: Date = Date(),
        toolName: String? = nil,
        toolInput: String? = nil,
        toolOutput: String? = nil,
        toolCallId: String? = nil,
        status: Status = .completed,
        todoItems: [TodoItem]? = nil,
        diffContent: String? = nil
    ) {
        self.id = id
        self.type = type
        self.content = content
        self.timestamp = timestamp
        self.toolName = toolName
        self.toolInput = toolInput
        self.toolOutput = toolOutput
        self.toolCallId = toolCallId
        self.status = status
        self.todoItems = todoItems
        self.diffContent = diffContent
    }
}

// MARK: - OpenCode Event

struct OpenCodeEvent: Sendable, Identifiable {
    enum Kind: String, Sendable {
        case thought
        case call
        case diff
        case finish
        case error // Explicit error from OpenCode
        case unknown
        case user
        case assistant // text message from AI
        case tool // tool_call / tool_use
        case usage // token usage updates
    }

    let id: UUID
    let kind: Kind
    let rawJson: String
    let text: String
    let toolName: String?
    let toolInput: String?
    let toolInputJSON: String? // Full tool input as JSON string (Sendable-safe)
    let toolOutput: String?
    let toolCallId: String?
    let sessionId: String?
    let model: String?
    let usage: TokenUsage?
    let cost: Double?
    let messageId: String?
    /// Unified diff from OpenCode protocol (`state.metadata.diff`).
    let diff: String?
    /// Whether this is a secondary/redundant finish event (session.idle, process exit)
    let isSecondaryFinish: Bool
    /// Agent name from OpenCode (e.g. "plan", "build"). Extracted from message info.
    let agent: String?

    init(
        id: UUID = UUID(),
        kind: Kind,
        rawJson: String,
        text: String,
        toolName: String? = nil,
        toolInput: String? = nil,
        toolInputJSON: String? = nil,
        toolOutput: String? = nil,
        toolCallId: String? = nil,
        sessionId: String? = nil,
        model: String? = nil,
        usage: TokenUsage? = nil,
        cost: Double? = nil,
        messageId: String? = nil,
        diff: String? = nil,
        isSecondaryFinish: Bool = false,
        agent: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.rawJson = rawJson
        self.text = text
        self.toolName = toolName
        self.toolInput = toolInput
        self.toolInputJSON = toolInputJSON
        self.toolOutput = toolOutput
        self.toolCallId = toolCallId
        self.sessionId = sessionId
        self.model = model
        self.usage = usage
        self.cost = cost
        self.messageId = messageId
        self.diff = diff
        self.isSecondaryFinish = isSecondaryFinish
        self.agent = agent
    }

    /// Parse OpenCode CLI JSON output
    /// Based on: https://github.com/accomplish-ai/openwork/blob/main/packages/shared/src/types/opencode.ts
    init(rawJson: String) {
        let trimmed = rawJson.trimmingCharacters(in: .whitespacesAndNewlines)

        // Skip non-JSON lines (terminal decorations, etc.)
        guard trimmed.hasPrefix("{"),
              let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            self.init(kind: .unknown, rawJson: rawJson, text: trimmed.isEmpty ? "" : trimmed)
            return
        }

        // Get message type
        let messageType = object["type"] as? String ?? ""
        let part = object["part"] as? [String: Any]
        let sessionId = part?["sessionID"] as? String ?? object["sessionID"] as? String

        switch messageType {
        case "text":
            // AI text response: { type: "text", part: { text: "..." } }
            let text = part?["text"] as? String ?? ""
            self.init(kind: .assistant, rawJson: rawJson, text: text, sessionId: sessionId)

        case "tool_call":
            // Tool call: { type: "tool_call", part: { tool: "Read", input: {...} } }
            let toolName = part?["tool"] as? String ?? "Tool"
            let inputDict = OpenCodeEvent.extractToolInputDict(from: part)
            let toolCallId = OpenCodeEvent.extractToolCallId(from: part)
            let inputStr = OpenCodeEvent.extractPrimaryInput(from: inputDict)
            self.init(
                kind: .tool,
                rawJson: rawJson,
                text: inputStr ?? "",
                toolName: toolName,
                toolInput: inputStr,
                toolInputJSON: OpenCodeEvent.serializeJSON(inputDict),
                toolCallId: toolCallId,
                sessionId: sessionId
            )

        case "tool_use":
            // Tool use (combined): { type: "tool_use", part: { tool: "Read", state: { status, input, output } } }
            let toolName = part?["tool"] as? String ?? "Tool"
            let state = part?["state"] as? [String: Any]
            let inputDict = OpenCodeEvent.extractToolInputDict(from: state)
            let outputStr = state?["output"] as? String
            let toolCallId = OpenCodeEvent.extractToolCallId(from: state) ?? OpenCodeEvent.extractToolCallId(from: part)
            let inputStr = OpenCodeEvent.extractPrimaryInput(from: inputDict)
            self.init(
                kind: .tool,
                rawJson: rawJson,
                text: inputStr ?? "",
                toolName: toolName,
                toolInput: inputStr,
                toolInputJSON: OpenCodeEvent.serializeJSON(inputDict),
                toolOutput: outputStr,
                toolCallId: toolCallId,
                sessionId: sessionId
            )

        case "tool_result":
            // Tool result: { type: "tool_result", part: { output: "..." } }
            let output = part?["output"] as? String ?? ""
            let toolCallId = OpenCodeEvent.extractToolCallId(from: part)
            // text is empty — output is accessed via toolOutputSummary + expand
            self.init(kind: .tool, rawJson: rawJson, text: "", toolName: "Result", toolOutput: output, toolCallId: toolCallId, sessionId: sessionId)

        case "step_start":
            self.init(kind: .thought, rawJson: rawJson, text: "Processing...", sessionId: sessionId)

        case "error":
            // Error message — surface to user, not silently drop
            let errorText = object["error"] as? String
                ?? part?["message"] as? String
                ?? part?["text"] as? String
                ?? "Unknown error"
            Log.bridge("⚠️ OpenCode error event: \(errorText)")
            self.init(kind: .error, rawJson: rawJson, text: errorText, sessionId: sessionId)

        case "user":
            // User message (logged by Motive in submitIntent/resumeSession)
            let userText = part?["text"] as? String ?? object["text"] as? String ?? ""
            self.init(kind: .user, rawJson: rawJson, text: userText, sessionId: sessionId)

        case "question.asked":
            self = Self.parseQuestionAsked(from: object, rawJson: rawJson, sessionId: sessionId)

        case "permission.asked":
            self = Self.parsePermissionAsked(from: object, rawJson: rawJson, sessionId: sessionId)

        case "step_finish":
            self = Self.parseStepFinish(from: part, rawJson: rawJson, sessionId: sessionId)

        default:
            // Unknown message type — log it for debugging instead of silently dropping
            let message = OpenCodeEvent.extractString(from: object, keys: ["message", "text", "content", "summary", "detail"])
            Log.bridge("⚠️ Unrecognized event type: '\(messageType)' — raw: \(rawJson.prefix(500))")
            self.init(kind: .unknown, rawJson: rawJson, text: message ?? "Unrecognized event: \(messageType)", sessionId: sessionId)
        }
    }

    // MARK: - Extracted Parsers

    private static func parseQuestionAsked(from object: [String: Any], rawJson: String, sessionId: String?) -> OpenCodeEvent {
        let questions = object["questions"] as? [[String: Any]] ?? []
        let questionText = questions.first?["question"] as? String ?? "Question"
        let questionId = object["id"] as? String
        var inputDict: [String: Any] = ["_isNativeQuestion": true, "question": questionText]
        if let id = questionId { inputDict["_nativeQuestionID"] = id }
        if let q = questions.first {
            inputDict["options"] = q["options"] ?? []
            inputDict["multiple"] = q["multiple"] ?? false
            inputDict["custom"] = q["custom"] ?? true
        }
        return OpenCodeEvent(kind: .tool, rawJson: rawJson, text: questionText, toolName: "Question", toolInput: questionText, toolInputJSON: serializeJSON(inputDict), sessionId: sessionId)
    }

    private static func parsePermissionAsked(from object: [String: Any], rawJson: String, sessionId: String?) -> OpenCodeEvent {
        let permission = object["permission"] as? String ?? "unknown"
        let patterns = object["patterns"] as? [String] ?? []
        let permId = object["id"] as? String
        let metadata = object["metadata"] as? [String: String] ?? [:]
        var inputDict: [String: Any] = [
            "_isNativePermission": true,
            "permission": permission,
            "patterns": patterns,
            "metadata": metadata,
        ]
        if let id = permId { inputDict["_nativePermissionID"] = id }
        let description = "\(permission): \(patterns.joined(separator: ", "))"
        return OpenCodeEvent(
            kind: .tool,
            rawJson: rawJson,
            text: description,
            toolName: "Permission",
            toolInput: patterns.joined(separator: ", "),
            toolInputJSON: serializeJSON(inputDict),
            sessionId: sessionId
        )
    }

    private static func parseStepFinish(from part: [String: Any]?, rawJson: String, sessionId: String?) -> OpenCodeEvent {
        let reason = part?["reason"] as? String ?? "done"
        let isTerminal = (reason == "stop" || reason == "end_turn" || reason == "done")
        if isTerminal {
            return OpenCodeEvent(kind: .finish, rawJson: rawJson, text: "Completed", sessionId: sessionId)
        } else {
            return OpenCodeEvent(kind: .thought, rawJson: rawJson, text: "", sessionId: sessionId)
        }
    }

    // MARK: - Replay Serialization

    /// Serialize this event into JSON that `OpenCodeEvent(rawJson:)` can parse back.
    /// Used by logEvent to persist bridge-created events (which have empty rawJson).
    func toReplayJSON() -> String {
        // If rawJson is already populated (e.g., question.asked, permission.asked), use it as-is
        if !rawJson.isEmpty { return rawJson }

        var dict: [String: Any] = [:]
        if let sid = sessionId { dict["sessionID"] = sid }

        switch kind {
        case .assistant:
            dict["type"] = "text"
            dict["part"] = ["text": text, "sessionID": sessionId ?? ""]

        case .tool, .call:
            // Reconstruct as tool_use (combined call + result format)
            var state: [String: Any] = ["tool": toolName ?? "Tool"]
            if let inputJSON = toolInputJSON,
               let inputData = inputJSON.data(using: .utf8),
               let input = try? JSONSerialization.jsonObject(with: inputData) as? [String: Any],
               JSONSerialization.isValidJSONObject(input)
            {
                state["input"] = input
            } else if let inputStr = toolInput {
                state["input"] = ["description": inputStr]
            }
            if let output = toolOutput { state["output"] = output }
            if let callId = toolCallId { state["id"] = callId }
            state["status"] = toolOutput != nil ? "completed" : "running"
            dict["type"] = "tool_use"
            dict["part"] = ["tool": toolName ?? "Tool", "state": state, "sessionID": sessionId ?? ""]

        case .thought:
            dict["type"] = "step_start"
            dict["part"] = ["text": text, "sessionID": sessionId ?? ""]

        case .finish:
            dict["type"] = "step_finish"
            dict["part"] = ["reason": isSecondaryFinish ? "idle" : "stop", "sessionID": sessionId ?? ""]

        case .error:
            dict["type"] = "error"
            dict["error"] = text

        case .diff:
            dict["type"] = "tool_use"
            dict["part"] = ["tool": toolName ?? "Edit", "state": ["status": "completed"], "sessionID": sessionId ?? ""]

        case .user:
            dict["type"] = "user"
            dict["part"] = ["text": text]

        case .usage:
            return rawJson

        case .unknown:
            return rawJson // Nothing useful to serialize
        }

        guard JSONSerialization.isValidJSONObject(dict),
              let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8)
        else {
            return rawJson
        }
        return str
    }

    private static func extractString(from object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String, !value.isEmpty {
                return value
            }
            if let value = object[key] as? [String: Any],
               let nested = value["text"] as? String,
               !nested.isEmpty
            {
                return nested
            }
        }
        return nil
    }

    private static func extractToolInputDict(from container: [String: Any]?) -> [String: Any]? {
        guard let container else { return nil }
        let keys = ["input", "arguments", "args"]
        // Try dict value first, then JSON-string value
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

    private static func extractToolCallId(from container: [String: Any]?) -> String? {
        guard let container else { return nil }
        let keys = ["id", "toolCallId", "toolCallID", "callId"]
        return keys.lazy.compactMap { container[$0] as? String }.first { !$0.isEmpty }
    }

    /// Extract the primary display-worthy input value from a tool input dictionary.
    /// Checks `filePath`, `path`, `command`, and `description` in priority order.
    private static func extractPrimaryInput(from dict: [String: Any]?) -> String? {
        guard let dict else { return nil }
        let keys = ["filePath", "path", "command", "description"]
        return keys.lazy.compactMap { dict[$0] as? String }.first
    }

    /// Serialize a dictionary to a JSON string for Sendable-safe storage.
    static func serializeJSON(_ dict: [String: Any]?) -> String? {
        guard let dict, JSONSerialization.isValidJSONObject(dict),
              let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8)
        else { return nil }
        return str
    }

    /// Deserialize toolInputJSON back to a dictionary (for consumers that need dict access).
    var toolInputDict: [String: Any]? {
        guard let toolInputJSON, let data = toolInputJSON.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return dict
    }

    /// Convert to ConversationMessage for UI display
    func toMessage() -> ConversationMessage? {
        // Skip empty messages — but always keep finish, error, and tool-with-name events
        if text.isEmpty, kind != .finish, kind != .error {
            guard kind == .tool, toolName != nil else { return nil }
        }

        let messageType: ConversationMessage.MessageType
        let messageStatus: ConversationMessage.Status

        switch kind {
        case .user:
            messageType = .user
            messageStatus = .completed
        case .assistant:
            messageType = .assistant
            messageStatus = .completed
        case .thought:
            messageType = .reasoning
            messageStatus = .completed
        case .tool, .call:
            // Tool calls without output are still running
            // Tool calls with output (tool_use) are completed
            messageType = .tool
            messageStatus = toolOutput != nil ? .completed : .running
        case .diff:
            messageType = .tool
            messageStatus = .completed
        case .error:
            // Error events are ALWAYS shown to the user
            messageType = .system
            messageStatus = .failed
        case .finish:
            messageType = .system
            messageStatus = .completed
        case .unknown:
            if text.isEmpty { return nil }
            messageType = .system
            messageStatus = .completed
        case .usage:
            return nil
        }

        return ConversationMessage(
            id: id,
            type: messageType,
            content: text,
            toolName: toolName ?? (kind == .call ? "Command" : nil),
            toolInput: toolInput,
            toolOutput: toolOutput,
            toolCallId: toolCallId,
            status: messageStatus,
            diffContent: self.diff
        )
    }
}

extension ConversationMessage {
    // MARK: - Convenience Builders

    /// Return a copy with a different status.
    func withStatus(_ newStatus: Status) -> ConversationMessage {
        ConversationMessage(
            id: id, type: type, content: content, timestamp: timestamp,
            toolName: toolName, toolInput: toolInput,
            toolOutput: toolOutput, toolCallId: toolCallId,
            status: newStatus, todoItems: todoItems, diffContent: diffContent
        )
    }

    /// Return a copy with updated content.
    func withContent(_ newContent: String) -> ConversationMessage {
        ConversationMessage(
            id: id, type: type, content: newContent, timestamp: timestamp,
            toolName: toolName, toolInput: toolInput,
            toolOutput: toolOutput, toolCallId: toolCallId,
            status: status, todoItems: todoItems, diffContent: diffContent
        )
    }

    /// Return a copy with updated todo items and content.
    func withTodos(_ items: [TodoItem], summary: String) -> ConversationMessage {
        ConversationMessage(
            id: id, type: type, content: summary, timestamp: timestamp,
            toolName: toolName, toolInput: toolInput,
            toolOutput: toolOutput, toolCallId: toolCallId,
            status: status, todoItems: items, diffContent: diffContent
        )
    }

    /// Merge tool data from an incoming message into this (existing) message.
    /// Keeps the existing value for each field when the incoming value is nil/empty.
    func mergingToolData(from incoming: ConversationMessage) -> ConversationMessage {
        ConversationMessage(
            id: id,
            type: type,
            content: content.isEmpty ? incoming.content : content,
            timestamp: timestamp,
            toolName: toolName ?? incoming.toolName,
            toolInput: toolInput ?? incoming.toolInput,
            toolOutput: toolOutput ?? incoming.toolOutput,
            toolCallId: toolCallId ?? incoming.toolCallId,
            status: incoming.toolOutput != nil ? .completed : status,
            todoItems: todoItems,
            diffContent: diffContent ?? incoming.diffContent
        )
    }

    /// Uniform output summary — always "Output · N lines", never raw content.
    /// Clicking "Show" in the UI reveals the actual output.
    var toolOutputSummary: String? {
        guard let toolOutput, !toolOutput.isEmpty else { return nil }
        let trimmed = toolOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }

        // Prefer explicit line-count marker from OpenCode (e.g., Read tool)
        if let range = trimmed.range(of: "End of file - total ") {
            let suffix = trimmed[range.upperBound...]
            let countStr = suffix.prefix { $0.isNumber }
            if let count = Int(countStr) {
                return "Output · \(count) lines"
            }
        }

        // Count actual lines — always show as "N lines"
        let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
        let lineCount = max(lines.count, 1)
        return "Output · \(lineCount) \(lineCount == 1 ? "line" : "lines")"
    }

    // MARK: - Snapshot Serialization (Codable)

    /// Serialize a messages array to Data for persistence using Codable.
    static func serializeMessages(_ messages: [ConversationMessage]) -> Data? {
        do {
            return try JSONEncoder().encode(messages)
        } catch {
            Log.error("Failed to serialize \(messages.count) messages: \(error)")
            return nil
        }
    }

    /// Deserialize a messages array from persisted Data.
    /// Tries Codable first, then falls back to legacy JSONSerialization format for migration.
    static func deserializeMessages(_ data: Data) -> [ConversationMessage]? {
        // Try Codable (new format)
        if let messages = try? JSONDecoder().decode([ConversationMessage].self, from: data),
           !messages.isEmpty
        {
            return messages
        }

        // Fallback: legacy manual JSONSerialization format (migration path)
        return deserializeMessagesLegacy(data)
    }

    /// Legacy deserialization for data saved before Codable migration.
    private static func deserializeMessagesLegacy(_ data: Data) -> [ConversationMessage]? {
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            Log.error("Failed to deserialize messages: data is not a valid JSON array")
            return nil
        }
        var droppedCount = 0
        let results: [ConversationMessage] = array.compactMap { dict in
            guard let idStr = dict["id"] as? String, let id = UUID(uuidString: idStr),
                  let typeStr = dict["type"] as? String, let type = MessageType(rawValue: typeStr),
                  let content = dict["content"] as? String,
                  let statusStr = dict["status"] as? String, let status = Status(rawValue: statusStr)
            else {
                droppedCount += 1
                Log.error("Dropped message during legacy deserialization: missing required field(s) in \(dict.keys)")
                return nil
            }

            let ts = dict["timestamp"] as? TimeInterval ?? Date().timeIntervalSince1970

            var todoItems: [TodoItem]?
            if let todoDicts = dict["todoItems"] as? [[String: String]] {
                todoItems = todoDicts.compactMap { td in
                    guard let id = td["id"], let content = td["content"],
                          let statusStr = td["status"], let status = TodoItem.Status(rawValue: statusStr)
                    else { return nil }
                    return TodoItem(id: id, content: content, status: status)
                }
            }

            return ConversationMessage(
                id: id,
                type: type,
                content: content,
                timestamp: Date(timeIntervalSince1970: ts),
                toolName: dict["toolName"] as? String,
                toolInput: dict["toolInput"] as? String,
                toolOutput: dict["toolOutput"] as? String,
                toolCallId: dict["toolCallId"] as? String,
                status: status,
                todoItems: todoItems,
                diffContent: dict["diffContent"] as? String
            )
        }
        if droppedCount > 0 {
            Log.error("Legacy deserialization: dropped \(droppedCount) of \(array.count) messages")
        }
        return results.isEmpty ? nil : results
    }
}
