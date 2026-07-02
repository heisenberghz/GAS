//
//  ScheduleRuleParser.swift
//  Motive
//
//  Created by Codex on 2026/2/16.
//

import Foundation

enum ScheduleRuleError: LocalizedError {
    case invalidType
    case invalidPayload
    case invalidTimezone
    case invalidCron(String)

    var errorDescription: String? {
        switch self {
        case .invalidType:
            "Invalid schedule type"
        case .invalidPayload:
            "Invalid schedule payload"
        case .invalidTimezone:
            "Invalid timezone"
        case let .invalidCron(reason):
            "Invalid cron expression: \(reason)"
        }
    }
}

enum ScheduleRule: Sendable {
    case once(OnceSchedulePayload)
    case interval(IntervalSchedulePayload)
    case daily(DailySchedulePayload)
    case weekly(WeeklySchedulePayload)
    case cron(CronSchedulePayload)
}

enum ScheduleRuleParser {
    static func parse(task: ScheduledTask) throws -> ScheduleRule {
        switch task.scheduleKind {
        case .once:
            try .once(decode(task.schedulePayload, as: OnceSchedulePayload.self))
        case .interval:
            try .interval(decode(task.schedulePayload, as: IntervalSchedulePayload.self))
        case .daily:
            try .daily(decode(task.schedulePayload, as: DailySchedulePayload.self))
        case .weekly:
            try .weekly(decode(task.schedulePayload, as: WeeklySchedulePayload.self))
        case .cron:
            try .cron(decode(task.schedulePayload, as: CronSchedulePayload.self))
        }
    }

    static func encode(_ payload: some Encodable) throws -> String {
        let data = try JSONEncoder().encode(payload)
        return String(decoding: data, as: UTF8.self)
    }

    static func decode<T: Decodable>(_ raw: String, as type: T.Type) throws -> T {
        guard let data = raw.data(using: .utf8) else { throw ScheduleRuleError.invalidPayload }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw ScheduleRuleError.invalidPayload
        }
    }
}

enum NextRunCalculator {
    private static let searchHorizonMinutes = 366 * 24 * 60

    static func nextRun(for task: ScheduledTask, from referenceDate: Date = Date()) throws -> Date? {
        let timezone = TimeZone(identifier: task.timezoneIdentifier) ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        let rule = try ScheduleRuleParser.parse(task: task)

        switch rule {
        case let .once(payload):
            return payload.runAt > referenceDate ? payload.runAt : nil
        case let .interval(payload):
            guard payload.intervalSeconds > 0 else { throw ScheduleRuleError.invalidPayload }
            let base = task.lastRunAt ?? task.createdAt
            if base > referenceDate {
                return base
            }
            let elapsed = referenceDate.timeIntervalSince(base)
            let interval = TimeInterval(payload.intervalSeconds)
            let cycles = Int(elapsed / interval) + 1
            return base.addingTimeInterval(Double(cycles) * interval)
        case let .daily(payload):
            guard (0 ... 23).contains(payload.hour), (0 ... 59).contains(payload.minute) else {
                throw ScheduleRuleError.invalidPayload
            }
            return nextDaily(calendar: calendar, from: referenceDate, hour: payload.hour, minute: payload.minute)
        case let .weekly(payload):
            guard (1 ... 7).contains(payload.weekday),
                  (0 ... 23).contains(payload.hour),
                  (0 ... 59).contains(payload.minute)
            else {
                throw ScheduleRuleError.invalidPayload
            }
            return nextWeekly(
                calendar: calendar,
                from: referenceDate,
                weekday: payload.weekday,
                hour: payload.hour,
                minute: payload.minute
            )
        case let .cron(payload):
            let cron = try CronExpression(expression: payload.expression)
            return nextCronDate(cron: cron, calendar: calendar, from: referenceDate)
        }
    }

    private static func nextDaily(calendar: Calendar, from referenceDate: Date, hour: Int, minute: Int) -> Date? {
        let start = calendar.date(byAdding: .minute, value: 1, to: referenceDate) ?? referenceDate
        var components = calendar.dateComponents([.year, .month, .day], from: start)
        components.hour = hour
        components.minute = minute
        components.second = 0
        let todayCandidate = calendar.date(from: components)
        if let todayCandidate, todayCandidate >= start {
            return todayCandidate
        }
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        var tomorrowComponents = calendar.dateComponents([.year, .month, .day], from: tomorrow)
        tomorrowComponents.hour = hour
        tomorrowComponents.minute = minute
        tomorrowComponents.second = 0
        return calendar.date(from: tomorrowComponents)
    }

