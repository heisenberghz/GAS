//
//  ToolInputTypes.swift
//  Motive
//

import Foundation

// MARK: - Native Question Input

struct NativeQuestionInput: Codable, Sendable {
    let isNativeQuestion: Bool
    let questionID: String?
    let question: String?
    let options: [QuestionOption]?
    let isCustom: Bool?
    let isMultiple: Bool?

    struct QuestionOption: Codable, Sendable {
        let label: String
        let description: String?
    }

    enum CodingKeys: String, CodingKey {
        case isNativeQuestion = "_isNativeQuestion"
        case questionID = "_nativeQuestionID"
        case question
        case options
        case isCustom = "custom"
        case isMultiple = "multiple"
    }
}

// MARK: - Native Permission Input

struct NativePermissionInput: Codable, Sendable {
    let isNativePermission: Bool
    let permissionID: String?
    let permission: String?
    let patterns: [String]?
    let metadata: [String: String]?

    enum CodingKeys: String, CodingKey {
        case isNativePermission = "_isNativePermission"
        case permissionID = "_nativePermissionID"
        case permission
        case patterns
        case metadata
    }
}

// MARK: - TodoWrite Input

struct TodoWriteInput: Codable, Sendable {
    let todos: [TodoEntry]?
    let merge: Bool?

    struct TodoEntry: Codable, Sendable {
        let id: String?
        let content: String?
        let status: String?
    }
}

// MARK: - Type-Safe Tool Input Accessors

extension OpenCodeEvent {
    /// Decode tool input as a native question request
    var nativeQuestionInput: NativeQuestionInput? {
        guard let json = toolInputJSON, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(NativeQuestionInput.self, from: data)
    }

    /// Decode tool input as a native permission request
    var nativePermissionInput: NativePermissionInput? {
        guard let json = toolInputJSON, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(NativePermissionInput.self, from: data)
    }

    /// Decode tool input as a TodoWrite request
    var todoWriteInput: TodoWriteInput? {
        guard let json = toolInputJSON, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(TodoWriteInput.self, from: data)
    }
}
