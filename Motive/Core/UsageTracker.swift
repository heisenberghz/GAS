//
//  UsageTracker.swift
//  Motive
//
//  Token usage tracking and persistence.
//  Extracted from ConfigManager+Usage.swift.
//

import Foundation

@MainActor
final class UsageTracker {
    // MARK: - Storage Callbacks

    private let getJSON: () -> String
    private let setJSON: (String) -> Void

    init(getJSON: @escaping () -> String, setJSON: @escaping (String) -> Void) {
        self.getJSON = getJSON
        self.setJSON = setJSON
    }

    // MARK: - Types

    struct TokenUsageTotals: Codable, Sendable, Equatable {
        var input: Int
        var output: Int
        var reasoning: Int
        var cacheRead: Int
        var cacheWrite: Int
        var cost: Double

        var totalTokens: Int {
            input + output + reasoning + cacheRead + cacheWrite
        }
    }

    struct TokenUsageEntry: Identifiable, Sendable, Equatable {
        let id: String
        let model: String
        let totals: TokenUsageTotals

        var displayName: String {
            if let slashIndex = model.lastIndex(of: "/") {
                return String(model[model.index(after: slashIndex)...])
            }
            return model
        }
    }

    // MARK: - Public API

    func recordTokenUsage(model: String, usage: TokenUsage, cost: Double?) {
        var usageMap = loadTokenUsageTotals()
        let normalizedModel = normalizeModelKey(model)
        let existing = usageMap[normalizedModel] ?? TokenUsageTotals(
            input: 0, output: 0, reasoning: 0, cacheRead: 0, cacheWrite: 0, cost: 0
        )
        let updated = TokenUsageTotals(
            input: existing.input + usage.input,
            output: existing.output + usage.output,
            reasoning: existing.reasoning + usage.reasoning,
            cacheRead: existing.cacheRead + usage.cacheRead,
            cacheWrite: existing.cacheWrite + usage.cacheWrite,
            cost: existing.cost + (cost ?? 0)
        )
        usageMap[normalizedModel] = updated
        saveTokenUsageTotals(usageMap)
    }

    func resetTokenUsage() {
        saveTokenUsageTotals([:])
    }

    func tokenUsageEntries() -> [TokenUsageEntry] {
        let map = loadTokenUsageTotals()
        return map.map { key, totals in
            TokenUsageEntry(id: key, model: key, totals: totals)
        }
        .sorted { lhs, rhs in
            if lhs.totals.totalTokens == rhs.totals.totalTokens {
                return lhs.model < rhs.model
            }
            return lhs.totals.totalTokens > rhs.totals.totalTokens
        }
    }

    // MARK: - Private

    private func loadTokenUsageTotals() -> [String: TokenUsageTotals] {
        guard let data = getJSON().data(using: .utf8) else {
            return [:]
        }
        do {
            return try JSONDecoder().decode([String: TokenUsageTotals].self, from: data)
        } catch {
            Log.error("Failed to decode token usage totals: \(error)")
            return [:]
        }
    }

    private func saveTokenUsageTotals(_ totals: [String: TokenUsageTotals]) {
        if let data = try? JSONEncoder().encode(totals),
           let json = String(data: data, encoding: .utf8)
        {
            setJSON(json)
        } else {
            setJSON("{}")
        }
    }

    private func normalizeModelKey(_ model: String) -> String {
        model.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
