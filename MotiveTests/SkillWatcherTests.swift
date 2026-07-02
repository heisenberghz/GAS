import Foundation
@testable import Motive
import Testing

struct SkillWatcherTests {
    @Test func debounceCoalescesEvents() async throws {
        let counter = Counter()
        let watcher = SkillWatcher(debounceMs: 50) { _ in
            counter.increment()
        }

        watcher.notifyChange(changedPath: "a")
        watcher.notifyChange(changedPath: "b")

        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(counter.value == 1)
    }
}

private final class Counter {
    private let lock = NSLock()
    private var _value: Int = 0
    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func increment() {
        lock.lock()
        _value += 1
        lock.unlock()
    }
}
