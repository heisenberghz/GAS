//
//  TokenUsage.swift
//  Motive
//
//  Token usage data structures and formatting helpers.
//

import Foundation

struct TokenUsage: Sendable, Codable, Equatable {
    let input: Int
    let output: Int
    let reasoning: Int
    let cacheRead: Int
    let cacheWrite: Int

    var total: Int {
        input + output + reasoning + cacheRead + cacheWrite
    }
}

enum TokenUsageFormatter {
    static func formatTokens(_ value: Int) -> String {
        if value >= 1_000_000 {
            let formatted = Double(value) / 1_000_000
            return String(format: "%.1fM", formatted)
        }
        if value >= 1000 {
            let formatted = Double(value) / 1000
            return String(format: "%.1fk", formatted)
        }
        return "\(value)"
    }

    static func formatCost(_ value: Double) -> String {
        if value == 0 {
            return "$0"
        }
        if value < 0.01 {
            return String(format: "$%.4f", value)
        }
        if value < 1 {
            return String(format: "$%.3f", value)
        }
        return String(format: "$%.2f", value)
    }
}
