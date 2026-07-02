//
//  ScheduledTask.swift
//  Motive
//
//  Created by Codex on 2026/2/16.
//

import Foundation
import SwiftData

enum ScheduledTaskScheduleType: String, Codable, CaseIterable, Sendable {
    case once
    case interval
    case daily
    case weekly
    case cron
}

enum ScheduledTaskRunStatus: String, Codable, CaseIterable, Sendable {
    case submitted
    case skipped
    case failed
}

struct OnceSchedulePayload: Codable, Sendable {
    var runAt: Date
}

struct IntervalSchedulePayload: Codable, Sendable {
    /// Seconds between executions. Must be >= 60 in UI validation.
    var intervalSeconds: Int
}

struct DailySchedulePayload: Codable, Sendable {
    var hour: Int
    var minute: Int
}

struct WeeklySchedulePayload: Codable, Sendable {
    /// 1...7 where 1 is Sunday (Calendar weekday).
    var weekday: Int
    var hour: Int
    var minute: Int
}

struct CronSchedulePayload: Codable, Sendable {
    /// Standard 5-field cron expression: m h dom mon dow
    var expression: String
}

@Model
final class ScheduledTask {
    var id: UUID
    var name: String
    var prompt: String
    var scheduleType: String
    var schedulePayload: String
    var timezoneIdentifier: String
    var isEnabled: Bool
    var projectPath: String?
    var agent: String?
    var createdAt: Date
    var updatedAt: Date
    var lastRunAt: Date?
    var nextRunAt: Date?
    var lastError: String?

    var scheduleKind: ScheduledTaskScheduleType {
        get { ScheduledTaskScheduleType(rawValue: scheduleType) ?? .once }
        set { scheduleType = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        name: String,
        prompt: String,
        scheduleType: ScheduledTaskScheduleType,
        schedulePayload: String,
        timezoneIdentifier: String = TimeZone.current.identifier,
        isEnabled: Bool = true,
        projectPath: String? = nil,
        agent: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastRunAt: Date? = nil,
        nextRunAt: Date? = nil,
        lastError: String? = nil
    ) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.scheduleType = scheduleType.rawValue
        self.schedulePayload = schedulePayload
        self.timezoneIdentifier = timezoneIdentifier
        self.isEnabled = isEnabled
        self.projectPath = projectPath
        self.agent = agent
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastRunAt = lastRunAt
        self.nextRunAt = nextRunAt
        self.lastError = lastError
    }
}

@Model
final class ScheduledTaskRun {
    var id: UUID
    var taskID: UUID
    var triggeredAt: Date
    var status: String
    var sessionID: String?
    var errorMessage: String?
    var durationMs: Int?

    var runStatus: ScheduledTaskRunStatus {
        get { ScheduledTaskRunStatus(rawValue: status) ?? .submitted }
        set { status = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        taskID: UUID,
        triggeredAt: Date = Date(),
        status: ScheduledTaskRunStatus,
        sessionID: String? = nil,
        errorMessage: String? = nil,
        durationMs: Int? = nil
    ) {
        self.id = id
        self.taskID = taskID
        self.triggeredAt = triggeredAt
        self.status = status.rawValue
        self.sessionID = sessionID
        self.errorMessage = errorMessage
        self.durationMs = durationMs
    }
}
