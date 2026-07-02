//
//  SkillDetailView.swift
//  Motive
//
//  Skill detail panel view
//

import MarkdownUI
import SwiftUI

// MARK: - Skill Detail

struct SkillDetail: View {
    let status: SkillStatusEntry
    let markdownContent: String
    let markdownError: String?
    let isMarkdownLoading: Bool
    let isBusy: Bool
    let installMessage: SkillsSettingsViewModel.SkillInstallMessage?
    let currentApiKey: String
    let onToggle: (Bool) -> Void
    let onInstall: (SkillInstallOption) -> Void
    let onSaveApiKey: (String) -> Void

    @State private var apiKeyInput: String = ""
    @State private var isEditingKey: Bool = false
    @State private var showApiKey: Bool = false

    private var primaryEnvName: String? {
        status.entry.metadata?.primaryEnv
    }

    private var hasApiKey: Bool {
        !currentApiKey.isEmpty
    }

    /// Dependency status: Blocked (missing deps) or Ready (deps satisfied)
    private var isReady: Bool {
        status.missing.isEmpty
    }

    @ViewBuilder
    private var statusBadge: some View {
        // Show dependency status: Blocked or Ready
        let text = isReady ? "Ready" : "Blocked"
        let color = isReady ? Color.Aurora.success : Color.Aurora.warning

        Text(text)
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(color.opacity(0.15))
            )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                headerSection

                // Missing deps warning
                if !status.missing.isEmpty {
                    missingSection
                }

                // API Key input
                if let envName = primaryEnvName {
                    apiKeySection(envName: envName)
                }

                // Install options
                if !status.installOptions.isEmpty, !status.missing.bins.isEmpty {
                    installSection
                }

