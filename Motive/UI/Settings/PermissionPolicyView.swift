//
//  PermissionPolicyView.swift
//  Motive
//
//  Tool permission settings backed by ToolPermissionPolicy.
//  Displays per-tool categories with pattern-based rules.
//

import SwiftUI

struct PermissionPolicyView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var configManager: ConfigManager
    @State private var configs: [ToolPermission: ToolPermissionConfig] = [:]
    @State private var showAdvanced = false
    @State private var newRuleSheet: NewRuleSheet?

    private var isDark: Bool {
        colorScheme == .dark
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Trust Level selector
            trustLevelSection

            // Primary tools
            toolPermissionsSection(
                title: L10n.Settings.permissions,
                tools: ToolPermission.allCases.filter(\.isPrimary)
            )

            // Advanced tools (collapsible)
            DisclosureGroup(isExpanded: $showAdvanced) {
                toolPermissionsSection(
                    title: nil,
                    tools: ToolPermission.allCases.filter { !$0.isPrimary }
                )
            } label: {
                Text(L10n.Settings.advanced)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.Aurora.textMuted)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }

            // Risk Legend
            riskLegend

            // Reset Button
            HStack {
                Spacer()
                Button(action: {
                    ToolPermissionPolicy.shared.resetToDefaults()
                    loadCurrentConfigs()
                    regenerateConfig()
                }) {
                    Text(L10n.Settings.resetToDefaults)
                        .font(.system(size: 12))
                        .foregroundColor(Color.Aurora.textMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear {
            loadCurrentConfigs()
        }
        .sheet(item: $newRuleSheet) { sheet in
            AddRuleView(tool: sheet.tool) { rule in
                ToolPermissionPolicy.shared.addRule(rule, to: sheet.tool)
                loadCurrentConfigs()
                regenerateConfig()
            }
        }
    }

    // MARK: - Trust Level Section

    private var trustLevelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.Settings.trustLevel)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color.Aurora.textMuted)
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.leading, 4)

            HStack(spacing: 8) {
                ForEach(TrustLevel.allCases, id: \.self) { level in
                    trustLevelCard(level)
                }
            }

            // YOLO warning
            if configManager.trustLevel == .yolo {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Color.Aurora.warning)
                    Text(L10n.Settings.trustAllOps)
                        .font(.system(size: 12))
                        .foregroundColor(Color.Aurora.warning)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.Aurora.warning.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.Aurora.warning.opacity(0.3), lineWidth: SettingsUIStyle.borderWidth)
                )
            }
        }
    }

    private func trustLevelCard(_ level: TrustLevel) -> some View {
        let isSelected = configManager.trustLevel == level

        return Button(action: {
            withAnimation(.auroraFast) {
                configManager.trustLevel = level
                loadCurrentConfigs()
            }
        }) {
            VStack(spacing: 8) {
                Image(systemName: level.systemSymbol)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(isSelected ? .white : Color.Aurora.textSecondary)

                Text(level.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isSelected ? .white : Color.Aurora.textPrimary)

                Text(level.description)
                    .font(.system(size: 10))
                    .foregroundColor(isSelected ? .white.opacity(0.8) : Color.Aurora.textMuted)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(Color.Aurora.auroraGradient) : AnyShapeStyle(Color.Aurora.surface))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isSelected ? Color.clear : SettingsUIStyle.borderColor,
                        lineWidth: SettingsUIStyle.borderWidth
                    )
            )
            .shadow(color: isSelected ? Color.Aurora.accentMid.opacity(0.3) : .clear, radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tool Permissions Section

    private func toolPermissionsSection(title: String?, tools: [ToolPermission]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.Aurora.textMuted)
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .padding(.leading, 4)
            }

            VStack(spacing: 0) {
                ForEach(Array(tools.enumerated()), id: \.element) { index, tool in
                    toolRow(tool)

                    if index < tools.count - 1 {
                        Rectangle()
                            .fill(SettingsUIStyle.dividerColor)
                            .frame(height: SettingsUIStyle.borderWidth)
                            .padding(.leading, 14)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.Aurora.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(SettingsUIStyle.borderColor, lineWidth: SettingsUIStyle.borderWidth)
            )
        }
    }

    private func toolRow(_ tool: ToolPermission) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Tool icon and name
                Image(systemName: tool.systemSymbol)
                    .font(.system(size: 14))
                    .foregroundColor(Color.Aurora.textSecondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(tool.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color.Aurora.textPrimary)

                    Text(tool.localizedDescription)
                        .font(.system(size: 11))
                        .foregroundColor(Color.Aurora.textMuted)
                        .lineLimit(1)
                }

                Spacer()

                // Risk indicator
                Circle()
                    .fill(riskColor(for: tool.riskLevel))
                    .frame(width: 8, height: 8)

                // Default action picker
                Picker("", selection: Binding(
                    get: { configs[tool]?.defaultAction ?? .ask },
                    set: { newAction in
                        ToolPermissionPolicy.shared.setDefaultAction(newAction, for: tool)
                        loadCurrentConfigs()
                        regenerateConfig()
                    }
                )) {
                    ForEach(PermissionAction.allCases, id: \.self) { action in
                        Text(action.displayName).tag(action)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 90)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            // Pattern rules for this tool
            let rules = configs[tool]?.rules ?? []
            if !rules.isEmpty {
                VStack(spacing: 0) {
                    ForEach(rules) { rule in
                        HStack(spacing: 8) {
                            Text(rule.pattern)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(Color.Aurora.textPrimary)

                            if let desc = rule.description {
                                Text(desc)
                                    .font(.system(size: 11))
                                    .foregroundColor(Color.Aurora.textMuted)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Text(rule.action.displayName)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(actionColor(for: rule.action))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(actionColor(for: rule.action).opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 4))

                            Button(action: {
                                ToolPermissionPolicy.shared.removeRule(id: rule.id, from: tool)
                                loadCurrentConfigs()
                                regenerateConfig()
                            }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(Color.Aurora.textMuted)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 46)
                        .padding(.vertical, 4)
                    }
                }
            }

            // Add rule button
            Button(action: {
                newRuleSheet = NewRuleSheet(tool: tool)
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 10))
                    Text(L10n.Settings.addRule)
                        .font(.system(size: 11))
                }
                .foregroundColor(Color.Aurora.textMuted)
            }
            .buttonStyle(.plain)
            .padding(.leading, 46)
            .padding(.vertical, 4)
            .padding(.bottom, 4)
        }
    }

    // MARK: - Risk Legend

    private var riskLegend: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.Settings.riskLevels)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color.Aurora.textMuted)
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.leading, 4)

            HStack(spacing: 20) {
                legendItem(color: .green, label: L10n.Settings.riskLow)
                legendItem(color: .yellow, label: L10n.Settings.riskMedium)
                legendItem(color: .orange, label: L10n.Settings.riskHigh)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.Aurora.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(SettingsUIStyle.borderColor, lineWidth: SettingsUIStyle.borderWidth)
            )
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(Color.Aurora.textSecondary)
        }
    }

    // MARK: - Helpers

    private func loadCurrentConfigs() {
        for tool in ToolPermission.allCases {
            configs[tool] = ToolPermissionPolicy.shared.config(for: tool)
        }
    }

    private func regenerateConfig() {
        configManager.generateOpenCodeConfig()
    }

    private func riskColor(for level: RiskLevel) -> Color {
        switch level {
        case .low: .green
        case .medium: .yellow
        case .high: .orange
        case .critical: .red
        }
    }

    private func actionColor(for action: PermissionAction) -> Color {
        switch action {
        case .allow: .green
        case .ask: .yellow
        case .deny: .red
        }
    }
}

// MARK: - New Rule Sheet

private struct NewRuleSheet: Identifiable {
    let id = UUID()
    let tool: ToolPermission
}

private struct AddRuleView: View {
    let tool: ToolPermission
    let onAdd: (ToolPermissionRule) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pattern = ""
    @State private var action: PermissionAction = .allow
    @State private var description = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(format: L10n.Settings.addRuleFor, tool.displayName))
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.Settings.pattern)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                TextField("e.g., *.ts, git *, /System/**", text: $pattern)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.Settings.action)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Picker(L10n.Settings.action, selection: $action) {
                    ForEach(PermissionAction.allCases, id: \.self) { action in
                        Text(action.displayName).tag(action)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.Settings.descriptionOptional)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                TextField(L10n.Settings.whatRuleDoes, text: $description)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button(L10n.cancel) {
                    dismiss()
                }
                Button(L10n.submit) {
                    let rule = ToolPermissionRule(
                        pattern: pattern,
                        action: action,
                        description: description.isEmpty ? nil : description
                    )
                    onAdd(rule)
                    dismiss()
                }
                .disabled(pattern.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}
