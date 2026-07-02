//
//  DrawerBadges.swift
//  Motive
//
//  Aurora Design System - Drawer Components
//

import SwiftUI

// MARK: - Session Status Badge

struct SessionStatusBadge: View {
    let status: SessionStatus
    let currentTool: String?
    let isThinking: Bool
    /// Current agent mode (e.g. "plan").
    var agent: String = "agent"

    var body: some View {
        HStack(spacing: AuroraSpacing.space1) {
            statusIcon
                .font(.Aurora.micro.weight(.bold))

            if status == .running, isThinking {
                ShimmerText(text: statusText)
            } else {
                Text(statusText)
                    .font(.Aurora.micro.weight(.semibold))
            }
        }
        .foregroundColor(foregroundColor)
        .padding(.horizontal, AuroraSpacing.space2)
        .padding(.vertical, AuroraSpacing.space1)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.xs, style: .continuous)
                .fill(backgroundColor)
        )
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch status {
        case .idle:
            Image(systemName: "circle")
        case .running:
            Image(systemName: "circle.fill")
        case .completed:
            Image(systemName: "checkmark.circle.fill")
        case .failed:
            Image(systemName: "xmark.circle.fill")
        case .interrupted:
            Image(systemName: "pause.circle.fill")
        }
    }

    private var statusText: String {
        switch status {
        case .idle:
            L10n.StatusBar.idle
        case .running:
            currentTool?.simplifiedToolName ?? L10n.Drawer.running
        case .completed:
            L10n.Drawer.completed
        case .failed:
            L10n.Drawer.failed
        case .interrupted:
            L10n.Drawer.interrupted
        }
    }

    private var foregroundColor: Color {
        switch status {
        case .idle: Color.Aurora.textMuted
        case .running: Color.Aurora.primary
        case .completed: Color.Aurora.success
        case .failed: Color.Aurora.error
        case .interrupted: Color.Aurora.warning
        }
    }

    private var backgroundColor: Color {
        foregroundColor.opacity(0.12)
    }
}

// MARK: - Agent Mode Toggle

/// Compact segmented toggle for switching between Agent and Plan modes.
struct AgentModeToggle: View {
    let currentAgent: String
    let isRunning: Bool
    let onChange: (String) -> Void

    private struct ModeOption: Hashable {
        let value: String
        let label: String
        let icon: String
    }

    private var modeOptions: [ModeOption] {
        var base: [ModeOption] = [
            ModeOption(value: "agent", label: "Agent", icon: "sparkle"),
            ModeOption(value: "plan", label: "Plan", icon: "checklist"),
        ]
        if !base.contains(where: { $0.value == currentAgent }) {
            base.append(
                ModeOption(
                    value: currentAgent,
                    label: modeDisplayName(currentAgent),
                    icon: "circle.hexagongrid.fill"
                )
            )
        }
        return base
    }

    private func isPlanMode(_ value: String) -> Bool {
        value == "plan"
    }

    var body: some View {
        Menu {
            ForEach(modeOptions, id: \.value) { option in
                Button {
                    onChange(option.value)
                } label: {
                    Label(option.label, systemImage: option.icon)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: iconForMode(currentAgent))
                    .font(.Aurora.micro.weight(.semibold))
                    .frame(width: 12, height: 12)
                Text(modeDisplayName(currentAgent))
                    .font(.Aurora.micro.weight(.semibold))
                Image(systemName: "chevron.down")
                    .font(.Aurora.micro.weight(.bold))
                    .foregroundColor(Color.Aurora.textMuted)
            }
            .foregroundColor(activeColor(for: currentAgent))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: AuroraRadius.xs, style: .continuous)
                    .fill(backgroundColor(for: currentAgent))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AuroraRadius.xs, style: .continuous)
                    .stroke(borderColor(for: currentAgent), lineWidth: 0.5)
            )
            .frame(height: 20)
        }
        .menuStyle(.borderlessButton)
        .disabled(isRunning)
        .opacity(isRunning ? 0.5 : 1.0)
    }

    private func iconForMode(_ value: String) -> String {
        switch value {
        case "plan": "checklist"
        case "agent": "sparkle"
        default: "circle.hexagongrid.fill"
        }
    }

    private func modeDisplayName(_ value: String) -> String {
        guard !value.isEmpty else { return "Agent" }
        return value.prefix(1).uppercased() + String(value.dropFirst())
    }

    private func activeColor(for value: String) -> Color {
        isPlanMode(value) ? Color.Aurora.planAccent : Color.Aurora.textSecondary
    }

    private func backgroundColor(for value: String) -> Color {
        isPlanMode(value) ? Color.Aurora.planAccent.opacity(0.12) : Color.Aurora.glassOverlay.opacity(0.06)
    }

    private func borderColor(for value: String) -> Color {
        isPlanMode(value) ? Color.Aurora.planAccent.opacity(0.25) : Color.Aurora.glassOverlay.opacity(0.12)
    }
}

// MARK: - Agent Mode Badge

/// Compact badge showing the current agent mode (e.g. "Plan").
struct AgentModeBadge: View {
    let agent: String

    private var isPlan: Bool {
        agent == "plan"
    }

    private var displayName: String {
        guard !agent.isEmpty else { return "Agent" }
        return agent.prefix(1).uppercased() + String(agent.dropFirst())
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: isPlan ? "checklist" : "sparkle")
                .font(.Aurora.micro.weight(.bold))
                .frame(width: 10, height: 10)
            Text(displayName)
                .font(.Aurora.micro.weight(.semibold))
        }
        .foregroundColor(isPlan ? Color.Aurora.planAccent : Color.Aurora.textSecondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.xs, style: .continuous)
                .fill(
                    isPlan
                        ? Color.Aurora.planAccent.opacity(0.12)
                        : Color.Aurora.glassOverlay.opacity(0.06)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: AuroraRadius.xs, style: .continuous)
                .strokeBorder(
                    isPlan
                        ? Color.Aurora.planAccent.opacity(0.25)
                        : Color.Aurora.glassOverlay.opacity(0.12),
                    lineWidth: 0.5
                )
        )
        .frame(height: 20)
    }
}

// MARK: - Context Size Badge

struct ContextSizeBadge: View {
    let tokens: Int
    private let softCapTokens: Double = 120_000

    private var usageRatio: Double {
        min(max(Double(tokens) / softCapTokens, 0), 1)
    }

    private var fillColor: Color {
        if usageRatio > 0.9 { return Color.Aurora.error }
        if usageRatio > 0.75 { return Color.Aurora.warning }
        return Color.Aurora.primary
    }

    private var formattedTokens: String {
        TokenUsageFormatter.formatTokens(tokens)
    }

    var body: some View {
        HStack(spacing: AuroraSpacing.space2) {
            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color.Aurora.glassOverlay.opacity(0.14))
                    Capsule(style: .continuous)
                        .fill(fillColor)
                        .frame(width: width * usageRatio)
                }
            }
            .frame(width: 52, height: 4)

            Text(formattedTokens)
                .font(.Aurora.micro.weight(.medium))
                .foregroundColor(Color.Aurora.textMuted)
        }
        .padding(.horizontal, AuroraSpacing.space1)
        .padding(.vertical, AuroraSpacing.space0_5)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.xs, style: .continuous)
                .fill(Color.Aurora.glassOverlay.opacity(0.025))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AuroraRadius.xs, style: .continuous)
                .strokeBorder(Color.Aurora.glassOverlay.opacity(0.06), lineWidth: 0.5)
        )
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel("Context tokens \(formattedTokens)")
    }
}
