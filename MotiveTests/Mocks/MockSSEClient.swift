//
//  MockSSEClient.swift
//  MotiveTests
//
//  Mock implementation of SSEClientProtocol for unit testing.
//  Tracks method calls and allows injecting a custom AsyncStream of events.
//

import Foundation
@testable import Motive

actor MockSSEClient: SSEClientProtocol {

    // MARK: - State

    private var _connected = false
    private var _hasActiveStream = false

    // MARK: - Call Tracking

    var connectCalled = false
    var connectCallCount = 0
    var connectLastBaseURL: URL?
    var connectLastDirectory: String?

    var disconnectCalled = false
    var disconnectCallCount = 0

    // MARK: - Configurable Behavior

    /// The stream to return from `connect(to:directory:)`.
    /// If nil, a default empty stream is returned.
    var connectStream: AsyncStream<SSEClient.SSEEvent>?

    /// A continuation that tests can use to yield events after connect is called.
    /// Set this via `makeControllableStream()` before the code under test calls connect.
    var streamContinuation: AsyncStream<SSEClient.SSEEvent>.Continuation?

    // MARK: - Protocol Conformance

    nonisolated var connected: Bool {
        get async { await _connected }
    }

    nonisolated var hasActiveStream: Bool {
        get async { await _hasActiveStream }
    }

    nonisolated func connect(to baseURL: URL, directory: String?) async -> AsyncStream<SSEClient.SSEEvent> {
        await _performConnect(to: baseURL, directory: directory)
    }

    private func _performConnect(to baseURL: URL, directory: String?) -> AsyncStream<SSEClient.SSEEvent> {
        connectCalled = true
        connectCallCount += 1
        connectLastBaseURL = baseURL
        connectLastDirectory = directory
        _connected = true
        _hasActiveStream = true

        if let stream = connectStream {
            return stream
        }

        // Return an empty stream by default
        return AsyncStream { continuation in
            continuation.finish()
        }
    }

    nonisolated func disconnect() async {
        await _performDisconnect()
    }

    private func _performDisconnect() {
        disconnectCalled = true
        disconnectCallCount += 1
        _connected = false
        _hasActiveStream = false
        streamContinuation?.finish()
        streamContinuation = nil
    }

    // MARK: - Test Helpers

    /// Create a controllable stream that tests can push events into.
    /// Call this before the code under test invokes `connect`.
    /// Returns the continuation for yielding events.
    @discardableResult
    func makeControllableStream() -> AsyncStream<SSEClient.SSEEvent>.Continuation {
        let (stream, continuation) = AsyncStream.makeStream(of: SSEClient.SSEEvent.self)
        self.connectStream = stream
        self.streamContinuation = continuation
        return continuation
    }

    /// Create a stream that emits the given events and then finishes.
    func setEvents(_ events: [SSEClient.SSEEvent]) {
        connectStream = AsyncStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }

    /// Yield a single event into the controllable stream.
    /// Only works if `makeControllableStream()` was called first.
    func yield(_ event: SSEClient.SSEEvent) {
        streamContinuation?.yield(event)
    }

    /// Finish the controllable stream.
    /// Only works if `makeControllableStream()` was called first.
    func finishStream() {
        streamContinuation?.finish()
        streamContinuation = nil
        _hasActiveStream = false
    }

    // MARK: - Reset

    /// Reset all tracking state for reuse between tests.
    func reset() {
        _connected = false
        _hasActiveStream = false
        connectCalled = false
        connectCallCount = 0
        connectLastBaseURL = nil
        connectLastDirectory = nil
        disconnectCalled = false
        disconnectCallCount = 0
        connectStream = nil
        streamContinuation?.finish()
        streamContinuation = nil
    }
}
