//
//  OnboardingProviderStep.swift
//  Motive
//
//  Aurora Design System - Onboarding Flow
//

import SwiftUI

// MARK: - Aurora AI Provider Step

struct AuroraAIProviderStep: View {
    @EnvironmentObject var configManager: ConfigManager
    let onContinue: () -> Void
    let onSkip: () -> Void

    @State private var apiKey: String = ""
    @State private var baseURL: String = ""
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool {
        colorScheme == .dark
    }

    var body: some View {
        VStack(spacing: AuroraSpacing.space4) {
            // Header
            VStack(spacing: AuroraSpacing.space2) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.Aurora.auroraGradient)

                Text(L10n.Onboarding.aiProviderTitle)
                    .font(.Aurora.title2)
                    .foregroundColor(Color.Aurora.textPrimary)

                Text(L10n.Onboarding.aiProviderSubtitle)
                    .font(.Aurora.bodySmall)
                    .foregroundColor(Color.Aurora.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, AuroraSpacing.space4)

            // Configuration card
            VStack(alignment: .leading, spacing: AuroraSpacing.space3) {
                Text(L10n.Settings.selectProvider)
                    .font(.Aurora.bodySmall.weight(.medium))
                    .foregroundColor(Color.Aurora.textPrimary)

                Picker("", selection: $configManager.providerRawValue) {
                    ForEach(ConfigManager.Provider.allCases) { provider in
                        Text(provider.displayName).tag(provider.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: configManager.providerRawValue) { _, _ in
                    apiKey = ""
                    baseURL = ""
                }

                // API Key input (only for providers that require it)
                if configManager.provider.requiresAPIKey {
                    VStack(alignment: .leading, spacing: AuroraSpacing.space2) {
                        Text(L10n.Settings.apiKey)
                            .font(.Aurora.caption)
                            .foregroundColor(Color.Aurora.textSecondary)

                        SecureInputField(placeholder: configManager.provider.apiKeyPlaceholder, text: $apiKey)
                    }
                }

                // Base URL
                VStack(alignment: .leading, spacing: AuroraSpacing.space2) {
                    Text(configManager.provider == .ollama ? L10n.Settings.ollamaHost : L10n.Settings.baseURL)
                        .font(.Aurora.caption)
                        .foregroundColor(Color.Aurora.textSecondary)

                    StyledTextField(placeholder: configManager.provider.baseURLPlaceholder, text: $baseURL)

                    Text(L10n.Settings.defaultEndpoint)
                        .font(.Aurora.micro)
                        .foregroundColor(Color.Aurora.textMuted)
                }
            }
            .padding(AuroraSpacing.space4)
            .background(Color.Aurora.surface)
            .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                    .stroke(Color.Aurora.border, lineWidth: 1)
            )
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
                .disabled(configManager.provider.requiresAPIKey && apiKey.isEmpty)
            }
            .padding(.horizontal, AuroraSpacing.space10)
            .padding(.bottom, AuroraSpacing.space8)
        }
    }

    private func saveSettings() {
        if !apiKey.isEmpty { configManager.apiKey = apiKey }
        if !baseURL.isEmpty { configManager.baseURL = baseURL }
    }
}
