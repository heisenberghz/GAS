import Combine
import Foundation

// MARK: - Permission Request Types

/// Permission request type (native system: question and permission only)
enum PermissionRequestType: String, Codable, Sendable {
    case question // Native question from OpenCode
    case permission // Native permission from OpenCode
}

/// Permission request model for the QuickConfirm UI.
///
/// In the native system, questions and permissions both come through SSE events
/// and are displayed via the QuickConfirm window. No HTTP servers needed.
struct PermissionRequest: Identifiable, @unchecked Sendable {
    let id: String
    let taskId: String
    let type: PermissionRequestType

    // Question fields
    var question: String?
    var header: String?
    var options: [QuestionOption]?
    var multiSelect: Bool?

    // Permission fields (native)
    var permissionType: String? // "edit", "bash", etc.
    var patterns: [String]? // File paths or command patterns
    var diff: String? // Diff preview for edit permissions

    /// Session intent for parallel prompts: "From: [intent]" so user knows which task is asking
    var sessionIntent: String?

    /// Whether this question is a plan_exit confirmation ("Execute Plan?").
    /// When true, QuickConfirm shows plan-specific styling and language.
    var isPlanExitConfirmation: Bool = false

    struct QuestionOption: Sendable {
        let label: String
        var value: String?
        var description: String?

        /// Returns value if available, otherwise label
        var effectiveValue: String {
            value ?? label
        }
    }

    init(
        id: String,
        taskId: String,
        type: PermissionRequestType,
        question: String? = nil,
        header: String? = nil,
        options: [QuestionOption]? = nil,
        multiSelect: Bool? = nil,
        permissionType: String? = nil,
        patterns: [String]? = nil,
        diff: String? = nil,
        sessionIntent: String? = nil
    ) {
        self.id = id
        self.taskId = taskId
        self.type = type
        self.question = question
        self.header = header
        self.options = options
        self.multiSelect = multiSelect
        self.permissionType = permissionType
        self.patterns = patterns
        self.diff = diff
        self.sessionIntent = sessionIntent
    }
}

/// Permission response
struct PermissionResponse: Sendable {
    let requestId: String
    let taskId: String
    let decision: Decision
    var selectedOptions: [String]?
    var customText: String?
    var message: String?

    enum Decision: String, Sendable {
        case allow
        case deny
    }
}

// MARK: - Permission Manager

/// Manages permission request UI state for the QuickConfirm window.
///
/// In the new architecture, questions and permissions arrive via SSE events
/// through OpenCodeBridge. This manager only handles UI state coordination
/// for the QuickConfirm popup — no HTTP servers, no MCP sidecar.
@MainActor
class PermissionManager: ObservableObject {
    static let shared = PermissionManager()

    @Published var currentRequest: PermissionRequest?
    @Published var isShowingRequest = false

    private init() {}

    /// Show a permission/question request in the UI
    func showRequest(_ request: PermissionRequest) {
        currentRequest = request
        isShowingRequest = true
    }

    /// Handle user response
    func respond(with response: PermissionResponse) {
        Log.permission("respond() called with requestId: \(response.requestId), decision: \(response.decision)")

        // Clear current request
        currentRequest = nil
        isShowingRequest = false
    }

    /// Cancel current request
    func cancelRequest() {
        if let request = currentRequest {
            respond(with: PermissionResponse(
                requestId: request.id,
                taskId: request.taskId,
                decision: .deny
            ))
        }
    }
}
