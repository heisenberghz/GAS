//
//  BridgeProtocols.swift
//  Motive
//
//  Protocol abstractions for bridge components to enable testing.
//  Each protocol captures the public interface used by OpenCodeBridge.
//

import Foundation

// MARK: - API Client Protocol

/// Abstracts the REST API surface used by OpenCodeBridge.
///
/// The concrete implementation is `OpenCodeAPIClient` (an actor).
/// All methods are implicitly `async` when called cross-actor; the protocol
/// mirrors that by marking every requirement `async`.
nonisolated protocol OpenCodeAPIClientProtocol: Sendable {
    func updateBaseURL(_ url: URL) async
    func updateDirectory(_ path: String) async
    func createSession(title: String?) async throws -> OpenCodeAPIClient.SessionInfo
    func abortSession(id: String) async throws
    func sendPromptAsync(sessionID: String, text: String, model: String?, modelProviderID: String?, agent: String?) async throws
    func replyToQuestion(requestID: String, answers: [[String]]) async throws
    func rejectQuestion(requestID: String) async throws
    func replyToPermission(requestID: String, reply: OpenCodeAPIClient.PermissionReply) async throws
}

extension OpenCodeAPIClientProtocol {
    func createSession() async throws -> OpenCodeAPIClient.SessionInfo {
        try await createSession(title: nil)
    }
}

// MARK: - SSE Client Protocol

/// Abstracts the SSE streaming surface used by OpenCodeBridge.
///
/// The concrete implementation is `SSEClient` (an actor).
nonisolated protocol SSEClientProtocol: Sendable {
    var connected: Bool { get async }
    var hasActiveStream: Bool { get async }
    func connect(to baseURL: URL, directory: String?) async -> AsyncStream<SSEClient.SSEEvent>
    func disconnect() async
}

extension SSEClientProtocol {
    func connect(to baseURL: URL) async -> AsyncStream<SSEClient.SSEEvent> {
        await connect(to: baseURL, directory: nil)
    }
}

// MARK: - Server Protocol

/// Abstracts the server lifecycle surface used by OpenCodeBridge.
///
/// The concrete implementation is `OpenCodeServer` (an actor).
nonisolated protocol OpenCodeServerProtocol: Sendable {
    var serverURL: URL? { get async }
    var isRunning: Bool { get async }
    func start(configuration: OpenCodeServer.Configuration) async throws -> URL
    func stop() async
    func setRestartHandler(_ handler: @escaping @Sendable (URL) async -> Void) async
}
