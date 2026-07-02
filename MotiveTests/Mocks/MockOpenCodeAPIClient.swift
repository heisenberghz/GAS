//
//  MockOpenCodeAPIClient.swift
//  MotiveTests
//
//  Mock implementation of OpenCodeAPIClientProtocol for unit testing.
//  Tracks method calls and allows configuring return values and errors.
//

import Foundation
@testable import Motive

actor MockOpenCodeAPIClient: OpenCodeAPIClientProtocol {

    // MARK: - Call Tracking

    var updateBaseURLCalled = false
    var updateBaseURLLastURL: URL?

    var updateDirectoryCalled = false
    var updateDirectoryLastPath: String?

    var createSessionCalled = false
    var createSessionCallCount = 0
    var createSessionLastTitle: String?

    var abortSessionCalled = false
    var abortSessionLastID: String?

    var sendPromptAsyncCalled = false
    var sendPromptAsyncCallCount = 0
    var sendPromptAsyncLastSessionID: String?
    var sendPromptAsyncLastText: String?
    var sendPromptAsyncLastModel: String?
    var sendPromptAsyncLastModelProviderID: String?

    var replyToQuestionCalled = false
    var replyToQuestionLastRequestID: String?
    var replyToQuestionLastAnswers: [[String]]?

    var rejectQuestionCalled = false
    var rejectQuestionLastRequestID: String?

    var replyToPermissionCalled = false
    var replyToPermissionLastRequestID: String?
    var replyToPermissionLastReply: OpenCodeAPIClient.PermissionReply?

    // MARK: - Configurable Results

    var createSessionResult: OpenCodeAPIClient.SessionInfo?
    var createSessionError: Error?

    var abortSessionError: Error?

    var sendPromptAsyncError: Error?

    var replyToQuestionError: Error?

    var rejectQuestionError: Error?

    var replyToPermissionError: Error?

    // MARK: - Protocol Conformance

    nonisolated func updateBaseURL(_ url: URL) async {
        await _recordUpdateBaseURL(url)
    }

    private func _recordUpdateBaseURL(_ url: URL) {
        updateBaseURLCalled = true
        updateBaseURLLastURL = url
    }

    nonisolated func updateDirectory(_ path: String) async {
        await _recordUpdateDirectory(path)
    }

    private func _recordUpdateDirectory(_ path: String) {
        updateDirectoryCalled = true
        updateDirectoryLastPath = path
    }

    nonisolated func createSession(title: String?) async throws -> OpenCodeAPIClient.SessionInfo {
        try await _performCreateSession(title: title)
    }

    private func _performCreateSession(title: String?) throws -> OpenCodeAPIClient.SessionInfo {
        createSessionCalled = true
        createSessionCallCount += 1
        createSessionLastTitle = title

        if let error = createSessionError {
            throw error
        }

        return createSessionResult ?? OpenCodeAPIClient.SessionInfo(
            id: "mock-session-\(createSessionCallCount)",
            title: title
        )
    }

    nonisolated func abortSession(id: String) async throws {
        try await _performAbortSession(id: id)
    }

    private func _performAbortSession(id: String) throws {
        abortSessionCalled = true
        abortSessionLastID = id

        if let error = abortSessionError {
            throw error
        }
    }

    nonisolated func sendPromptAsync(
        sessionID: String,
        text: String,
        model: String?,
        modelProviderID: String?,
        agent: String?
    ) async throws {
        try await _performSendPromptAsync(
            sessionID: sessionID,
            text: text,
            model: model,
            modelProviderID: modelProviderID
        )
    }

    private func _performSendPromptAsync(
        sessionID: String,
        text: String,
        model: String?,
        modelProviderID: String?
    ) throws {
        sendPromptAsyncCalled = true
        sendPromptAsyncCallCount += 1
        sendPromptAsyncLastSessionID = sessionID
        sendPromptAsyncLastText = text
        sendPromptAsyncLastModel = model
        sendPromptAsyncLastModelProviderID = modelProviderID

        if let error = sendPromptAsyncError {
            throw error
        }
    }

    nonisolated func replyToQuestion(requestID: String, answers: [[String]]) async throws {
        try await _performReplyToQuestion(requestID: requestID, answers: answers)
    }

    private func _performReplyToQuestion(requestID: String, answers: [[String]]) throws {
        replyToQuestionCalled = true
        replyToQuestionLastRequestID = requestID
        replyToQuestionLastAnswers = answers

        if let error = replyToQuestionError {
            throw error
        }
    }

    nonisolated func rejectQuestion(requestID: String) async throws {
        try await _performRejectQuestion(requestID: requestID)
    }

    private func _performRejectQuestion(requestID: String) throws {
        rejectQuestionCalled = true
        rejectQuestionLastRequestID = requestID

        if let error = rejectQuestionError {
            throw error
        }
    }

    nonisolated func replyToPermission(requestID: String, reply: OpenCodeAPIClient.PermissionReply) async throws {
        try await _performReplyToPermission(requestID: requestID, reply: reply)
    }

    private func _performReplyToPermission(requestID: String, reply: OpenCodeAPIClient.PermissionReply) throws {
        replyToPermissionCalled = true
        replyToPermissionLastRequestID = requestID
        replyToPermissionLastReply = reply

        if let error = replyToPermissionError {
            throw error
        }
    }

    // MARK: - Reset

    /// Reset all tracking state for reuse between tests.
    func reset() {
        updateBaseURLCalled = false
        updateBaseURLLastURL = nil
        updateDirectoryCalled = false
        updateDirectoryLastPath = nil
        createSessionCalled = false
        createSessionCallCount = 0
        createSessionLastTitle = nil
        abortSessionCalled = false
        abortSessionLastID = nil
        sendPromptAsyncCalled = false
        sendPromptAsyncCallCount = 0
        sendPromptAsyncLastSessionID = nil
        sendPromptAsyncLastText = nil
        sendPromptAsyncLastModel = nil
        sendPromptAsyncLastModelProviderID = nil
        replyToQuestionCalled = false
        replyToQuestionLastRequestID = nil
        replyToQuestionLastAnswers = nil
        rejectQuestionCalled = false
        rejectQuestionLastRequestID = nil
        replyToPermissionCalled = false
        replyToPermissionLastRequestID = nil
        replyToPermissionLastReply = nil

        createSessionResult = nil
        createSessionError = nil
        abortSessionError = nil
        sendPromptAsyncError = nil
        replyToQuestionError = nil
        rejectQuestionError = nil
        replyToPermissionError = nil
    }
}
