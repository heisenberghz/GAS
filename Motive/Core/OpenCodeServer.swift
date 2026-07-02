//
//  OpenCodeServer.swift
//  Motive
//
//  Manages the persistent `opencode serve` background process.
//  Uses Foundation Process directly (no PTY needed for HTTP server).
//

import Foundation
import os

/// Manages the `opencode serve` HTTP server process lifecycle.
///
/// Responsibilities:
/// - Spawn `opencode serve --port 0` via Foundation Process
/// - Parse stdout for the actual port ("listening on http://...")
/// - Health check via HTTP GET
/// - Auto-restart on crash with exponential backoff (max 3 retries)
/// - Graceful shutdown: SIGTERM -> wait 2s -> SIGKILL
/// - Notify via `onRestart` when the server restarts on a new URL
actor OpenCodeServer {

    // MARK: - Types

    struct Configuration: Sendable {
        let binaryURL: URL
        let environment: [String: String]
        let workingDirectory: String
    }

    enum ServerError: Error, LocalizedError {
        case notConfigured
        case startFailed(String)
        case portDetectionTimeout
        case maxRetriesExceeded(attempts: Int)
        case alreadyRunning

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                "Server not configured"
            case let .startFailed(reason):
                "Failed to start OpenCode server: \(reason)"
            case .portDetectionTimeout:
                "Timed out waiting for server to report its port"
            case let .maxRetriesExceeded(attempts):
                "Server failed to start after \(attempts) attempts"
            case .alreadyRunning:
                "Server is already running"
            }
        }
    }

    private enum State: Sendable {
        case stopped
        case starting
        case running(URL)
        case crashed
    }

    // MARK: - Properties

    private var process: Process?
    private var stdoutPipe: Pipe?
    private var state: State = .stopped
    private var monitorTask: Task<Void, Never>?
    private var stdoutDrainTask: Task<Void, Never>?
    private var stderrDrainTask: Task<Void, Never>?
    private var restartCount: Int = 0
    private static let maxRestartAttempts = MotiveConstants.Limits.maxServerRestartAttempts
    private static let portDetectionTimeoutSeconds: TimeInterval = MotiveConstants.Timeouts.portDetection
    private static let gracefulShutdownSeconds: TimeInterval = MotiveConstants.Timeouts.gracefulShutdown

    /// Called when the server restarts on a new URL after a crash.
    /// The Bridge uses this to update SSE and API client URLs.
    private var onRestart: (@Sendable (URL) async -> Void)?

    private let logger = Logger(subsystem: "com.velvet.motive", category: "OpenCodeServer")

    /// Thread-safe PID for synchronous shutdown from `applicationWillTerminate`.
    /// Actor isolation cannot be awaited in synchronous contexts, so this lock-protected
    /// value allows `nonisolated` methods to read the PID without crossing the actor boundary.
    private let currentPID = OSAllocatedUnfairLock<pid_t?>(initialState: nil)

    /// The URL of the running server, if available.
    var serverURL: URL? {
        if case let .running(url) = state {
            return url
        }
        return nil
    }

    /// Whether the server process is currently running.
    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    // MARK: - Lifecycle

    /// Set a handler that fires when the server restarts on a new URL.
    func setRestartHandler(_ handler: @escaping @Sendable (URL) async -> Void) {
        self.onRestart = handler
    }

    /// Start the server and return the base URL once it's ready.
    ///
    /// - Parameter configuration: Binary path, environment, and working directory.
    /// - Returns: The base URL of the running server.
    /// - Throws: `ServerError` if the server fails to start.
    func start(configuration: Configuration) async throws -> URL {
        if case let .running(url) = state {
            logger.info("Server already running at \(url.absoluteString)")
            return url
        }

        if case .starting = state {
            logger.warning("Ignoring concurrent start request while server is already starting")
            throw ServerError.alreadyRunning
        }

        state = .starting
        restartCount = 0

        do {
            let url = try await spawnAndDetectPort(configuration: configuration)
            state = .running(url)
            startMonitor(configuration: configuration)
            logger.info("OpenCode server started at \(url.absoluteString)")
            return url
        } catch {
            cleanupCurrentProcess()
            state = .stopped
            throw error
        }
    }

    /// Stop the server gracefully.
    func stop() async {
        monitorTask?.cancel()
        monitorTask = nil
        stdoutDrainTask?.cancel()
        stdoutDrainTask = nil
        stderrDrainTask?.cancel()
        stderrDrainTask = nil

        // Mark stopped IMMEDIATELY — before the graceful-shutdown wait loop.
        // The wait loop has `await` suspension points where a racing handleCrash()
        // could re-enter the actor and spawn a new process. Setting .stopped first
        // ensures handleCrash() sees it and bails out.
        let processToStop = self.process
        state = .stopped
        restartCount = 0

        guard let processToStop else {
            self.process = nil
            self.stdoutPipe = nil
            clearPIDFile()
            return
        }

        logger.info("Stopping OpenCode server (PID: \(processToStop.processIdentifier))...")

        processToStop.terminate()

        let deadline = Date().addingTimeInterval(Self.gracefulShutdownSeconds)
        while processToStop.isRunning, Date() < deadline {
            try? await Task.sleep(nanoseconds: UInt64(MotiveConstants.Timeouts.serverStartupPoll * 1_000_000_000))
        }

        if processToStop.isRunning {
            logger.warning("Server did not stop gracefully, sending SIGKILL")
            kill(processToStop.processIdentifier, SIGKILL)
        }

        // Final cleanup — also catches any process a racing handleCrash()
        // managed to spawn before seeing .stopped (belt-and-suspenders).
        cleanupCurrentProcess()
        logger.info("OpenCode server stopped")
    }

    /// Check if the server is healthy by making a simple HTTP request.
    func isHealthy() async -> Bool {
        guard let url = serverURL else { return false }

        let healthURL = url.appendingPathComponent("session")
        var request = URLRequest(url: healthURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 5

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                return (200 ... 499).contains(httpResponse.statusCode)
            }
            return false
        } catch {
            return false
        }
    }

    // MARK: - Internal

    /// Spawn the process and wait for the port to appear in stdout.
    private func spawnAndDetectPort(configuration: Configuration) async throws -> URL {
        let proc = Process()
        proc.executableURL = configuration.binaryURL
        proc.arguments = ["serve", "--port", "0", "--hostname", "127.0.0.1"]
        proc.currentDirectoryURL = URL(fileURLWithPath: configuration.workingDirectory)

        // Set environment
        var env = ProcessInfo.processInfo.environment
        for (key, value) in configuration.environment {
            env[key] = value
        }
        if env["TERM"] == nil {
            env["TERM"] = "dumb"
        }
        proc.environment = env

        // Create pipes for stdout (stderr logged via separate pipe for diagnostics)
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
        } catch {
            throw ServerError.startFailed(error.localizedDescription)
        }

        self.process = proc
        self.stdoutPipe = pipe
        writePIDFile(proc.processIdentifier)
        logger.info("Spawned opencode serve (PID: \(proc.processIdentifier)) binary: \(configuration.binaryURL.path)")

        // Read lines until we find the port announcement
        return try await detectPort(from: pipe.fileHandleForReading)
    }

    /// Read stdout lines looking for the "listening on http://..." message.
    /// After finding the port, continues draining stdout in the background
    /// to prevent the pipe buffer from filling and blocking the child process.
    private func detectPort(from fileHandle: FileHandle) async throws -> URL {
        let lines = fileHandle.bytes.lines
        let deadline = Date().addingTimeInterval(Self.portDetectionTimeoutSeconds)

        var iterator = lines.makeAsyncIterator()

        do {
            while let line = try await iterator.next() {
                guard Date() < deadline else {
                    throw ServerError.portDetectionTimeout
                }

                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                logger.debug("Server output: \(trimmed)")

                // Look for the listening announcement
                if let url = parseListeningURL(from: trimmed) {
                    // Continue draining stdout in the background
                    startStdoutDrain(fileHandle: fileHandle)
                    return url
                }
            }
        } catch let error as ServerError {
            throw error
        } catch {
            if !Task.isCancelled {
                throw ServerError.startFailed("Stdout stream ended: \(error.localizedDescription)")
            }
        }

        throw ServerError.portDetectionTimeout
    }

    /// Continuously drain stdout to prevent buffer fill-up.
    /// Uses Task.detached to avoid competing with actor-isolated work.
    private func startStdoutDrain(fileHandle: FileHandle) {
        stdoutDrainTask?.cancel()
        let log = self.logger
        stdoutDrainTask = Task.detached {
            do {
                let lines = fileHandle.bytes.lines
                for try await line in lines {
                    guard !Task.isCancelled else { break }
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        log.debug("Server output: \(trimmed)")
                    }
                }
            } catch {
                if !Task.isCancelled {
                    log.debug("Server stdout drain ended: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Continuously drain stderr and log for diagnostics.
    /// Uses Task.detached to avoid competing with detectPort for actor execution.
    private func startStderrDrain(fileHandle: FileHandle) {
        stderrDrainTask?.cancel()
        let log = self.logger
        stderrDrainTask = Task.detached {
            do {
                let lines = fileHandle.bytes.lines
                for try await line in lines {
                    guard !Task.isCancelled else { break }
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        log.warning("Server stderr: \(trimmed)")
                    }
                }
            } catch {
                if !Task.isCancelled {
                    log.debug("Server stderr drain ended: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Parse a URL from a line like "listening on http://127.0.0.1:4096"
    func parseListeningURL(from line: String) -> URL? {
        let lowered = line.lowercased()
        guard lowered.contains("listening") else { return nil }

        let patterns = ["http://127.0.0.1:", "http://localhost:", "http://0.0.0.0:"]
        for pattern in patterns {
            guard let range = line.range(of: pattern, options: .caseInsensitive) else { continue }
            let afterPattern = line[range.upperBound...]
            let portString = afterPattern.prefix(while: { $0.isNumber })
            guard let port = Int(portString), port > 0 else { continue }
            return URL(string: "http://127.0.0.1:\(port)")
        }

        return nil
    }

    /// Monitor the server process and auto-restart on crash.
    private func startMonitor(configuration: Configuration) {
        monitorTask?.cancel()
        let log = self.logger
        monitorTask = Task { [weak self] in
            guard let self else { return }

            // Poll isRunning instead of blocking
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(MotiveConstants.Timeouts.serverHealthCheck * 1_000_000_000))
                guard !Task.isCancelled else { return }

                guard let process = await self.process else { return }
                if !process.isRunning {
                    guard !Task.isCancelled else { return }
                    let exitCode = process.terminationStatus
                    log.error("OpenCode server exited unexpectedly (code: \(exitCode))")
                    await self.handleCrash(configuration: configuration)
                    return
                }
            }
        }
    }

    /// Handle a server crash with exponential backoff restart.
    private func handleCrash(configuration: Configuration) async {
        stdoutDrainTask?.cancel()
        stdoutDrainTask = nil
        stderrDrainTask?.cancel()
        stderrDrainTask = nil
        cleanupCurrentProcess()
        state = .crashed

        restartCount += 1
        guard restartCount <= Self.maxRestartAttempts else {
            logger.error("Max restart attempts (\(Self.maxRestartAttempts)) exceeded, giving up")
            return
        }

        let delay = pow(2.0, Double(restartCount - 1)) // 1s, 2s, 4s
        logger.info("Restarting server in \(delay)s (attempt \(self.restartCount)/\(Self.maxRestartAttempts))...")

        do {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }

            // Another caller (e.g. startIfNeeded) may have started a new server
            // while we were sleeping. Bail out to avoid spawning a duplicate process.
            switch state {
            case .starting, .running, .stopped:
                logger.info("Server state changed during backoff (\(String(describing: self.state))), skipping crash restart")
                return
            case .crashed:
                break
            }

            state = .starting
            let url = try await spawnAndDetectPort(configuration: configuration)
            state = .running(url)
            startMonitor(configuration: configuration)
            logger.info("Server restarted successfully at \(url.absoluteString)")

            // Notify the bridge so it can reconnect SSE and update API client
            await onRestart?(url)
        } catch {
            // Only clean up if we own the current process (state is still .starting
            // from our transition above). If cancelled, another path may have already
            // taken ownership of self.process — cleaning up would kill their process.
            if case .starting = state {
                cleanupCurrentProcess()
                state = .crashed
            }
            if !Task.isCancelled {
                logger.error("Server restart failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Process Lifecycle Helpers

    /// Terminate the current process (if any) and clean up all references.
    private func cleanupCurrentProcess() {
        guard let process else {
            clearPIDFile()
            return
        }
        if process.isRunning {
            process.terminate()
            var waitMs = 0
            while waitMs < 500, process.isRunning {
                usleep(100_000)
                waitMs += 100
            }
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
        self.process = nil
        self.stdoutPipe = nil
        clearPIDFile()
    }

    // MARK: - PID File Management

    private static var pidFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Motive/opencode-server.pid")
    }

    private func writePIDFile(_ pid: pid_t) {
        currentPID.withLock { $0 = pid }
        try? "\(pid)".write(to: Self.pidFileURL, atomically: true, encoding: .utf8)
    }

    private func clearPIDFile() {
        currentPID.withLock { $0 = nil }
        try? FileManager.default.removeItem(at: Self.pidFileURL)
    }

    /// Synchronous process termination for `applicationWillTerminate`.
    ///
    /// Safe to call from any isolation domain — uses the lock-protected PID
    /// rather than actor-isolated state, so no `await` is needed.
    nonisolated func terminateImmediately() {
        guard let pid = currentPID.withLock({ $0 }), pid > 0 else { return }
        logger.info("Synchronous terminate for PID \(pid)")
        kill(pid, SIGTERM)
        var waitMs = 0
        while waitMs < 1000, kill(pid, 0) == 0 {
            usleep(100_000)
            waitMs += 100
        }
        if kill(pid, 0) == 0 {
            kill(pid, SIGKILL)
        }
        currentPID.withLock { $0 = nil }
        try? FileManager.default.removeItem(at: Self.pidFileURL)
    }

    /// Kill any stale server processes left over from a previous app run.
    ///
    /// Two-phase cleanup:
    /// 1. PID file — kill the tracked process.
    /// 2. `pgrep` — find and kill any orphaned `opencode serve` processes
    ///    that leaked due to actor reentrancy races in previous runs.
    static func terminateStaleProcess() {
        let log = Logger(subsystem: "com.velvet.motive", category: "OpenCodeServer")

        // Phase 1: PID file
        if let pidString = try? String(contentsOf: pidFileURL, encoding: .utf8),
           let pid = pid_t(pidString.trimmingCharacters(in: .whitespacesAndNewlines)),
           pid > 0
        {
            if kill(pid, 0) == 0 {
                log.info("Killing stale opencode server from PID file (PID: \(pid))")
                terminatePID(pid)
            }
            try? FileManager.default.removeItem(at: pidFileURL)
        }

        // Phase 2: kill orphaned `opencode serve` processes not tracked by PID file
        killOrphanedServeProcesses(log: log)
    }

    /// Find and kill all `opencode serve` processes owned by the current user.
    private static func killOrphanedServeProcesses(log: Logger) {
        let pgrep = Process()
        pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrep.arguments = ["-f", "opencode serve --port"]
        let pipe = Pipe()
        pgrep.standardOutput = pipe
        pgrep.standardError = FileHandle.nullDevice

        do { try pgrep.run() } catch { return }
        pgrep.waitUntilExit()

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let pids = output.split(separator: "\n")
            .compactMap { pid_t($0.trimmingCharacters(in: .whitespaces)) }
            .filter { $0 > 0 }

        guard !pids.isEmpty else { return }
        log.info("Killing \(pids.count) orphaned opencode serve process(es): \(pids)")
        for pid in pids {
            terminatePID(pid)
        }
    }

    private static func terminatePID(_ pid: pid_t) {
        kill(pid, SIGTERM)
        var waitMs = 0
        while waitMs < 1000, kill(pid, 0) == 0 {
            usleep(100_000)
            waitMs += 100
        }
        if kill(pid, 0) == 0 {
            kill(pid, SIGKILL)
        }
    }
}

// MARK: - Protocol Conformance

extension OpenCodeServer: OpenCodeServerProtocol {}
