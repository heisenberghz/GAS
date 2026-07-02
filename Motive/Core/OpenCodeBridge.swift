//
//  OpenCodeBridge.swift
//  Motive
//
//  Coordinator for the OpenCode HTTP server, SSE client, and REST API client.
//  Replaces the previous PTY-based approach with structured SSE events and REST APIs.
//

import Foundation

actor OpenCodeBridge {

    // MARK: - Configuration

    struct Configuration: Sendable {
        let binaryURL: URL
        let environment: [String: String]
        let model: String? // Raw user model override (if any)
        let modelProviderID: String? // Selected provider ID for raw model names
        let agent: String? // e.g., "motive", "plan" — per-message agent override
        let debugMode: Bool
        let projectDirectory: String // Current project directory for server CWD
    }

    // MARK: - Properties

    private var configuration: Configuration?
    private let server = OpenCodeServer()
    private let sseClient = SSEClient()
    private let apiClient = OpenCodeAPIClient()
    private var eventTask: Task<Void, Never>?

    private var currentSessionId: String?
    private var activeSessions: Set<String> = [] // Multi-session ready

    /// SessionID -> directory mapping for deterministic routing.
    private var sessionDirectory: [String: String] = [:]
    /// Request ID -> directory for question/permission reply routing.
    private var questionDirectory: [String: String] = [:]
    private var permissionDirectory: [String: String] = [:]

    /// Last reported agent per session (deduplication for message.updated floods)
    private var lastReportedAgent: [String: String] = [:]

    /// Session IDs waiting for the first meaningful output event after prompt submission.
    /// If a session goes idle while still in this set, treat it as failure (empty/no-op run).
    private var waitingForFirstOutput: Set<String> = []
    private let maxRetryBeforeFailure = 3

    /// Health check task: after global SSE reconnects, checks active sessions.
    private var reconnectHealthTask: Task<Void, Never>?

    /// Non-blocking event channel to AppState.
    /// `yield()` never blocks the bridge actor; AppState consumes on MainActor.
    /// AsyncStream preserves FIFO ordering, so events arrive in correct sequence.
    private let eventContinuation: AsyncStream<OpenCodeEvent>.Continuation

    // MARK: - Init

    init(eventContinuation: AsyncStream<OpenCodeEvent>.Continuation) {
        self.eventContinuation = eventContinuation
    }

    // MARK: - Configuration

    func updateConfiguration(_ configuration: Configuration) {
        self.configuration = configuration
    }

    // MARK: - Server Lifecycle

    /// Synchronous server termination — safe to call from `applicationWillTerminate`.
    /// Bypasses actor isolation via the server's lock-protected PID.
    nonisolated func terminateServerImmediately() {
        server.terminateImmediately()
    }

    /// Start the HTTP server and connect SSE if not already running.
    func startIfNeeded() async {
        guard let configuration else {
            Log.error("Cannot start: no configuration")
            return
        }

        guard await !server.isRunning else {
            Log.bridge("Server already running")
            return
        }

        do {
            let serverConfig = OpenCodeServer.Configuration(
                binaryURL: configuration.binaryURL,
                environment: configuration.environment,
                workingDirectory: currentWorkingDirectory()
            )

            // Register restart handler BEFORE starting so it's ready
            // if the server crashes immediately after start
            await server.setRestartHandler { [weak self] newURL in
                await self?.handleServerRestart(newURL)
            }

            let url = try await server.start(configuration: serverConfig)
            await apiClient.updateBaseURL(url)
            await apiClient.updateDirectory(currentWorkingDirectory())

            // Don't start SSE here — submitIntent will lazily start global SSE.

            Log.bridge("Bridge started with server at \(url.absoluteString)")
        } catch OpenCodeServer.ServerError.alreadyRunning {
            // A concurrent start (crash recovery or duplicate call) is in progress.
            // Poll server.isRunning from the bridge actor — each check is a brief
            // cross-actor read that won't block detectPort() on the server actor.
            Log.bridge("Concurrent start detected, waiting for server to become ready...")
            for _ in 0 ..< 30 {
                try? await Task.sleep(for: .milliseconds(500))
                if await server.isRunning { break }
            }
            if let url = await server.serverURL {
                await apiClient.updateBaseURL(url)
                await apiClient.updateDirectory(currentWorkingDirectory())
                Log.bridge("Server became ready at \(url.absoluteString)")
            }
        } catch {
            Log.error("Failed to start server: \(error.localizedDescription)")
            eventContinuation.yield(OpenCodeEvent(
                kind: .error,
                rawJson: "",
                text: "Failed to start OpenCode: \(error.localizedDescription)"
            ))
        }
    }

    /// Called by OpenCodeServer when the server auto-restarts on a new URL.
    /// Reconnects SSE and updates the API client to point at the new port.
    private func handleServerRestart(_ newURL: URL) async {
        Log.bridge("Server restarted at \(newURL.absoluteString), reconnecting global SSE...")

        // Update API client to the new URL
        await apiClient.updateBaseURL(newURL)
        await sseClient.disconnect()
        startGlobalEventLoop(baseURL: newURL)
        waitingForFirstOutput.removeAll()
        Log.bridge("Reconnected global SSE at \(newURL.absoluteString)")
    }

    /// Stop the server and SSE.
    func stop() async {
        eventTask?.cancel()
        eventTask = nil
        await sseClient.disconnect()
        await server.stop()
        activeSessions.removeAll()
        waitingForFirstOutput.removeAll()
        sessionDirectory.removeAll()
        questionDirectory.removeAll()
        permissionDirectory.removeAll()
        reconnectHealthTask?.cancel()
        reconnectHealthTask = nil
        Log.bridge("Bridge stopped")
    }

    /// Restart: stop everything and start fresh.
    func restart() async {
        await stop()
        await startIfNeeded()
    }

    // MARK: - Session Management

    /// Get the current OpenCode session ID.
    func getSessionId() -> String? {
        currentSessionId
    }

    /// Set the current session ID (for switching sessions / interrupt targeting).
    /// Does NOT remove the old session from activeSessions — background sessions
    /// must remain tracked so their SSE events continue to flow through isTrackedSession.
    func setSessionId(_ sessionId: String?) {
        currentSessionId = sessionId
        if let sessionId {
            activeSessions.insert(sessionId)
        }
        Log.bridge("Session ID set to: \(sessionId ?? "nil"), active sessions: \(activeSessions.count)")
    }

    /// Remove a completed/failed session from active tracking.
    /// Called by AppState when a session finishes or errors out.
    /// This stops the bridge from forwarding further events for this session.
    func removeActiveSession(_ sessionId: String) {
        activeSessions.remove(sessionId)
        sessionDirectory.removeValue(forKey: sessionId)
        lastReportedAgent.removeValue(forKey: sessionId)
        waitingForFirstOutput.remove(sessionId)
        if currentSessionId == sessionId {
            currentSessionId = nil
        }
        Log.bridge("Removed active session: \(sessionId), remaining: \(activeSessions.count)")
    }

    // MARK: - Intent Submission

    /// Submit a new intent (run a task).
    /// - Parameter forceNewSession: If true, clears `currentSessionId` atomically before creating
    ///   a new session. This prevents the race condition where multiple concurrent Tasks
    ///   interleave their setSessionId(nil) + submitIntent calls on the bridge actor.
    func submitIntent(
        text: String,
        cwd: String,
        agent: String? = nil,
        forceNewSession: Bool = false,
        correlationId: String? = nil
    ) async {
        if forceNewSession {
            currentSessionId = nil
        }
        guard configuration != nil else {
            eventContinuation.yield(OpenCodeEvent(
                kind: .error,
                rawJson: "",
                text: "OpenCode not configured"
            ))
            return
        }

        // Ensure server is running
        if await !server.isRunning {
            await startIfNeeded()
            guard await server.isRunning else { return }
        }

        if let url = await server.serverURL {
            await ensureGlobalEventLoop(baseURL: url)
        }

        do {
            try await submitPrompt(
                text: text,
                cwd: cwd,
                agentOverride: agent,
                forceNewSession: forceNewSession,
                correlationId: correlationId
            )
        } catch {
            Log.error("Failed to submit intent: \(error.localizedDescription)")
            eventContinuation.yield(OpenCodeEvent(
                kind: .unknown,
                rawJson: "__session_bind_failed__",
                text: error.localizedDescription,
                toolCallId: correlationId
            ))
            eventContinuation.yield(OpenCodeEvent(
                kind: .error,
                rawJson: "",
                text: "Failed to submit task: \(error.localizedDescription)"
            ))
        }
    }

    /// Resume an existing session with a new message.
    func resumeSession(sessionId: String, text: String, cwd: String, agent: String? = nil) async {
        currentSessionId = sessionId
        activeSessions.insert(sessionId)
        sessionDirectory[sessionId] = cwd
        await submitIntent(text: text, cwd: cwd, agent: agent)
    }

    // MARK: - Interruption

    /// Interrupt/abort the current session.
    func interrupt() async {
        guard let sessionId = currentSessionId else {
            Log.warning("No active session to interrupt")
            return
        }

        do {
            await apiClient.updateDirectory(resolveDirectory(forSessionID: sessionId))
            try await apiClient.abortSession(id: sessionId)
            Log.bridge("Aborted session: \(sessionId)")
        } catch {
            Log.error("Failed to abort session: \(error.localizedDescription)")
        }
    }

    // MARK: - Native Question/Permission Replies

    /// Reply to a native question from OpenCode.
    func replyToQuestion(requestID: String, answers: [[String]], sessionID: String? = nil) async {
        do {
            await apiClient.updateDirectory(resolveDirectory(forQuestionID: requestID, sessionID: sessionID))
            try await apiClient.replyToQuestion(requestID: requestID, answers: answers)
            questionDirectory.removeValue(forKey: requestID)
        } catch {
            Log.error("Failed to reply to question \(requestID): \(error.localizedDescription)")
        }
    }

    /// Reject a native question (user cancelled).
    func rejectQuestion(requestID: String, sessionID: String? = nil) async {
        do {
            await apiClient.updateDirectory(resolveDirectory(forQuestionID: requestID, sessionID: sessionID))
            try await apiClient.rejectQuestion(requestID: requestID)
            questionDirectory.removeValue(forKey: requestID)
        } catch {
            Log.error("Failed to reject question \(requestID): \(error.localizedDescription)")
        }
    }

    /// Reply to a native permission request.
    func replyToPermission(
        requestID: String,
        reply: OpenCodeAPIClient.PermissionReply,
        sessionID: String? = nil
    ) async {
        do {
            await apiClient.updateDirectory(resolveDirectory(forPermissionID: requestID, sessionID: sessionID))
            try await apiClient.replyToPermission(requestID: requestID, reply: reply)
            permissionDirectory.removeValue(forKey: requestID)
        } catch {
            Log.error("Failed to reply to permission \(requestID): \(error.localizedDescription)")
        }
    }

    // MARK: - SSE Event Loop

    private func ensureGlobalEventLoop(baseURL: URL) async {
        let sseAlive = await sseClient.hasActiveStream
        if sseAlive { return }
        startGlobalEventLoop(baseURL: baseURL)
    }

    private func startGlobalEventLoop(baseURL: URL) {
        eventTask?.cancel()
        eventTask = Task { [weak self] in
            guard let self else { return }
            let stream = await self.sseClient.connectGlobal(to: baseURL)
            for await scopedEvent in stream {
                guard !Task.isCancelled else { break }
                await self.handleSSEEvent(scopedEvent.event, sourceDirectory: scopedEvent.directory)
            }
            Log.bridge("Global SSE event loop ended")
        }
    }

    /// Route an SSE event to the appropriate handler.
    /// Most handlers are now synchronous (non-blocking yield to AsyncStream).
    private func handleSSEEvent(_ event: SSEClient.SSEEvent, sourceDirectory: String?) {
        switch event {
        case .connected:
            Log.bridge("Global SSE connected")
            startReconnectHealthCheck()

        case .heartbeat:
            break

        case let .textDelta(info):
            observeSessionDirectory(sessionID: info.sessionID, sourceDirectory: sourceDirectory)
            handleTextDelta(info)

        case let .textComplete(info):
            observeSessionDirectory(sessionID: info.sessionID, sourceDirectory: sourceDirectory)
            handleTextComplete(info)

        case let .reasoningDelta(info):
            observeSessionDirectory(sessionID: info.sessionID, sourceDirectory: sourceDirectory)
            handleReasoningDelta(info)

        case let .toolRunning(info):
            observeSessionDirectory(sessionID: info.sessionID, sourceDirectory: sourceDirectory)
            handleToolRunning(info)

        case let .toolCompleted(info):
            observeSessionDirectory(sessionID: info.sessionID, sourceDirectory: sourceDirectory)
            handleToolCompleted(info)

        case let .toolError(info):
            observeSessionDirectory(sessionID: info.sessionID, sourceDirectory: sourceDirectory)
            handleToolError(info)

        case let .usageUpdated(info):
            observeSessionDirectory(sessionID: info.sessionID, sourceDirectory: sourceDirectory)
            handleUsageUpdate(info)

        case let .sessionIdle(sessionID):
            observeSessionDirectory(sessionID: sessionID, sourceDirectory: sourceDirectory)
            handleSessionIdle(sessionID)

        case let .sessionStatus(info):
            observeSessionDirectory(sessionID: info.sessionID, sourceDirectory: sourceDirectory)
            guard isTrackedSession(info.sessionID) else { return }
            handleSessionStatus(info)

        case let .sessionError(info):
            observeSessionDirectory(sessionID: info.sessionID, sourceDirectory: sourceDirectory)
            handleSessionError(info)

        case let .questionAsked(request):
            handleQuestionSSEEvent(request, sourceDirectory: sourceDirectory)

        case let .permissionAsked(request):
            handlePermissionSSEEvent(request, sourceDirectory: sourceDirectory)

        case let .agentChanged(info):
            observeSessionDirectory(sessionID: info.sessionID, sourceDirectory: sourceDirectory)
            handleAgentChanged(info)
        }
    }

    // MARK: - Text Event Handlers

    private func handleTextDelta(_ info: SSEClient.TextDeltaInfo) {
        guard isTrackedSession(info.sessionID) else { return }
        waitingForFirstOutput.remove(info.sessionID)
        eventContinuation.yield(OpenCodeEvent(
            kind: .assistant,
            rawJson: "",
            text: info.delta,
            sessionId: info.sessionID
        ))
    }

    private func handleTextComplete(_ info: SSEClient.TextCompleteInfo) {
        guard isTrackedSession(info.sessionID) else { return }
        // Text completion is a lifecycle marker; no state to update.
    }

    private func handleReasoningDelta(_ info: SSEClient.ReasoningDeltaInfo) {
        guard isTrackedSession(info.sessionID) else { return }
        waitingForFirstOutput.remove(info.sessionID)
        eventContinuation.yield(OpenCodeEvent(
            kind: .thought,
            rawJson: "",
            text: info.delta,
            sessionId: info.sessionID
        ))
    }

    // MARK: - Tool Event Handlers

    private func handleToolRunning(_ info: SSEClient.ToolInfo) {
        guard isTrackedSession(info.sessionID) else { return }
        waitingForFirstOutput.remove(info.sessionID)
        eventContinuation.yield(OpenCodeEvent(
            kind: .tool,
            rawJson: "",
            text: info.inputSummary ?? "",
            toolName: info.toolName,
            toolInput: info.inputSummary,
            toolInputJSON: info.inputJSON,
            toolCallId: info.toolCallID,
            sessionId: info.sessionID
        ))
    }

    private func handleToolCompleted(_ info: SSEClient.ToolCompletedInfo) {
        guard isTrackedSession(info.sessionID) else { return }
        waitingForFirstOutput.remove(info.sessionID)
        eventContinuation.yield(OpenCodeEvent(
            kind: .tool,
            rawJson: "",
            text: info.inputSummary ?? "",
            toolName: info.toolName,
            toolInput: info.inputSummary,
            toolInputJSON: info.inputJSON,
            toolOutput: info.output,
            toolCallId: info.toolCallID,
            sessionId: info.sessionID,
            diff: info.diff
        ))
    }

    private func handleToolError(_ info: SSEClient.ToolErrorInfo) {
        guard isTrackedSession(info.sessionID) else { return }
        waitingForFirstOutput.remove(info.sessionID)
        eventContinuation.yield(OpenCodeEvent(
            kind: .tool,
            rawJson: "",
            text: info.error,
            toolName: info.toolName,
            toolOutput: "Error: \(info.error)",
            toolCallId: info.toolCallID,
            sessionId: info.sessionID
        ))
    }

    // MARK: - Usage Event Handler

    private func handleUsageUpdate(_ info: SSEClient.UsageInfo) {
        guard isTrackedSession(info.sessionID) else { return }
        waitingForFirstOutput.remove(info.sessionID)
        eventContinuation.yield(OpenCodeEvent(
            kind: .usage,
            rawJson: "",
            text: "",
            sessionId: info.sessionID,
            model: info.model,
            usage: info.usage,
            cost: info.cost,
            messageId: info.messageID
        ))
    }

    // MARK: - Session Lifecycle Handlers

    private func handleSessionIdle(_ sessionID: String) {
        guard isTrackedSession(sessionID) else { return }
        let hadNoOutput = waitingForFirstOutput.contains(sessionID)
        waitingForFirstOutput.remove(sessionID)
        lastReportedAgent.removeValue(forKey: sessionID)
        if hadNoOutput {
            eventContinuation.yield(OpenCodeEvent(
                kind: .error,
                rawJson: "",
                text: "No output from provider. Check model/base URL/API key and retry.",
                sessionId: sessionID
            ))
        } else {
            eventContinuation.yield(OpenCodeEvent(
                kind: .finish,
                rawJson: "",
                text: "Completed",
                sessionId: sessionID
            ))
        }
    }

    private func handleSessionError(_ info: SSEClient.SessionErrorInfo) {
        guard isTrackedSession(info.sessionID) else { return }
        waitingForFirstOutput.remove(info.sessionID)
        lastReportedAgent.removeValue(forKey: info.sessionID)
        eventContinuation.yield(OpenCodeEvent(
            kind: .error,
            rawJson: "",
            text: info.error,
            sessionId: info.sessionID
        ))
    }

    private func handleSessionStatus(_ info: SSEClient.SessionStatusInfo) {
        guard info.status == "retry" else { return }
        let attempt = info.attempt ?? 0
        let reason = info.message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let detail = reason.isEmpty ? "Request failed and OpenCode is retrying." : reason
        Log.warning("Session retry status: sid=\(info.sessionID) attempt=\(attempt) reason=\(detail)")

        // Fail fast after a few retries so users don't wait through long exponential backoff.
        guard attempt >= maxRetryBeforeFailure else { return }

        waitingForFirstOutput.remove(info.sessionID)
        lastReportedAgent.removeValue(forKey: info.sessionID)
        eventContinuation.yield(OpenCodeEvent(
            kind: .error,
            rawJson: "",
            text: "Provider request failed after \(attempt) retries: \(detail)",
            sessionId: info.sessionID
        ))
    }

    // MARK: - Agent Change Handler

    private func handleAgentChanged(_ info: SSEClient.AgentChangeInfo) {
        guard isTrackedSession(info.sessionID) else { return }

        // Deduplicate: message.updated fires frequently with the same agent
        let key = info.sessionID
        if lastReportedAgent[key] == info.agent { return }
        lastReportedAgent[key] = info.agent

        eventContinuation.yield(OpenCodeEvent(
            kind: .assistant,
            rawJson: "",
            text: "",
            sessionId: info.sessionID,
            agent: info.agent
        ))
    }

    // MARK: - Native Prompt Handlers

    private func handleQuestionSSEEvent(_ request: SSEClient.QuestionRequest, sourceDirectory: String?) {
        guard isTrackedSession(request.sessionID) else { return }
        let resolvedDirectory = sourceDirectory ?? resolveDirectory(forSessionID: request.sessionID)
        questionDirectory[request.id] = resolvedDirectory
        if sessionDirectory[request.sessionID] == nil {
            sessionDirectory[request.sessionID] = resolvedDirectory
        }
        eventContinuation.yield(OpenCodeEvent(
            kind: .tool,
            rawJson: encodeQuestionAsJSON(request),
            text: request.questions.first?.question ?? "Question",
            toolName: "Question",
            toolInput: request.questions.first?.question,
            toolInputJSON: OpenCodeEvent.serializeJSON(buildQuestionInputDict(request)),
            sessionId: request.sessionID
        ))
    }

    private func handlePermissionSSEEvent(_ request: SSEClient.NativePermissionRequest, sourceDirectory: String?) {
        guard isTrackedSession(request.sessionID) else { return }
        let resolvedDirectory = sourceDirectory ?? resolveDirectory(forSessionID: request.sessionID)
        permissionDirectory[request.id] = resolvedDirectory
        if sessionDirectory[request.sessionID] == nil {
            sessionDirectory[request.sessionID] = resolvedDirectory
        }
        eventContinuation.yield(OpenCodeEvent(
            kind: .tool,
            rawJson: encodePermissionAsJSON(request),
            text: "Permission: \(request.permission) for \(request.patterns.joined(separator: ", "))",
            toolName: "Permission",
            toolInput: request.patterns.joined(separator: ", "),
            toolInputJSON: OpenCodeEvent.serializeJSON(buildPermissionInputDict(request)),
            sessionId: request.sessionID
        ))
    }

    // MARK: - Reconnection Health Check

    /// After global SSE reconnects, check whether active sessions keep progressing.
    private func startReconnectHealthCheck() {
        reconnectHealthTask?.cancel()
        guard !activeSessions.isEmpty else { return }
        let sessionsAtReconnect = activeSessions

        reconnectHealthTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled, let self else { return }
            let currentActive = await self.getActiveSessions()
            let stillTracked = sessionsAtReconnect.filter { currentActive.contains($0) }
            if !stillTracked.isEmpty {
                Log.warning("Global SSE reconnect health: \(stillTracked.count) session(s) still active after reconnect")
            }
        }
    }

    private func getActiveSessions() -> Set<String> {
        activeSessions
    }

    private func observeSessionDirectory(sessionID: String, sourceDirectory: String?) {
        guard let sourceDirectory, !sourceDirectory.isEmpty else { return }
        if sessionDirectory[sessionID] == nil {
            sessionDirectory[sessionID] = sourceDirectory
        }
    }

    // MARK: - Helpers

    private func isTrackedSession(_ sessionID: String) -> Bool {
        // If no sessions are actively tracked, accept all events
        // This handles the case before a session is created
        if activeSessions.isEmpty { return true }
        return activeSessions.contains(sessionID)
    }

    private func currentWorkingDirectory() -> String {
        if let dir = configuration?.projectDirectory, !dir.isEmpty {
            return dir
        }
        return FileManager.default.homeDirectoryForCurrentUser.path
    }

    private func resolveDirectory(forSessionID sessionID: String?) -> String {
        guard let sessionID else { return currentWorkingDirectory() }
        return sessionDirectory[sessionID] ?? currentWorkingDirectory()
    }

    private func resolveDirectory(forQuestionID requestID: String, sessionID: String?) -> String {
        if let sessionID {
            return resolveDirectory(forSessionID: sessionID)
        }
        if let directory = questionDirectory[requestID] {
            return directory
        }
        return currentWorkingDirectory()
    }

    private func resolveDirectory(forPermissionID requestID: String, sessionID: String?) -> String {
        if let sessionID {
            return resolveDirectory(forSessionID: sessionID)
        }
        if let directory = permissionDirectory[requestID] {
            return directory
        }
        return currentWorkingDirectory()
    }

    private func submitPrompt(
        text: String,
        cwd: String,
        agentOverride: String? = nil,
        forceNewSession: Bool = false,
        correlationId: String? = nil
    ) async throws {
        // Create or reuse session.
        // When forceNewSession is true, ALWAYS create a new OC session.
        // This prevents actor reentrancy from causing a concurrent call
        // to accidentally reuse another call's freshly-created session.
        let sessionID: String
        if !forceNewSession, let existing = currentSessionId {
            sessionID = existing
            Log.bridge("Reusing existing session: \(sessionID)")
        } else {
            await apiClient.updateDirectory(cwd)
            let session = try await apiClient.createSession()
            sessionID = session.id
            currentSessionId = sessionID
            activeSessions.insert(sessionID)
            sessionDirectory[sessionID] = cwd
            waitingForFirstOutput.insert(sessionID)
            Log.bridge("Created new session: \(sessionID)")

            eventContinuation.yield(OpenCodeEvent(
                kind: .unknown,
                rawJson: "__session_bind__",
                text: "",
                toolCallId: correlationId,
                sessionId: sessionID
            ))
        }

        // Ensure directory mapping exists for reused sessions as well.
        if sessionDirectory[sessionID] == nil {
            sessionDirectory[sessionID] = cwd
        }
        waitingForFirstOutput.insert(sessionID)
        let directory = resolveDirectory(forSessionID: sessionID)
        if let url = await server.serverURL {
            await ensureGlobalEventLoop(baseURL: url)
        }

        let sessionCount = activeSessions.count
        let sseAlive = await sseClient.hasActiveStream
        let sseConnected = await sseClient.connected
        Log.bridge("Active sessions: \(sessionCount), global SSE alive: \(sseAlive), connected: \(sseConnected)")

        // Send prompt asynchronously (results via SSE)
        // Use explicit agent override if provided, otherwise fall back to configuration
        let agent = agentOverride ?? configuration?.agent
        await apiClient.updateDirectory(directory)
        try await apiClient.sendPromptAsync(
            sessionID: sessionID,
            text: text,
            model: configuration?.model,
            modelProviderID: configuration?.modelProviderID,
            agent: agent
        )
        Log.bridge("Submitted intent to session \(sessionID)")
    }

    // MARK: - JSON Encoding Helpers

    private func encodeQuestionAsJSON(_ request: SSEClient.QuestionRequest) -> String {
        var dict: [String: Any] = [
            "type": "question.asked",
            "id": request.id,
            "sessionID": request.sessionID,
        ]

        let questions = request.questions.map { q -> [String: Any] in
            var qDict: [String: Any] = [
                "question": q.question,
                "multiple": q.multiple,
                "custom": q.custom,
            ]
            qDict["options"] = q.options.map { opt -> [String: Any] in
                var optDict: [String: Any] = ["label": opt.label]
                if let desc = opt.description {
                    optDict["description"] = desc
                }
                return optDict
            }
            return qDict
        }
        dict["questions"] = questions

        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return str
    }

    private func encodePermissionAsJSON(_ request: SSEClient.NativePermissionRequest) -> String {
        let dict: [String: Any] = [
            "type": "permission.asked",
            "id": request.id,
            "sessionID": request.sessionID,
            "permission": request.permission,
            "patterns": request.patterns,
            "metadata": request.metadata,
            "always": request.always,
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return str
    }

    private func buildQuestionInputDict(_ request: SSEClient.QuestionRequest) -> [String: Any] {
        var dict: [String: Any] = [
            "_nativeQuestionID": request.id,
            "_isNativeQuestion": true,
        ]

        if let first = request.questions.first {
            dict["question"] = first.question
            dict["custom"] = first.custom
            dict["multiple"] = first.multiple
            dict["options"] = first.options.map { opt -> [String: Any] in
                var d: [String: Any] = ["label": opt.label]
                if let desc = opt.description {
                    d["description"] = desc
                }
                return d
            }
        }

        // Pass tool context for plan_exit detection
        if let toolContext = request.toolContext {
            dict["_toolContext"] = toolContext
        }
        if let planFilePath = request.planFilePath, !planFilePath.isEmpty {
            dict["_planFilePath"] = planFilePath
        }

        return dict
    }

    private func buildPermissionInputDict(_ request: SSEClient.NativePermissionRequest) -> [String: Any] {
        [
            "_nativePermissionID": request.id,
            "_isNativePermission": true,
            "permission": request.permission,
            "patterns": request.patterns,
            "metadata": request.metadata,
            "always": request.always,
        ]
    }
}
