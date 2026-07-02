//
//  Errors.swift
//  Motive
//
//  Domain-specific error types for the application.
//  Each error carries enough context for debugging and user-facing messages.
//

import Foundation

// MARK: - Bridge Errors

/// Errors that can occur during OpenCode bridge operations
enum BridgeError: Error, LocalizedError, Sendable {
    case notConfigured
    case processSpawnFailed(underlying: Error)
    case sessionNotFound(id: String)
    case invalidResponse(message: String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "OpenCode bridge is not configured"
        case let .processSpawnFailed(underlying):
            "Failed to spawn OpenCode process: \(underlying.localizedDescription)"
        case let .sessionNotFound(id):
            "Session not found: \(id)"
        case let .invalidResponse(message):
            "Invalid response from OpenCode: \(message)"
        case .timeout:
            "OpenCode operation timed out"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .notConfigured:
            "Please configure the OpenCode binary in Settings."
        case .processSpawnFailed:
            "Check that the OpenCode binary is installed and accessible."
        case .sessionNotFound:
            "The session may have been deleted. Try starting a new session."
        case .invalidResponse:
            "Try restarting the agent."
        case .timeout:
            "The operation took too long. Try again or check your network connection."
        }
    }
}

// MARK: - Session Errors

/// Errors that can occur during session management
enum SessionError: Error, LocalizedError, Sendable {
    case invalidIntent
    case notFound(id: UUID)
    case saveFailed(underlying: Error)
    case loadFailed(underlying: Error)
    case contextNotAttached

    var errorDescription: String? {
        switch self {
        case .invalidIntent:
            "Invalid session intent"
        case let .notFound(id):
            "Session not found: \(id)"
        case let .saveFailed(underlying):
            "Failed to save session: \(underlying.localizedDescription)"
        case let .loadFailed(underlying):
            "Failed to load session: \(underlying.localizedDescription)"
        case .contextNotAttached:
            "Model context is not attached"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .invalidIntent:
            "Please enter a valid command or question."
        case .notFound:
            "The session may have been deleted."
        case .saveFailed, .loadFailed:
            "Try restarting the application."
        case .contextNotAttached:
            "The application is not fully initialized."
        }
    }
}

// MARK: - Skill Errors

/// Errors that can occur during skill operations
enum SkillError: Error, LocalizedError, Sendable {
    case notFound(name: String)
    case invalidFormat(reason: String)
    case installFailed(name: String, reason: String)
    case loadFailed(path: String, reason: String)

    var errorDescription: String? {
        switch self {
        case let .notFound(name):
            "Skill not found: \(name)"
        case let .invalidFormat(reason):
            "Invalid skill format: \(reason)"
        case let .installFailed(name, reason):
            "Failed to install skill '\(name)': \(reason)"
        case let .loadFailed(path, reason):
            "Failed to load skill from \(path): \(reason)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .notFound:
            "Check the skill name and try again."
        case .invalidFormat:
            "Ensure the skill follows the correct SKILL.md format."
        case .installFailed:
            "Check your internet connection and try again."
        case .loadFailed:
            "Verify the skill file exists and is readable."
        }
    }
}

// MARK: - Workspace Errors

/// Errors that can occur during workspace operations
enum WorkspaceError: Error, LocalizedError, Sendable {
    case directoryCreationFailed(path: String, reason: String)
    case fileNotFound(path: String)
    case readFailed(path: String, reason: String)
    case writeFailed(path: String, reason: String)
    case migrationFailed(reason: String)

    var errorDescription: String? {
        switch self {
        case let .directoryCreationFailed(path, reason):
            "Failed to create directory at \(path): \(reason)"
        case let .fileNotFound(path):
            "File not found: \(path)"
        case let .readFailed(path, reason):
            "Failed to read \(path): \(reason)"
        case let .writeFailed(path, reason):
            "Failed to write \(path): \(reason)"
        case let .migrationFailed(reason):
            "Workspace migration failed: \(reason)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .directoryCreationFailed:
            "Check that you have write permissions to the directory."
        case .fileNotFound:
            "The file may have been moved or deleted."
        case .readFailed, .writeFailed:
            "Check file permissions and available disk space."
        case .migrationFailed:
            "Try manually moving your files to ~/.motive/"
        }
    }
}

// MARK: - Permission Errors

/// Errors that can occur during permission operations
enum PermissionError: Error, LocalizedError, Sendable {
    case denied(operation: String, path: String)
    case timeout(operation: String)
    case serverError(message: String)

    var errorDescription: String? {
        switch self {
        case let .denied(operation, path):
            "Permission denied for \(operation) on \(path)"
        case let .timeout(operation):
            "Permission request timed out for \(operation)"
        case let .serverError(message):
            "Permission server error: \(message)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .denied:
            "Grant the permission in the dialog or update your permission policy."
        case .timeout:
            "Try the operation again."
        case .serverError:
            "Restart the application and try again."
        }
    }
}
