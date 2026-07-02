//
//  UsageSettingsView.swift
//  Motive
//
//  Token usage dashboard.
//

import Charts
import SwiftUI

struct UsageSettingsView: View {
    @EnvironmentObject private var configManager: ConfigManager
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool {
        colorScheme == .dark
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingSection(L10n.Usage.tokenUsage) {
                let entries = configManager.tokenUsageEntries()
                let hasData = entries.contains { $0.totals.totalTokens > 0 }

                VStack(alignment: .leading, spacing: 0) {
                    if entries.isEmpty {
                        Text(L10n.Usage.noData)
                            .font(.Aurora.caption)
                            .foregroundColor(Color.Aurora.textMuted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    } else {
                        // Chart — only if there's actual token data
                        if hasData {
                            Text(L10n.Usage.cumulative)
                                .font(.Aurora.micro)
                                .foregroundColor(Color.Aurora.textMuted)
                                .padding(.horizontal, 16)
                                .padding(.top, 12)
                                .padding(.bottom, 4)

                            usageChart(entries: entries.filter { $0.totals.totalTokens > 0 })
                                .padding(.bottom, 8)
                        }

                        // Model list
                        usageList(entries: entries)
                    }

                    // Footer
                    Rectangle()
                        .fill(Color.Aurora.border.opacity(0.5))
                        .frame(height: 0.5)

                    HStack {
                        Text(L10n.Usage.costReported)
                            .font(.Aurora.micro)
                            .foregroundColor(Color.Aurora.textMuted)
                        Spacer()
                        Button(L10n.Usage.reset) {
                            configManager.resetTokenUsage()
                        }
                        .font(.system(size: 12))
                        .foregroundColor(Color.Aurora.error.opacity(0.8))
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
        }
    }

    private func usageChart(entries: [ConfigManager.TokenUsageEntry]) -> some View {
        let nameCounts = entryNameCounts(entries: entries)
        let barHeight: CGFloat = 28
        let chartHeight = min(280, CGFloat(entries.count) * barHeight + 50)

        return Chart {
            ForEach(entries) { entry in
                let label = displayLabel(for: entry, nameCounts: nameCounts)
                ForEach(TokenUsageCategory.allCases, id: \.self) { category in
                    let value = category.value(from: entry.totals)
                    if value > 0 {
                        BarMark(
                            x: .value("Tokens", value),
                            y: .value("Model", label)
                        )
                        .foregroundStyle(by: .value("Type", category.label))
                        .cornerRadius(3)
                        .annotation(position: .overlay) {
                            // Show value on hover via tooltip
                            Text(TokenUsageFormatter.formatTokens(value))
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(.white)
                                .opacity(value > 100 ? 1 : 0) // hide if bar too thin
                        }
                    }
                }
            }
        }
        .chartForegroundStyleScale(TokenUsageCategory.styleScale)
        .chartLegend(position: .bottom, alignment: .leading, spacing: 6)
        .chartXAxis {
            AxisMarks { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                    .foregroundStyle(Color.Aurora.textMuted.opacity(0.3))
                AxisValueLabel()
                    .font(.system(size: 9))
                    .foregroundStyle(Color.Aurora.textMuted)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisValueLabel()
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.Aurora.textSecondary)
            }
        }
        .frame(height: chartHeight)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func usageList(entries: [ConfigManager.TokenUsageEntry]) -> some View {
        let nameCounts = entryNameCounts(entries: entries)

        return VStack(spacing: 0) {
            ForEach(entries) { entry in
                HStack(spacing: 8) {
                    Text(displayLabel(for: entry, nameCounts: nameCounts))
                        .font(.Aurora.caption.weight(.medium))
                        .foregroundColor(Color.Aurora.textPrimary)
                        .lineLimit(1)

                    Spacer()

                    Text(TokenUsageFormatter.formatTokens(entry.totals.totalTokens))
                        .font(.Aurora.caption)
                        .foregroundColor(Color.Aurora.textSecondary)

                    if entry.totals.cost > 0 {
                        Text(TokenUsageFormatter.formatCost(entry.totals.cost))
                            .font(.Aurora.caption)
                            .foregroundColor(Color.Aurora.textMuted)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                if entry.id != entries.last?.id {
                    Rectangle()
                        .fill(Color.Aurora.border)
                        .frame(height: 1)
                        .padding(.leading, 16)
                }
            }
        }
    }

    private func entryNameCounts(entries: [ConfigManager.TokenUsageEntry]) -> [String: Int] {
        Dictionary(grouping: entries, by: { $0.displayName })
            .mapValues { $0.count }
    }

    private func displayLabel(
        for entry: ConfigManager.TokenUsageEntry,
        nameCounts: [String: Int]
    ) -> String {
        if let count = nameCounts[entry.displayName], count > 1 {
            return entry.model
        }
        return entry.displayName
    }
}

private enum TokenUsageCategory: String, CaseIterable {
    case input
    case output
    case reasoning
    case cacheRead
    case cacheWrite

    var label: String {
        switch self {
        case .input: L10n.Usage.input
        case .output: L10n.Usage.output
        case .reasoning: L10n.Usage.reasoning
        case .cacheRead: L10n.Usage.cacheRead
        case .cacheWrite: L10n.Usage.cacheWrite
        }
    }

    var color: Color {
        switch self {
        case .input: Color(red: 0.30, green: 0.56, blue: 1.0) // Blue
        case .output: Color(red: 0.34, green: 0.80, blue: 0.46) // Green
        case .reasoning: Color(red: 1.0, green: 0.72, blue: 0.25) // Amber
        case .cacheRead: Color(red: 0.68, green: 0.52, blue: 0.98) // Purple
        case .cacheWrite: Color(red: 0.90, green: 0.42, blue: 0.48) // Rose
        }
    }

    static var styleScale: KeyValuePairs<String, Color> {
        KeyValuePairs(
            dictionaryLiteral:
            (L10n.Usage.input, Color(red: 0.30, green: 0.56, blue: 1.0)),
            (L10n.Usage.output, Color(red: 0.34, green: 0.80, blue: 0.46)),
            (L10n.Usage.reasoning, Color(red: 1.0, green: 0.72, blue: 0.25)),
            (L10n.Usage.cacheRead, Color(red: 0.68, green: 0.52, blue: 0.98)),
            (L10n.Usage.cacheWrite, Color(red: 0.90, green: 0.42, blue: 0.48))
        )
    }

    func value(from totals: ConfigManager.TokenUsageTotals) -> Int {
        switch self {
        case .input: totals.input
        case .output: totals.output
        case .reasoning: totals.reasoning
        case .cacheRead: totals.cacheRead
        case .cacheWrite: totals.cacheWrite
        }
    }
}
