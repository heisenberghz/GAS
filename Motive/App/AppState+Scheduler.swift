//
//  AppState+Scheduler.swift
//  Motive
//
//  Created by Codex on 2026/2/16.
//

import Foundation

extension AppState {
    func startScheduledTaskSystemIfNeeded() {
        guard taskScheduler == nil else { return }
        let executor = ScheduledTaskExecutor(appState: self)
        let scheduler = TaskScheduler(executor: executor)
        scheduledTaskExecutor = executor
        taskScheduler = scheduler
        Task { await scheduler.start() }
    }

    func refreshScheduledTaskSystem() {
        Task { await taskScheduler?.refresh() }
    }

    func stopScheduledTaskSystem() {
        let scheduler = taskScheduler
        taskScheduler = nil
        scheduledTaskExecutor = nil
        Task { await scheduler?.stop() }
    }

    func runScheduledTaskNow(_ taskID: UUID) {
        Task { await taskScheduler?.runNow(taskID: taskID) }
    }
}
