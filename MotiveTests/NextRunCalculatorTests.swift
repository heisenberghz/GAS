//
//  NextRunCalculatorTests.swift
//  MotiveTests
//

import Foundation
@testable import Motive
import Testing

struct NextRunCalculatorTests {
    @Test func onceSchedule_returnsNilWhenPast() throws {
        let payload = try ScheduleRuleParser.encode(
            OnceSchedulePayload(runAt: Date().addingTimeInterval(-60))
        )
        let task = ScheduledTask(
            name: "once",
            prompt: "hello",
            scheduleType: .once,
            schedulePayload: payload
        )

        let next = try NextRunCalculator.nextRun(for: task, from: Date())
        #expect(next == nil)
    }

    @Test func intervalSchedule_advancesAfterReference() throws {
        let createdAt = Date().addingTimeInterval(-7200)
        let payload = try ScheduleRuleParser.encode(
            IntervalSchedulePayload(intervalSeconds: 3600)
        )
        let task = ScheduledTask(
            name: "interval",
            prompt: "hello",
            scheduleType: .interval,
            schedulePayload: payload,
            createdAt: createdAt,
            updatedAt: createdAt
        )

        let reference = createdAt.addingTimeInterval(3700)
        let next = try #require(try NextRunCalculator.nextRun(for: task, from: reference))
        #expect(next > reference)
        #expect(abs(next.timeIntervalSince(createdAt.addingTimeInterval(7200))) < 1.0)
    }

    @Test func cronSchedule_parsesStepExpression() throws {
        let payload = try ScheduleRuleParser.encode(
            CronSchedulePayload(expression: "*/5 * * * *")
        )
        let task = ScheduledTask(
            name: "cron",
            prompt: "hello",
            scheduleType: .cron,
            schedulePayload: payload
        )
        let reference = Date(timeIntervalSince1970: 1_700_000_123) // fixed value

        let next = try #require(try NextRunCalculator.nextRun(for: task, from: reference))
        let minute = Calendar.current.component(.minute, from: next)
        #expect(minute % 5 == 0)
        #expect(next > reference)
    }
}