                // Markdown content
                markdownSection
            }
            .padding(20)
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

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Top row: emoji, name, badges
            HStack(spacing: 12) {
                // Emoji/icon
                Group {
                    if let emoji = status.entry.metadata?.emoji {
                        Text(emoji)
                            .font(.system(size: 32))
                    } else {
                        Image(systemName: "sparkle")
                            .font(.system(size: 24))
                            .foregroundStyle(Color.Aurora.auroraGradient)
                    }
                }

                // Name and badges
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(status.entry.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.Aurora.textPrimary)

                        // Status badge - distinguish between Disabled, Blocked, and Ready
                        statusBadge

                        // Source badge
                        Text(status.entry.source.rawValue)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(Color.Aurora.textMuted)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.Aurora.surfaceElevated)
                            )
                    }
                }

                Spacer()
            }

            // Description - full width
            Text(status.entry.description)
                .font(.system(size: 13))
                .foregroundColor(Color.Aurora.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var missingSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.Settings.skillsMissingReqs)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Color.Aurora.warning)

            if !status.missing.bins.isEmpty {
                Text("binaries: \(status.missing.bins.joined(separator: ", "))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Color.Aurora.textSecondary)
            }

            let otherMissingEnv = status.missing.env.filter { $0 != primaryEnvName }
            if !otherMissingEnv.isEmpty {
                Text("env: \(otherMissingEnv.joined(separator: ", "))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Color.Aurora.textSecondary)
            }

            if !status.missing.config.isEmpty {
                Text("config: \(status.missing.config.joined(separator: ", "))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Color.Aurora.textSecondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.Aurora.warning.opacity(0.08))
        )
    }

    private func apiKeySection(envName: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(envName)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(Color.Aurora.textMuted)

                if hasApiKey, !isEditingKey {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Color.Aurora.success)
                }
            }

            if isEditingKey || !hasApiKey {
                HStack(spacing: 8) {
                    // API Key field with eye toggle inside
                    ZStack(alignment: .trailing) {
                        Group {
                            if showApiKey {
                                TextField(L10n.Settings.skillsEnterApiKey, text: $apiKeyInput)
                            } else {
                                SecureField(L10n.Settings.skillsEnterApiKey, text: $apiKeyInput)
                            }
                        }
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, design: .monospaced))
                        .padding(.leading, 10)
                        .padding(.trailing, 30)
                        .padding(.vertical, 6)
                        .onSubmit { saveApiKey() }

                        Button {
                            showApiKey.toggle()
                        } label: {
                            Image(systemName: showApiKey ? "eye.slash" : "eye")
                                .font(.system(size: 10))
                                .foregroundColor(Color.Aurora.textMuted)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 8)
                    }
                    .settingsInputField(cornerRadius: 4)

                    Button {
                        saveApiKey()
                    } label: {
                        Text(L10n.save)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.Aurora.primary)
                    .disabled(apiKeyInput.isEmpty)

                    if isEditingKey {
                        Button {
                            apiKeyInput = currentApiKey
                            isEditingKey = false
                            showApiKey = false
                        } label: {
                            Text(L10n.cancel)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(Color.Aurora.textMuted)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            } else {
                HStack {
                    Text(maskedKey)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color.Aurora.textMuted)

                    Spacer()

                    Button {
                        isEditingKey = true
                        apiKeyInput = ""
                    } label: {
                        Text(L10n.edit)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color.Aurora.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.Aurora.surface)
        )
    }

    private var installSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.install)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Color.Aurora.textMuted)

            HStack(spacing: 8) {
                ForEach(status.installOptions, id: \.id) { option in
                    Button {
                        onInstall(option)
                    } label: {
                        HStack(spacing: 4) {
                            if isBusy {
                                ProgressView()
                                    .scaleEffect(0.5)
                                    .frame(width: 10, height: 10)
                            } else {
                                Image(systemName: iconName(for: option.kind))
                                    .font(.system(size: 10))
                            }

                            Text(option.label)
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(option.available ? Color.Aurora.textPrimary : Color.Aurora.textMuted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.Aurora.surface)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!option.available || isBusy)
                }
            }

            if let installMessage {
                HStack(spacing: 4) {
                    Image(systemName: installMessage.kind == .success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 10))
                    Text(installMessage.message)
                        .font(.system(size: 10))
                }
                .foregroundColor(installMessage.kind == .success ? Color.Aurora.success : Color.Aurora.error)
            }
        }
    }

    private var markdownSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title row with Toggle
            HStack {
                Text(L10n.Settings.skillsGuide)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color.Aurora.textMuted)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Spacer()

                // Toggle moved here - disabled when skill is blocked
                HStack(spacing: 8) {
                    if !isReady {
                        Text(L10n.Settings.skillsBlocked)
                            .font(.system(size: 11))
                            .foregroundColor(Color.Aurora.warning)
                    } else {
                        Text(status.disabled ? L10n.Settings.skillsDisabled : L10n.Settings.skillsEnabled)
                            .font(.system(size: 11))
                            .foregroundColor(status.disabled ? Color.Aurora.textMuted : Color.Aurora.success)
                    }

                    Toggle("", isOn: Binding(
                        get: { !status.disabled },
                        set: { onToggle($0) }
                    ))
                    .toggleStyle(.switch)
                    .tint(Color.Aurora.primary)
                    .controlSize(.small)
                    .disabled(!isReady) // Can't enable blocked skills
                }
            }

            Group {
                if isMarkdownLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text(L10n.loading)
                            .font(.system(size: 11))
                            .foregroundColor(Color.Aurora.textMuted)
                    }
                    .padding(.vertical, 16)
                } else if let markdownError {
                    Text(markdownError)
                        .font(.system(size: 11))
                        .foregroundColor(Color.Aurora.error)
                        .padding(.vertical, 8)
                } else {
                    Markdown(markdownContent)
                        .markdownTextStyle {
                            FontSize(13)
                            ForegroundColor(Color.Aurora.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.Aurora.surface)
            )
        }
    }

    private var maskedKey: String {
        guard currentApiKey.count > 8 else {
            return String(repeating: "\u{2022}", count: max(currentApiKey.count, 4))
        }
        let prefix = String(currentApiKey.prefix(4))
        let suffix = String(currentApiKey.suffix(4))
        return "\(prefix)\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\(suffix)"
    }

    private func saveApiKey() {
        guard !apiKeyInput.isEmpty else { return }
        onSaveApiKey(apiKeyInput)
        isEditingKey = false
    }

    private func iconName(for kind: InstallKind) -> String {
        switch kind {
        case .brew: "cup.and.saucer.fill"
        case .node: "shippingbox.fill"
        case .go: "chevron.left.forwardslash.chevron.right"
        case .uv: "puzzlepiece.fill"
        case .apt: "square.and.arrow.down.fill"
        case .download: "arrow.down.circle.fill"
        }
    }
}
