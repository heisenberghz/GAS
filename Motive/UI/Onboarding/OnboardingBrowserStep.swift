//
//  OnboardingBrowserStep.swift
//  Motive
//
//  Aurora Design System - Onboarding Flow
//

import SwiftUI

// MARK: - Aurora Browser Step

struct AuroraBrowserStep: View {
    @EnvironmentObject var configManager: ConfigManager
    let onContinue: () -> Void
    let onSkip: () -> Void

    @State private var browserAgentAPIKey: String = ""
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool {
        colorScheme == .dark
    }

    var body: some View {
        VStack(spacing: AuroraSpacing.space4) {
            // Header
            VStack(spacing: AuroraSpacing.space2) {
                Image(systemName: "globe")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.Aurora.auroraGradient)

                Text(L10n.Onboarding.browserTitle)
                    .font(.Aurora.title2)
                    .foregroundColor(Color.Aurora.textPrimary)

                Text(L10n.Onboarding.browserSubtitle)
                    .font(.Aurora.bodySmall)
                    .foregroundColor(Color.Aurora.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AuroraSpacing.space5)
            }
            .padding(.top, AuroraSpacing.space4)

            // Configuration card
            VStack(spacing: 0) {
                // Enable toggle
                OnboardingSettingsRow {
                    HStack {
                        VStack(alignment: .leading, spacing: AuroraSpacing.space1) {
                            Text(L10n.Settings.browserEnable)
                                .font(.Aurora.bodySmall.weight(.medium))
                                .foregroundColor(Color.Aurora.textPrimary)
                            Text(L10n.Onboarding.browserEnableDesc)
                                .font(.Aurora.caption)
                                .foregroundColor(Color.Aurora.textSecondary)
                        }
                        Spacer()
                        Toggle("", isOn: $configManager.browserUseEnabled)
                            .toggleStyle(.switch)
                            .tint(Color.Aurora.primary)
                            .labelsHidden()
                    }
                }

                if configManager.browserUseEnabled {
                    Rectangle().fill(Color.Aurora.border).frame(height: 1).padding(.leading, AuroraSpacing.space4)

                    OnboardingSettingsRow {
                        HStack {
                            VStack(alignment: .leading, spacing: AuroraSpacing.space1) {
                                Text(L10n.Settings.browserShowWindow)
                                    .font(.Aurora.bodySmall.weight(.medium))
                                    .foregroundColor(Color.Aurora.textPrimary)
                                Text(L10n.Settings.browserShowWindowDesc)
                                    .font(.Aurora.caption)
                                    .foregroundColor(Color.Aurora.textSecondary)
                            }
                            Spacer()
                            Toggle("", isOn: $configManager.browserUseHeadedMode)
                                .toggleStyle(.switch)
                                .tint(Color.Aurora.primary)
                                .labelsHidden()
                        }
                    }

                    Rectangle().fill(Color.Aurora.border).frame(height: 1).padding(.leading, AuroraSpacing.space4)

                    OnboardingSettingsRow {
                        HStack {
                            VStack(alignment: .leading, spacing: AuroraSpacing.space1) {
                                Text(L10n.Settings.browserAgentProvider)
                                    .font(.Aurora.bodySmall.weight(.medium))
                                    .foregroundColor(Color.Aurora.textPrimary)
                                Text(L10n.Settings.browserAgentProviderDesc)
                                    .font(.Aurora.caption)
                                    .foregroundColor(Color.Aurora.textSecondary)
                            }
                            Spacer()
                            Picker("", selection: Binding(
                                get: { configManager.browserAgentProvider },
                                set: { newValue in
                                    configManager.browserAgentProvider = newValue
                                    configManager.clearBrowserAgentAPIKeyCache()
                                    browserAgentAPIKey = ""
                                }
                            )) {
                                ForEach(ConfigManager.BrowserAgentProvider.allCases, id: \.self) { provider in
                                    Text(provider.displayName).tag(provider)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 150)
                        }
                    }

                    Rectangle().fill(Color.Aurora.border).frame(height: 1).padding(.leading, AuroraSpacing.space4)

                    OnboardingSettingsRow {
                        HStack {
                            VStack(alignment: .leading, spacing: AuroraSpacing.space1) {
                                Text(configManager.browserAgentProvider.envKeyName)
                                    .font(.Aurora.bodySmall.weight(.medium))
                                    .foregroundColor(Color.Aurora.textPrimary)
                                Text(L10n.Settings.browserApiKeyDesc)
                                    .font(.Aurora.caption)
                                    .foregroundColor(Color.Aurora.textSecondary)
                            }
                            Spacer()
                            SecureInputField(placeholder: "sk-...", text: $browserAgentAPIKey)
                                .frame(width: 160)
                        }
                    }
                }
            }
            .background(Color.Aurora.surface)
            .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                    .stroke(Color.Aurora.border, lineWidth: 1)
            )
            .padding(.horizontal, AuroraSpacing.space10)

            HStack(spacing: AuroraSpacing.space2) {
                Image(systemName: "info.circle")
                    .foregroundColor(Color.Aurora.textMuted)
                Text(L10n.Onboarding.browserInfo)
                    .font(.Aurora.caption)
                    .foregroundColor(Color.Aurora.textMuted)
            }
            .padding(.horizontal, AuroraSpacing.space10)

            Spacer()

            // Buttons
            HStack(spacing: AuroraSpacing.space3) {
                Button(action: onSkip) {
                    Text(L10n.Onboarding.skip)
                        .font(.Aurora.body.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AuroraSpacing.space3)
                }
                .buttonStyle(AuroraOnboardingButtonStyle(style: .secondary))

                Button(action: {
                    saveSettings()
                    onContinue()
                }) {
                    Text(L10n.Onboarding.continueButton)
                        .font(.Aurora.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AuroraSpacing.space3)
                }
                .buttonStyle(AuroraOnboardingButtonStyle(style: .primary))
            }
            .padding(.horizontal, AuroraSpacing.space10)
            .padding(.bottom, AuroraSpacing.space8)
        }
    }

    private func saveSettings() {
        if configManager.browserUseEnabled, !browserAgentAPIKey.isEmpty {
            configManager.browserAgentAPIKey = browserAgentAPIKey
        }
        SkillManager.shared.reloadSkills()
    }
}
