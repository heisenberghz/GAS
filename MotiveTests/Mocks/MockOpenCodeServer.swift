//
//  MockOpenCodeServer.swift
//  MotiveTests
//
//  Mock implementation of OpenCodeServerProtocol for unit testing.
//  Tracks method calls and allows configuring return values, errors, and behavior.
//

import Foundation
@testable import Motive

actor MockOpenCodeServer: OpenCodeServerProtocol {

    // MARK: - State

    private var _serverURL: URL?
    private var _isRunning = false
    private var restartHandler: (@Sendable (URL) async -> Void)?

    // MARK: - Call Tracking

    var startCalled = false
    var startCallCount = 0
    var startLastConfiguration: OpenCodeServer.Configuration?

    var stopCalled = false
    var stopCallCount = 0

    var setRestartHandlerCalled = false

    // MARK: - Configurable Results

    /// The URL to return from `start(configuration:)`.
    /// Defaults to `http://127.0.0.1:4096` if nil.
    var startResult: URL?

    /// If set, `start(configuration:)` will throw this error.
    var startError: Error?

    // MARK: - Protocol Conformance

    nonisolated var serverURL: URL? {
        get async { await _serverURL }
    }

    nonisolated var isRunning: Bool {
        get async { await _isRunning }
    }

    nonisolated func start(configuration: OpenCodeServer.Configuration) async throws -> URL {
        try await _performStart(configuration: configuration)
    }

    private func _performStart(configuration: OpenCodeServer.Configuration) throws -> URL {
        startCalled = true
        startCallCount += 1
        startLastConfiguration = configuration

        if let error = startError {
            throw error
        }

        let url = startResult ?? URL(string: "http://127.0.0.1:4096")!
        _serverURL = url
        _isRunning = true
        return url
    }

    nonisolated func stop() async {
        await _performStop()
    }

    private func _performStop() {
        stopCalled = true
        stopCallCount += 1
        _serverURL = nil
        _isRunning = false
    }

    nonisolated func setRestartHandler(_ handler: @escaping @Sendable (URL) async -> Void) async {
        await _performSetRestartHandler(handler)
    }

    private func _performSetRestartHandler(_ handler: @escaping @Sendable (URL) async -> Void) {
        setRestartHandlerCalled = true
        restartHandler = handler
    }

    // MARK: - Test Helpers

    /// Simulate a server restart by invoking the restart handler with a new URL.
    /// Returns false if no restart handler has been set.
    @discardableResult
    func simulateRestart(newURL: URL? = nil) async -> Bool {
        guard let handler = restartHandler else { return false }

        let url = newURL ?? URL(string: "http://127.0.0.1:4097")!
        _serverURL = url
        _isRunning = true
        await handler(url)
        return true
    }

    /// Simulate a server crash by marking it as not running.
    func simulateCrash() {
        _serverURL = nil
        _isRunning = false
    }

    // MARK: - Reset

    /// Reset all tracking state for reuse between tests.
    func reset() {
        _serverURL = nil
        _isRunning = false
        restartHandler = nil
        startCalled = false
        startCallCount = 0
        startLastConfiguration = nil
        stopCalled = false
        stopCallCount = 0
        setRestartHandlerCalled = false
        startResult = nil
        startError = nil
    }
}
