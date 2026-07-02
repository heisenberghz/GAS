//
//  Constants.swift
//  Motive
//

import Foundation

nonisolated enum MotiveConstants: Sendable {
    nonisolated enum Timeouts: Sendable {
        /// API request timeout (seconds)
        static let apiRequest: TimeInterval = 30
        /// API resource timeout (seconds)
        static let apiResource: TimeInterval = 300
        /// Session inactivity soft warning threshold (seconds).
        /// Used to inform users that the model is still processing.
        static let sessionActivityWarning: TimeInterval = 30
        /// Session inactivity hard failure threshold (seconds).
        /// If no events arrive before this timeout, terminate the run.
        static let sessionActivityFail: TimeInterval = 180
        /// Delay before dismissing reasoning bubble (seconds)
        static let reasoningDismiss: TimeInterval = 2
        /// Server port detection timeout (seconds)
        static let portDetection: TimeInterval = 30
        /// Graceful server shutdown wait (seconds)
        static let gracefulShutdown: TimeInterval = 2

        /// Server process startup poll interval (seconds)
        static let serverStartupPoll: TimeInterval = 0.1
        /// Server health check interval (seconds)
        static let serverHealthCheck: TimeInterval = 0.5
    }

    nonisolated enum SSE: Sendable {
        /// Maximum reconnection backoff delay (seconds)
        static let reconnectMaxDelay: TimeInterval = 30
    }

    nonisolated enum Limits: Sendable {
        /// Maximum number of recent projects to keep
        static let maxRecentProjects = 10
        /// Maximum server restart attempts before giving up
        static let maxServerRestartAttempts = 3
    }
}
