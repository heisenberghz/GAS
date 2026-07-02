//
//  SSEEventTypes.swift
//  Motive
//
//  SSE event type definitions and associated info structs.
//  Extracted from SSEClient.swift for separation of concerns.
//

import Foundation

// MARK: - Event Types

extension SSEClient {

    /// Structured events parsed from OpenCode's SSE stream.
    enum SSEEvent: Sendable {
        // Text streaming
        case textDelta(TextDeltaInfo)
        case textComplete(TextCompleteInfo)

        /// Reasoning streaming
        case reasoningDelta(ReasoningDeltaInfo)

        /// Token usage
        case usageUpdated(UsageInfo)

        // Tool lifecycle
        case toolRunning(ToolInfo)
        case toolCompleted(ToolCompletedInfo)
        case toolError(ToolErrorInfo)

        // Session lifecycle
        case sessionIdle(sessionID: String)
        case sessionStatus(SessionStatusInfo)
        case sessionError(SessionErrorInfo)

        // Native question/permission
        case questionAsked(QuestionRequest)
        case permissionAsked(NativePermissionRequest)

        /// Agent mode
        case agentChanged(AgentChangeInfo)

        // Connection
        case connected
        case heartbeat
    }
}

// MARK: - Info Types

extension SSEClient {

    struct TextDeltaInfo: Sendable {
        let sessionID: String
        let messageID: String
        let delta: String
    }

    struct TextCompleteInfo: Sendable {
        let sessionID: String
        let messageID: String
        let text: String
    }

    struct ReasoningDeltaInfo: Sendable {
        let sessionID: String
        let delta: String
    }

    struct UsageInfo: Sendable {
        let sessionID: String
        let messageID: String?
        let model: String?
        let usage: TokenUsage
        let cost: Double?
    }

    struct ToolInfo: Sendable {
        let sessionID: String
        let toolName: String
        let toolCallID: String?
        let inputSummary: String?
        /// Serialized JSON of the full tool input dict (Sendable workaround for [String: Any]).
        let inputJSON: String?

        init(sessionID: String, toolName: String, toolCallID: String?, input: [String: Any]?, inputSummary: String?) {
            self.sessionID = sessionID
            self.toolName = toolName
            self.toolCallID = toolCallID
            self.inputSummary = inputSummary
            if let input {
                let isValid = JSONSerialization.isValidJSONObject(input)
                if isValid, let data = try? JSONSerialization.data(withJSONObject: input) {
                    self.inputJSON = String(data: data, encoding: .utf8)
                } else {
                    Log.bridge("⚠️ ToolInfo inputJSON serialization failed: tool=\(toolName) keys=\(input.keys.sorted()) isValid=\(isValid)")
                    self.inputJSON = nil
                }
            } else {
                self.inputJSON = nil
            }
        }
    }

    struct ToolCompletedInfo: Sendable {
        let sessionID: String
        let toolName: String
        let toolCallID: String?
        let output: String?
        let inputSummary: String?
        /// Unified diff from OpenCode protocol (`state.metadata.diff`).
        let diff: String?
        /// Serialized JSON of the full tool input dict (Sendable workaround for [String: Any]).
        let inputJSON: String?

        init(sessionID: String, toolName: String, toolCallID: String?, output: String?, input: [String: Any]?, inputSummary: String?, diff: String?) {
            self.sessionID = sessionID
            self.toolName = toolName
            self.toolCallID = toolCallID
            self.output = output
            self.inputSummary = inputSummary
            self.diff = diff
            if let input, let data = try? JSONSerialization.data(withJSONObject: input) {
                self.inputJSON = String(data: data, encoding: .utf8)
            } else {
                self.inputJSON = nil
            }
        }
    }

    struct ToolErrorInfo: Sendable {
        let sessionID: String
        let toolName: String
        let toolCallID: String?
        let error: String
    }

    struct SessionStatusInfo: Sendable {
        let sessionID: String
        let status: String // "idle", "busy", "retry"
        let attempt: Int?
        let message: String?
        let nextRetryUnixMS: Int64?
    }

    struct SessionErrorInfo: Sendable {
        let sessionID: String
        let error: String
    }

    /// A question asked by OpenCode's native question tool.
    struct QuestionRequest: Sendable {
        let id: String
        let sessionID: String
        let questions: [QuestionItem]
        /// Tool context from the question event (e.g. tool name that triggered it).
        /// Used to detect plan_exit questions.
        let toolContext: String?
        /// Plan file path parsed from plan_enter / plan_exit question text.
        let planFilePath: String?

        struct QuestionItem: Sendable {
            let question: String
            let options: [QuestionOption]
            let multiple: Bool
            let custom: Bool
        }

        struct QuestionOption: Sendable {
            let label: String
            let description: String?
        }
    }

    /// A permission request from OpenCode's native permission system.
    struct NativePermissionRequest: Sendable {
        let id: String
        let sessionID: String
        let permission: String // "edit", "bash", "read", etc.
        let patterns: [String] // File paths or command patterns
        let metadata: [String: String] // "filepath", "diff", etc.
        let always: [String] // Patterns to remember if "always" is chosen
    }

    /// Agent mode change detected from SSE events (e.g. plan → build).
    struct AgentChangeInfo: Sendable {
        let sessionID: String
        let agent: String // "plan", "build", etc.
    }
}
