//
//  CommandBarFooter.swift
//  Motive
//
//  Created by geezerrrr on 2026/1/19.
//

import SwiftUI

extension CommandBarView {
    // MARK: - Footer View

    var footerView: some View {
        HStack(spacing: 0) {
            // Left side: status or hints
            leftFooterContent
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(0)

            // Right side: keyboard shortcuts (keep visible)
            rightFooterContent
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
        }
        .frame(height: 38)
        .padding(.horizontal, AuroraSpacing.space6)
        .background(Color.Aurora.glassOverlay.opacity(isDark ? 0.04 : 0.03))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.Aurora.glassOverlay.opacity(isDark ? 0.08 : 0.06))
                .frame(height: 0.5)
        }
    }

    var leftFooterContent: some View {
        HStack(spacing: AuroraSpacing.space3) {
            // Agent indicator
            AgentIndicator()

            // Show current project directory
            HStack(spacing: AuroraSpacing.space2) {
                Image(systemName: "folder")
                    .font(.Aurora.micro.weight(.medium))
                    .foregroundColor(Color.Aurora.textMuted)

                Text(configManager.currentProjectShortPath)
                    .font(.Aurora.micro)
                    .foregroundColor(Color.Aurora.textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, AuroraSpacing.space1)
            .padding(.vertical, AuroraSpacing.space1)
            .onTapGesture {
                // Quick access to /project command
                inputText = "/"
                mode = .command(fromSession: !appState.messages.isEmpty)
                selectedCommandIndex = 0 // /project is first in the list
            }
        }
    }

    @ViewBuilder
    var rightFooterContent: some View {
        if mode.isCommand {
            InlineShortcutHint(items: [
                (L10n.CommandBar.select, "↵"),
                (L10n.CommandBar.complete, "tab"),
                (L10n.CommandBar.navigate, "↑↓"),
                (L10n.CommandBar.back, "esc"),
            ])
        } else if mode.isHistory {
            InlineShortcutHint(items: [
                (L10n.CommandBar.open, "↵"),
                (L10n.CommandBar.delete, "⌘⌫"),
                (L10n.CommandBar.navigate, "↑↓"),
                (L10n.CommandBar.back, "esc"),
            ])
        } else if mode.isProjects {
            InlineShortcutHint(items: [
                (L10n.CommandBar.select, "↵"),
                (L10n.CommandBar.navigate, "↑↓"),
                (L10n.CommandBar.back, "esc"),
            ])
        } else if mode.isModes {
            InlineShortcutHint(items: [
                (L10n.CommandBar.select, "↵"),
                (L10n.CommandBar.navigate, "↑↓"),
                (L10n.CommandBar.back, "esc"),
            ])
        } else {
            switch mode {
            case .idle, .input:
                InlineShortcutHint(items: [
                    (L10n.CommandBar.run, "↵"),
                    (L10n.CommandBar.commands, "/"),
                    (L10n.CommandBar.close, "esc"),
                ])
            case .running:
                InlineShortcutHint(items: [
                    (L10n.CommandBar.close, "esc"),
                ])
            case .completed:
                InlineShortcutHint(items: [
                    (L10n.CommandBar.send, "↵"),
                    (L10n.CommandBar.new, "⌘N"),
                    (L10n.CommandBar.commands, "/"),
                    (L10n.CommandBar.close, "esc"),
                ])
            case .error:
                InlineShortcutHint(items: [
                    (L10n.CommandBar.retry, "↵"),
                    (L10n.CommandBar.commands, "/"),
                    (L10n.CommandBar.close, "esc"),
                ])
            default:
                EmptyView()
            }
        }
    }

    // MARK: - Border Overlay

    var borderOverlay: some View {
        EmptyView() // ConsistentBackground handles the border
    }

    /// Border tint color that adapts to the current mode
    private var borderColor: Color {
        switch mode {
        case .running:
            Color.Aurora.primary.opacity(0.45)
        case .error:
            Color.Aurora.error.opacity(0.5)
        case .command, .history, .projects, .modes:
            Color.Aurora.microAccent.opacity(0.28)
        default:
            Color.Aurora.glassOverlay.opacity(0.08)
        }
    }

    // MARK: - Background

    var commandBarBackground: some View {
        LiquidGlassBackgroundAuto(cornerRadius: AuroraRadius.xl, showBorder: true)
    }
}

// MARK: - Agent Indicator

private struct AgentIndicator: View {
    @EnvironmentObject private var configManager: ConfigManager

    private var agentName: String {
        configManager.currentAgent
    }

    private var displayName: String {
        guard !agentName.isEmpty else { return "Agent" }
        return agentName.prefix(1).uppercased() + String(agentName.dropFirst())
    }

    private var agentIcon: String {
        switch agentName {
        case "plan": "checklist"
        default: "sparkle"
        }
    }

    private var agentColor: Color {
        switch agentName {
        case "plan": Color.Aurora.planAccent
        default: Color.Aurora.textSecondary
        }
    }

    private var agentBackgroundColor: Color {
        switch agentName {
        case "plan":
            Color.Aurora.planAccent.opacity(0.12)
        default:
            Color.Aurora.glassOverlay.opacity(0.06)
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: agentIcon)
                .font(.Aurora.micro.weight(.semibold))
                .frame(width: 10, height: 10)
            Text(displayName)
                .font(.Aurora.micro.weight(.medium))
        }
        .foregroundColor(agentColor)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(agentBackgroundColor)
        )
        .frame(height: 20)
        .help("Current mode: \(displayName) (use /mode to switch)")
    }
}
