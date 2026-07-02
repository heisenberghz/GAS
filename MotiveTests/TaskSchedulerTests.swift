//
//  TaskSchedulerTests.swift
//  MotiveTests
//

import Foundation
@testable import Motive
import Testing

struct TaskSchedulerTests {
    @Test func scheduler_executesDueTask() async {
        let dueID = UUID()
        let fakeExecutor = FakeScheduledTaskExecutor(
            snapshots: [ScheduledTaskSnapshot(id: dueID, nextRunAt: Date().addingTimeInterval(-1), isEnabled: true)]
        )
        let scheduler = TaskScheduler(
            executor: fakeExecutor,
            idlePollInterval: .milliseconds(30),
            maxSleepChunk: .milliseconds(30)
        )

        await scheduler.start()
        try? await Task.sleep(for: .milliseconds(180))
        await scheduler.stop()

        let executed = await fakeExecutor.executedTaskIDs
        #expect(executed.contains(dueID))
    }

    @Test func scheduler_runNow_executesImmediately() async {
        let taskID = UUID()
        let fakeExecutor = FakeScheduledTaskExecutor(snapshots: [])
        let scheduler = TaskScheduler(
            executor: fakeExecutor,
            idlePollInterval: .milliseconds(30),
            maxSleepChunk: .milliseconds(30)
        )

        await scheduler.start()
        await scheduler.runNow(taskID: taskID)
        try? await Task.sleep(for: .milliseconds(100))
        await scheduler.stop()

        let executed = await fakeExecutor.executedTaskIDs
        #expect(executed.contains(taskID))
    }
}

private actor FakeScheduledTaskExecutor: ScheduledTaskExecuting {
    private let snapshots: [ScheduledTaskSnapshot]
    private(set) var executedTaskIDs: [UUID] = []

    init(snapshots: [ScheduledTaskSnapshot]) {
        self.snapshots = snapshots
    }

    func loadTaskSnapshots() async -> [ScheduledTaskSnapshot] {
        snapshots
    }

    func execute(taskID: UUID) async {
        executedTaskIDs.append(taskID)
    }
}
