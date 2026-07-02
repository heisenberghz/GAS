import Foundation
@testable import Motive
import Testing

@Suite("UsageTracker")
struct UsageTrackerTests {

    @Test @MainActor func recordAndRetrieveUsage() {
        var json = "{}"
        let tracker = UsageTracker(
            getJSON: { json },
            setJSON: { json = $0 }
        )

        let usage = TokenUsage(input: 100, output: 50, reasoning: 10, cacheRead: 20, cacheWrite: 5)
        tracker.recordTokenUsage(model: "test-model", usage: usage, cost: 0.01)

        let entries = tracker.tokenUsageEntries()
        #expect(entries.count == 1)
        #expect(entries[0].model == "test-model")
        #expect(entries[0].totals.input == 100)
        #expect(entries[0].totals.output == 50)
        #expect(entries[0].totals.reasoning == 10)
        #expect(entries[0].totals.cacheRead == 20)
        #expect(entries[0].totals.cacheWrite == 5)
        #expect(entries[0].totals.cost == 0.01)
    }

    @Test @MainActor func accumulateUsageAcrossMultipleCalls() {
        var json = "{}"
        let tracker = UsageTracker(
            getJSON: { json },
            setJSON: { json = $0 }
        )

        let usage1 = TokenUsage(input: 100, output: 50, reasoning: 0, cacheRead: 0, cacheWrite: 0)
        let usage2 = TokenUsage(input: 200, output: 100, reasoning: 0, cacheRead: 0, cacheWrite: 0)
        tracker.recordTokenUsage(model: "model-a", usage: usage1, cost: 0.01)
        tracker.recordTokenUsage(model: "model-a", usage: usage2, cost: 0.02)

        let entries = tracker.tokenUsageEntries()
        #expect(entries.count == 1)
        #expect(entries[0].totals.input == 300)
        #expect(entries[0].totals.output == 150)
        #expect(entries[0].totals.cost == 0.03)
    }

    @Test @MainActor func multipleModelsTrackedSeparately() {
        var json = "{}"
        let tracker = UsageTracker(
            getJSON: { json },
            setJSON: { json = $0 }
        )

        let usage1 = TokenUsage(input: 100, output: 50, reasoning: 0, cacheRead: 0, cacheWrite: 0)
        let usage2 = TokenUsage(input: 200, output: 100, reasoning: 0, cacheRead: 0, cacheWrite: 0)
        tracker.recordTokenUsage(model: "model-a", usage: usage1, cost: nil)
        tracker.recordTokenUsage(model: "model-b", usage: usage2, cost: nil)

        let entries = tracker.tokenUsageEntries()
        #expect(entries.count == 2)
    }

    @Test @MainActor func resetClearsAllUsage() {
        var json = "{}"
        let tracker = UsageTracker(
            getJSON: { json },
            setJSON: { json = $0 }
        )

        let usage = TokenUsage(input: 100, output: 50, reasoning: 0, cacheRead: 0, cacheWrite: 0)
        tracker.recordTokenUsage(model: "model-a", usage: usage, cost: nil)
        tracker.resetTokenUsage()

        let entries = tracker.tokenUsageEntries()
        #expect(entries.isEmpty)
    }

    @Test @MainActor func displayNameExtractsModelAfterSlash() {
        var json = "{}"
        let tracker = UsageTracker(
            getJSON: { json },
            setJSON: { json = $0 }
        )

        let usage = TokenUsage(input: 100, output: 50, reasoning: 0, cacheRead: 0, cacheWrite: 0)
        tracker.recordTokenUsage(model: "anthropic/claude-sonnet", usage: usage, cost: nil)

        let entries = tracker.tokenUsageEntries()
        #expect(entries[0].displayName == "claude-sonnet")
    }

    @Test @MainActor func entriesSortedByTotalTokensDescending() {
        var json = "{}"
        let tracker = UsageTracker(
            getJSON: { json },
            setJSON: { json = $0 }
        )

        let small = TokenUsage(input: 10, output: 5, reasoning: 0, cacheRead: 0, cacheWrite: 0)
        let large = TokenUsage(input: 1000, output: 500, reasoning: 0, cacheRead: 0, cacheWrite: 0)
        tracker.recordTokenUsage(model: "small-model", usage: small, cost: nil)
        tracker.recordTokenUsage(model: "large-model", usage: large, cost: nil)

        let entries = tracker.tokenUsageEntries()
        #expect(entries[0].model == "large-model")
        #expect(entries[1].model == "small-model")
    }
}
