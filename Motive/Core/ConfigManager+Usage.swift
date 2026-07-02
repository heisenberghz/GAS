//
//  ConfigManager+Usage.swift
//  Motive
//
//  Thin facade delegating to UsageTracker.
//

import Foundation

extension ConfigManager {
    // Type aliases for backward compatibility
    typealias TokenUsageTotals = UsageTracker.TokenUsageTotals
    typealias TokenUsageEntry = UsageTracker.TokenUsageEntry

    func recordTokenUsage(model: String, usage: TokenUsage, cost: Double?) {
        usageTracker.recordTokenUsage(model: model, usage: usage, cost: cost)
    }

    func resetTokenUsage() {
        usageTracker.resetTokenUsage()
    }

    func tokenUsageEntries() -> [TokenUsageEntry] {
        usageTracker.tokenUsageEntries()
    }
}