    private static func nextWeekly(
        calendar: Calendar,
        from referenceDate: Date,
        weekday: Int,
        hour: Int,
        minute: Int
    ) -> Date? {
        let start = calendar.date(byAdding: .minute, value: 1, to: referenceDate) ?? referenceDate
        for offset in 0 ... 14 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            if calendar.component(.weekday, from: day) != weekday {
                continue
            }
            var components = calendar.dateComponents([.year, .month, .day], from: day)
            components.hour = hour
            components.minute = minute
            components.second = 0
            if let candidate = calendar.date(from: components), candidate >= start {
                return candidate
            }
        }
        return nil
    }

    private static func nextCronDate(cron: CronExpression, calendar: Calendar, from referenceDate: Date) -> Date? {
        var current = referenceDate
        for _ in 0 ..< searchHorizonMinutes {
            guard let candidate = calendar.date(byAdding: .minute, value: 1, to: current) else { return nil }
            current = candidate
            if cron.matches(date: candidate, calendar: calendar) {
                return candidate
            }
        }
        return nil
    }
}

private struct CronExpression: Sendable {
    private let minuteField: CronField
    private let hourField: CronField
    private let dayField: CronField
    private let monthField: CronField
    private let weekdayField: CronField
    private let dayIsWildcard: Bool
    private let weekdayIsWildcard: Bool

    init(expression: String) throws {
        let parts = expression
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
        guard parts.count == 5 else {
            throw ScheduleRuleError.invalidCron("Expected 5 fields")
        }
        minuteField = try CronField(token: parts[0], min: 0, max: 59)
        hourField = try CronField(token: parts[1], min: 0, max: 23)
        dayField = try CronField(token: parts[2], min: 1, max: 31)
        monthField = try CronField(token: parts[3], min: 1, max: 12)
        weekdayField = try CronField(token: parts[4], min: 0, max: 7, map: { $0 == 7 ? 0 : $0 })
        dayIsWildcard = parts[2] == "*"
        weekdayIsWildcard = parts[4] == "*"
    }

    func matches(date: Date, calendar: Calendar) -> Bool {
        let minute = calendar.component(.minute, from: date)
        let hour = calendar.component(.hour, from: date)
        let day = calendar.component(.day, from: date)
        let month = calendar.component(.month, from: date)
        let weekday = calendar.component(.weekday, from: date) - 1 // Sunday -> 0

        guard minuteField.matches(minute),
              hourField.matches(hour),
              monthField.matches(month)
        else {
            return false
        }

        let dayMatches = dayField.matches(day)
        let weekdayMatches = weekdayField.matches(weekday)
        if !dayIsWildcard, !weekdayIsWildcard {
            return dayMatches || weekdayMatches
        }
        return dayMatches && weekdayMatches
    }
}

private struct CronField: Sendable {
    private let values: Set<Int>

    init(
        token: String,
        min: Int,
        max: Int,
        map: (Int) -> Int = { $0 }
    ) throws {
        if token == "*" {
            values = Set((min ... max).map(map))
            return
        }

        var result = Set<Int>()
        for segment in token.split(separator: ",") {
            let part = String(segment)
            if part.hasPrefix("*/") {
                let stepPart = String(part.dropFirst(2))
                guard let step = Int(stepPart), step > 0 else {
                    throw ScheduleRuleError.invalidCron("Invalid step '\(part)'")
                }
                var value = min
                while value <= max {
                    result.insert(map(value))
                    value += step
                }
                continue
            }

            if part.contains("-") {
                let bounds = part.split(separator: "-").map(String.init)
                guard bounds.count == 2,
                      let start = Int(bounds[0]),
                      let end = Int(bounds[1]),
                      start <= end
                else {
                    throw ScheduleRuleError.invalidCron("Invalid range '\(part)'")
                }
                guard (min ... max).contains(start), (min ... max).contains(end) else {
                    throw ScheduleRuleError.invalidCron("Out of range '\(part)'")
                }
                for value in start ... end {
                    result.insert(map(value))
                }
                continue
            }

            guard let value = Int(part), (min ... max).contains(value) else {
                throw ScheduleRuleError.invalidCron("Invalid value '\(part)'")
            }
            result.insert(map(value))
        }

        guard !result.isEmpty else {
            throw ScheduleRuleError.invalidCron("Empty field '\(token)'")
        }
        values = result
    }

    func matches(_ value: Int) -> Bool {
        values.contains(value)
    }
}
