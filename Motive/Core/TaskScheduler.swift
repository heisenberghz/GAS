//
//  TaskScheduler.swift
//  Motive
//
//  Created by Codex on 2026/2/16.
//

import Foundation
import os

struct ScheduledTaskSnapshot: Sendable {
    let id: UUID
    let nextRunAt: Date?
    let isEnabled: Bool
}

protocol ScheduledTaskExecuting: Sendable {
    func loadTaskSnapshots() async -> [ScheduledTaskSnapshot]
    func execute(taskID: UUID) async
}

actor TaskScheduler {
    private let executor: any ScheduledTaskExecuting
    private var schedulerTask: Task<Void, Never>?
    private var runningTaskIDs = Set<UUID>()
    private let idlePollInterval: Duration
    private let maxSleepChunk: Duration
    private let maxSleepChunkSeconds: TimeInterval
    private let logger = Logger(subsystem: "com.velvet.motive", category: "Scheduler")

    init(
        executor: any ScheduledTaskExecuting,
        idlePollInterval: Duration = .seconds(30),
        maxSleepChunk: Duration = .seconds(30)
    ) {
        self.executor = executor
        self.idlePollInterval = idlePollInterval
        self.maxSleepChunk = maxSleepChunk
        self.maxSleepChunkSeconds = maxSleepChunk.timeInterval
    }

    func start() {
        guard schedulerTask == nil else { return }
        schedulerTask = Task { [weak self] in
            await self?.runLoop()
        }
        logger.info("TaskScheduler started")
    }

    func stop() {
        schedulerTask?.cancel()
        schedulerTask = nil
        logger.info("TaskScheduler stopped")
    }

    func refresh() {
        guard schedulerTask != nil else { return }
        schedulerTask?.cancel()
        schedulerTask = Task { [weak self] in
            await self?.runLoop()
        }
        logger.debug("TaskScheduler refreshed")
    }

    func runNow(taskID: UUID) {
        guard !runningTaskIDs.contains(taskID) else { return }
        runningTaskIDs.insert(taskID)
        Task { [weak self] in
            await self?.executor.execute(taskID: taskID)
            await self?.markTaskCompleted(taskID)
        }
    }

    private func runLoop() async {
        while !Task.isCancelled {
            let now = Date()
            let snapshots = await executor.loadTaskSnapshots().filter {
                $0.isEnabled && $0.nextRunAt != nil
            }

            let dueTaskIDs = snapshots.compactMap { snapshot -> UUID? in
                guard let nextRunAt = snapshot.nextRunAt, nextRunAt <= now else { return nil }
                return snapshot.id
            }
            if !dueTaskIDs.isEmpty {
                logger.debug("Scheduler found \(dueTaskIDs.count) due task(s)")
                for taskID in dueTaskIDs where !runningTaskIDs.contains(taskID) {
                    runningTaskIDs.insert(taskID)
                    Task { [weak self] in
                        await self?.executor.execute(taskID: taskID)
                        await self?.markTaskCompleted(taskID)
                    }
                }
                continue
            }

            guard let nextRunAt = snapshots.compactMap(\.nextRunAt).min() else {
                try? await Task.sleep(for: idlePollInterval)
                continue
            }

            let delta = nextRunAt.timeIntervalSinceNow
            if delta <= 0 {
                continue
            }
            let sleepDuration = Duration.seconds(min(delta, maxSleepChunkSeconds))
            try? await Task.sleep(for: sleepDuration)
        }
    }

    private func markTaskCompleted(_ taskID: UUID) {
        runningTaskIDs.remove(taskID)
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let value = self.components
        return TimeInterval(value.seconds) + TimeInterval(value.attoseconds) / 1_000_000_000_000_000_000
    }

    static func seconds(_ value: TimeInterval) -> Duration {
        let nanoseconds = max(Int64(value * 1_000_000_000), 0)
        return .nanoseconds(nanoseconds)
    }
}
