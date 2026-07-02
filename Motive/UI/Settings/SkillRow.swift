//
//  SkillRow.swift
//  Motive
//
//  Individual skill row component for Settings UI.
//

import SwiftUI

struct SkillRow: View {
    let status: SkillStatusEntry
    let isBusy: Bool
    let message: SkillsSettingsViewModel.SkillInstallMessage?
    let currentApiKey: String
    let onToggle: (Bool) -> Void
    let onInstall: (SkillInstallOption) -> Void
    let onSaveApiKey: (String) -> Void

    @State private var apiKeyInput: String = ""
    @State private var isEditingKey: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool {
        colorScheme == .dark
    }

    /// Whether this skill needs an API key (has primaryEnv and it's missing)
    private var needsApiKey: Bool {
        guard let primaryEnv = status.entry.metadata?.primaryEnv else { return false }
        return status.missing.env.contains(primaryEnv)
    }

    /// The primary env variable name
    private var primaryEnvName: String? {
        status.entry.metadata?.primaryEnv
    }

    /// Whether the API key is currently configured
    private var hasApiKey: Bool {
        !currentApiKey.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                // Left: Name and description
                VStack(alignment: .leading, spacing: AuroraSpacing.space1) {
                    HStack(spacing: AuroraSpacing.space2) {
                        if let emoji = status.entry.metadata?.emoji {
                            Text(emoji)
                        }
                        Text(status.entry.name)
                            .font(.Aurora.body.weight(.medium))
                            .foregroundColor(Color.Aurora.textPrimary)
                    }

                    Text(status.entry.description)
                        .font(.Aurora.caption)
                        .foregroundColor(Color.Aurora.textMuted)
                        .lineLimit(2)

                    // Status chips
                    HStack(spacing: AuroraSpacing.space2) {
                        StatusChip(text: status.entry.source.rawValue)

                        // Dependency status: Ready (deps OK) or Blocked (missing deps)
                        if status.missing.isEmpty {
                            StatusChip(text: "ready", style: .success)
                        } else {
                            StatusChip(text: "blocked", style: .warning)
                        }

                        // Enabled status
                        if status.disabled {
                            StatusChip(text: "disabled", style: .default)
                        } else {
                            StatusChip(text: "enabled", style: .success)
                        }
                    }

                    // Missing dependencies
                    if !status.missing.bins.isEmpty {
                        Text("Missing: \(status.missing.bins.joined(separator: ", "))")
                            .font(.Aurora.caption)
                            .foregroundColor(Color.Aurora.textMuted)
                    }

                    // Missing env (excluding primaryEnv which gets special treatment)
                    let otherMissingEnv = status.missing.env.filter { $0 != primaryEnvName }
                    if !otherMissingEnv.isEmpty {
                        Text("Missing env: \(otherMissingEnv.joined(separator: ", "))")
                            .font(.Aurora.caption)
                            .foregroundColor(Color.Aurora.textMuted)
                    }
                }

                Spacer()

                // Right: Action buttons
                HStack(spacing: AuroraSpacing.space3) {
                    // Install button - show when there are missing bins and install options exist
                    if !status.missing.bins.isEmpty, !status.installOptions.isEmpty {
                        if let option = status.installOptions.first(where: { $0.available }) {
                            Button {
                                onInstall(option)
                            } label: {
                                HStack(spacing: 4) {
                                    if isBusy {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                            .frame(width: 12, height: 12)
                                    }
                                    Text(isBusy ? "Installing..." : option.label)
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .foregroundColor(Color.Aurora.textPrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: AuroraRadius.sm, style: .continuous)
                                        .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: AuroraRadius.sm, style: .continuous)
                                        .strokeBorder(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.1), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(isBusy)
                        } else {
                            // Show unavailable install options info
                            let firstOption = status.installOptions.first!
                            Text(firstOption.displayLabel)
                                .font(.system(size: 11))
                                .foregroundColor(Color.Aurora.textMuted)
                        }
                    }

                    // Enable/disable toggle - disabled when skill is blocked
                    Toggle("", isOn: Binding(
                        get: { !status.disabled },
                        set: { onToggle($0) }
                    ))
                    .toggleStyle(.switch)
                    .tint(Color.Aurora.accent)
                    .disabled(!status.missing.isEmpty) // Can't enable blocked skills
                }
            }
            .padding(.horizontal, AuroraSpacing.space4)
            .padding(.vertical, AuroraSpacing.space3)

            // API Key input section
            if let envName = primaryEnvName {
                apiKeySection(envName: envName)
            }

            // Install message
            if let message {
                HStack {
                    Image(systemName: message.kind == .success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 12))
                    Text(message.message)
                        .font(.Aurora.caption)
                    Spacer()
                }
                .foregroundColor(message.kind == .success ? Color.Aurora.success : Color.Aurora.error)
                .padding(.horizontal, AuroraSpacing.space4)
                .padding(.bottom, AuroraSpacing.space2)
            }
        }
        .onAppear {
            apiKeyInput = currentApiKey
        }
        .onChange(of: currentApiKey) { _, newValue in
            if !isEditingKey {
                apiKeyInput = newValue
            }
        }
    }

    private func apiKeySection(envName: String) -> some View {
        VStack(alignment: .leading, spacing: AuroraSpacing.space2) {
            HStack(spacing: AuroraSpacing.space2) {
                Text(envName)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(Color.Aurora.textMuted)

                if hasApiKey, !isEditingKey {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Color.Aurora.success)
                }
            }

            HStack(spacing: AuroraSpacing.space2) {
                if isEditingKey || !hasApiKey {
                    SecureField(L10n.Settings.skillsEnterApiKey, text: $apiKeyInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: AuroraRadius.sm, style: .continuous)
                                .fill(isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: AuroraRadius.sm, style: .continuous)
                                .strokeBorder(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.1), lineWidth: 1)
                        )
                        .onSubmit {
                            saveApiKey()
                        }

                    Button {
                        saveApiKey()
                    } label: {
                        Text(L10n.save)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color.Aurora.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: AuroraRadius.sm, style: .continuous)
                                    .fill(Color.Aurora.accent.opacity(0.8))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(apiKeyInput.isEmpty)

                    if isEditingKey {
                        Button {
                            apiKeyInput = currentApiKey
                            isEditingKey = false
                        } label: {
                            Text(L10n.cancel)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color.Aurora.textMuted)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    // Key is configured, show masked value with edit button
                    Text(maskedKey)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(Color.Aurora.textMuted)

                    Spacer()

                    Button {
                        isEditingKey = true
                        apiKeyInput = ""
                    } label: {
                        Text(L10n.edit)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color.Aurora.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, AuroraSpacing.space4)
        .padding(.bottom, AuroraSpacing.space3)
    }

    private var maskedKey: String {
        guard currentApiKey.count > 8 else {
            return String(repeating: "•", count: max(currentApiKey.count, 4))
        }
        let prefix = String(currentApiKey.prefix(4))
        let suffix = String(currentApiKey.suffix(4))
        return "\(prefix)••••••••\(suffix)"
    }

    private func saveApiKey() {
        guard !apiKeyInput.isEmpty else { return }
        onSaveApiKey(apiKeyInput)
        isEditingKey = false
    }
}

// MARK: - Status Chip

private struct StatusChip: View {
    let text: String
    var style: Style = .default

    enum Style {
        case `default`
        case success
        case warning
    }

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .cornerRadius(4)
    }

    private var backgroundColor: Color {
        switch style {
        case .default:
            colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)
        case .success:
            Color.Aurora.success.opacity(0.15)
        case .warning:
            Color.Aurora.warning.opacity(0.15)
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .default:
            Color.Aurora.textMuted
        case .success:
            Color.Aurora.success
        case .warning:
            Color.Aurora.warning
        }
    }
}
