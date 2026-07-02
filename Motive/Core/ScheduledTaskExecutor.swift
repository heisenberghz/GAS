//
//  ScheduledTaskExecutor.swift
//  Motive
//
//  Created by Codex on 2026/2/16.
//

import Foundation
import SwiftData

actor ScheduledTaskExecutor: ScheduledTaskExecuting {
    @MainActor private weak var appState: AppState?

    init(appState: AppState) {
        self.appState = appState
    }

    func loadTaskSnapshots() async -> [ScheduledTaskSnapshot] {
        await MainActor.run {
            guard let appState, let modelContext = appState.modelContext else { return [] }
            let descriptor = FetchDescriptor<ScheduledTask>(sortBy: [SortDescriptor(\.createdAt, order: .forward)])
            let tasks = (try? modelContext.fetch(descriptor)) ?? []
            let now = Date()
            var snapshots: [ScheduledTaskSnapshot] = []
            var didMutate = false

            for task in tasks where task.isEnabled {
                // IMPORTANT: Keep persisted nextRunAt stable. Do not recompute every scheduler tick,
                // otherwise overdue tasks are continuously pushed into the future and never become due.
                if task.nextRunAt == nil {
                    do {
                        task.nextRunAt = try NextRunCalculator.nextRun(for: task, from: now)
                        task.lastError = nil
                        didMutate = true
                    } catch {
                        task.nextRunAt = nil
                        task.lastError = error.localizedDescription
                        didMutate = true
                        Log.error("Failed to compute initial next run for task \(task.id): \(error.localizedDescription)")
                    }
                }
                snapshots.append(
                    ScheduledTaskSnapshot(
                        id: task.id,
                        nextRunAt: task.nextRunAt,
                        isEnabled: task.isEnabled
                    )
                )
            }

            if didMutate {
                do {
                    try modelContext.save()
                } catch {
                    Log.error("Failed to save scheduled task snapshots: \(error.localizedDescription)")
                }
            }
            return snapshots
        }
    }

    func execute(taskID: UUID) async {
        await MainActor.run {
            guard let appState, let modelContext = appState.modelContext else { return }
            let descriptor = FetchDescriptor<ScheduledTask>(predicate: #Predicate { $0.id == taskID })
            guard let task = (try? modelContext.fetch(descriptor))?.first else { return }
            guard task.isEnabled else { return }

            let startedAt = Date()
            var runStatus: ScheduledTaskRunStatus = .submitted
            var runSessionID: String?
            var runErrorMessage: String?

            do {
                let projectPath: String? = {
                    let trimmed = task.projectPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    return trimmed.isEmpty ? nil : trimmed
                }()
                let agentOverride: String? = {
                    let trimmed = task.agent?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    return trimmed.isEmpty ? nil : trimmed
                }()

                let session = try appState.submitScheduledIntent(
                    task.prompt,
                    workingDirectory: projectPath,
                    agentOverride: agentOverride
                )
                runSessionID = session.id.uuidString
                task.lastRunAt = startedAt
                task.updatedAt = startedAt
                task.lastError = nil
                task.nextRunAt = try NextRunCalculator.nextRun(for: task, from: startedAt)
                if task.nextRunAt == nil, task.scheduleKind == .once {
                    task.isEnabled = false
                }
                Log.session("Scheduled task submitted: \(task.id)")
            } catch {
                runStatus = .failed
                runErrorMessage = error.localizedDescription
                task.lastError = error.localizedDescription
                task.updatedAt = startedAt
                Log.error("Scheduled task execution failed \(task.id): \(error.localizedDescription)")
            }

            let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            modelContext.insert(
                ScheduledTaskRun(
                    taskID: task.id,
                    triggeredAt: startedAt,
                    status: runStatus,
                    sessionID: runSessionID,
                    errorMessage: runErrorMessage,
                    durationMs: durationMs
                )
            )

            do {
                try modelContext.save()
            } catch {
                Log.error("Failed to save scheduled task execution: \(error.localizedDescription)")
            }
        }
    }
}
