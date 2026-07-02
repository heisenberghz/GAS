//
//  ModelConfigView.swift
//  Motive
//
//  Compact Model Configuration
//

import SwiftUI

struct ModelConfigView: View {
    @EnvironmentObject private var configManager: ConfigManager
    @EnvironmentObject private var appState: AppState

    @State private var showSavedFeedback = false
    @State private var showAPIKey = false
    @FocusState private var focusedField: Field?

    enum Field: Hashable {
        case baseURL, apiKey, modelName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Provider Selection
            VStack(alignment: .leading, spacing: 10) {
                // Header with warning badge - fixed height to prevent layout shift
                HStack(spacing: 8) {
                    Text(L10n.Settings.provider)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color.Aurora.textMuted)
                        .textCase(.uppercase)
                        .tracking(0.5)

                    Spacer()

                    // Warning badge - always reserve space
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Color.Aurora.warning)

                        Text(configManager.providerConfigurationError ?? "")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color.Aurora.warning)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.Aurora.warning.opacity(0.12))
                    )
                    .opacity(configManager.providerConfigurationError != nil ? 1 : 0)
                }
                .frame(height: 28)
                .padding(.leading, 4)

                // Compact provider picker
                providerPicker
            }

            // Configuration
            SettingSection(L10n.Settings.configuration) {
                // API Key / Token field.
                // Show for: (a) providers that require a key, (b) providers with optional key (LM Studio/Ollama),
                // and (c) any provider with a custom base URL (OpenAI-compatible mode may require server auth).
                if configManager.provider.requiresAPIKey || configManager.provider.allowsOptionalAPIKey || !configManager.baseURL.isEmpty {
                    SettingRow(
                        apiKeyFieldLabel,
                        description: apiKeyFieldDescription
                    ) {
                        // API Key field with visibility toggle
                        ZStack(alignment: .trailing) {
                            HStack(spacing: 8) {
                                // Checkmark on the left when key is configured
                                if configManager.hasAPIKey {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(Color.Aurora.success)
                                }

                                Group {
                                    if showAPIKey {
                                        TextField(apiKeyPlaceholder, text: Binding(
                                            get: { configManager.apiKey },
                                            set: { configManager.apiKey = $0 }
                                        ))
                                    } else {
                                        SecureField(apiKeyPlaceholder, text: Binding(
                                            get: { configManager.apiKey },
                                            set: { configManager.apiKey = $0 }
                                        ))
                                    }
                                }
                                .textFieldStyle(.plain)
                                .font(.system(size: 13, design: .monospaced))
                            }
                            .padding(.leading, 12)
                            .padding(.trailing, 32)
                            .padding(.vertical, 8)

                            // Eye toggle button
                            Button {
                                showAPIKey.toggle()
                            } label: {
                                Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color.Aurora.textMuted)
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 10)
                        }
                        .frame(width: 220)
                        .settingsInputField(
                            cornerRadius: 6,
                            borderColor: configManager.hasAPIKey ? Color.Aurora.success.opacity(0.5) : nil
                        )
                    }
                }

                // Base URL (stored in Keychain alongside API key)
                SettingRow(configManager.provider == .ollama ? L10n.Settings.ollamaHost : L10n.Settings.baseURL) {
                    TextField(baseURLPlaceholder, text: Binding(
                        get: { configManager.baseURL },
                        set: { configManager.baseURL = $0 }
                    ))
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(width: 220)
                    .settingsInputField(cornerRadius: 6)
                }

                // Model Name
                SettingRow(L10n.Settings.model, showDivider: false) {
                    TextField(modelPlaceholder, text: $configManager.modelName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(width: 220)
                        .settingsInputField(cornerRadius: 6)
                }
            }

            // Action Bar (no Spacer - keep content compact)
            HStack {
                Spacer()

                if showSavedFeedback {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(Color.Aurora.success)
                        Text(L10n.Settings.agentRestarted)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color.Aurora.textSecondary)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }

                Button(action: saveAndRestart) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                        Text(L10n.Settings.saveRestart)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.Aurora.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.auroraFast, value: showSavedFeedback)
    }

    // MARK: - Provider Picker

    private var providerPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ConfigManager.Provider.allCases) { provider in
                    CompactProviderCard(
                        provider: provider,
                        isSelected: configManager.provider == provider
                    ) {
                        withAnimation(.auroraFast) {
                            configManager.provider = provider
                        }
                    }
                }
            }
            .padding(12)
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.Aurora.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(SettingsUIStyle.borderColor, lineWidth: SettingsUIStyle.borderWidth)
        )
    }

    private var modelPlaceholder: String {
        configManager.provider.defaultModel
    }

    private var apiKeyPlaceholder: String {
        configManager.provider.apiKeyPlaceholder
    }

    private var baseURLPlaceholder: String {
        configManager.provider.baseURLPlaceholder
    }

    // MARK: - API Key Field Helpers

    /// Label for the API key/token field, contextual to provider and base URL
    private var apiKeyFieldLabel: String {
        if configManager.provider.allowsOptionalAPIKey {
            return "API Token (Optional)"
        }
        // Standard provider used with a custom (OpenAI-compatible) endpoint
        if !configManager.baseURL.isEmpty {
            return "API Token"
        }
        return L10n.Settings.apiKey
    }

    /// Description for the API key/token field
    private var apiKeyFieldDescription: String? {
        if configManager.provider.allowsOptionalAPIKey {
            return "Required for remote servers with auth enabled (e.g. LM Studio with authentication)"
        }
        // Standard provider using custom base URL
        if !configManager.baseURL.isEmpty {
            return "Required if the custom endpoint has authentication enabled"
        }
        return nil
    }

    private func saveAndRestart() {
        appState.restartAgent()
        showSavedFeedback = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            withAnimation {
                showSavedFeedback = false
            }
        }
    }
}

// MARK: - Compact Provider Card

private struct CompactProviderCard: View {
    let provider: ConfigManager.Provider
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool {
        colorScheme == .dark
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                // Provider icon (custom asset or SF Symbol)
                providerIcon
                    .frame(width: 22, height: 22)
                    .foregroundColor(isSelected ? Color.Aurora.primary : Color.Aurora.textSecondary)

                Text(provider.displayName)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? Color.Aurora.textPrimary : Color.Aurora.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: 70)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isSelected ? Color.Aurora.primary.opacity(0.5) : Color.clear,
                        lineWidth: SettingsUIStyle.borderWidth
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    @ViewBuilder
    private var providerIcon: some View {
        if provider.usesCustomIcon {
            Image(provider.iconAsset)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: provider.sfSymbol)
                .font(.system(size: 18, weight: .medium))
        }
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.Aurora.primary.opacity(isDark ? 0.12 : 0.08)
        } else if isHovering {
            return isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.03)
        }
        return Color.clear
    }
}

// MARK: - Legacy Components (kept for compatibility)

struct AuroraProviderCard: View {
    let provider: ConfigManager.Provider
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        CompactProviderCard(provider: provider, isSelected: isSelected, action: action)
    }
}

struct ProviderCard: View {
    let provider: ConfigManager.Provider
    let isSelected: Bool
    var isDark: Bool = true
    let action: () -> Void

    var body: some View {
        CompactProviderCard(provider: provider, isSelected: isSelected, action: action)
    }
}

struct SettingsTextField: View {
    let placeholder: String
    @Binding var text: String
    var isFocused: Bool = false
    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 12, design: .monospaced))
            .foregroundColor(Color.Aurora.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .settingsInputField(
                cornerRadius: 5,
                borderColor: isFocused ? Color.Aurora.primary : nil
            )
    }
}

struct SettingsSecureField: View {
    let placeholder: String
    @Binding var text: String
    var isFocused: Bool = false
    var body: some View {
        SecureField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 12, design: .monospaced))
            .foregroundColor(Color.Aurora.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .settingsInputField(
                cornerRadius: 5,
                borderColor: isFocused ? Color.Aurora.primary : nil
            )
    }
}

/// Legacy compatibility
struct AuroraModernTextFieldStyle: TextFieldStyle {
    var isFocused: Bool = false
    func _body(configuration: TextField<_Label>) -> some View {
        configuration
    }
}

struct ModernTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<_Label>) -> some View {
        configuration
    }
}

// MARK: - Provider Extension

extension ConfigManager.Provider {
    /// Asset Catalog icon name (all providers have custom icons in `icons/`)
    var iconAsset: String {
        switch self {
        case .claude: "anthropic"
        case .openai: "open-ai"
        case .gemini: "gemini-ai"
        case .ollama: "ollama"
        case .openrouter: "openrouter"
        case .mistral: "Mistral"
        case .groq: "Groq"
        case .xai: "xai"
        case .cohere: "cohere"
        case .deepinfra: "deepinfra"
        case .deepseek: "deepseek"
        case .minimax: "MiniMax"
        case .alibaba: "Qwen"
        case .moonshotai: "moonshot"
        case .zhipuai: "zhipu"
        case .perplexity: "perplexity"
        case .bedrock: "bedrock"
        case .lmstudio: "lmstudio"
        }
    }

    /// SF Symbol fallback (unused — all providers have custom icons)
    var sfSymbol: String {
        ""
    }

    /// Whether this provider uses a custom asset or SF Symbol
    var usesCustomIcon: Bool {
        true
    }

    /// API key placeholder text
    var apiKeyPlaceholder: String {
        switch self {
        case .claude: "sk-ant-..."
        case .openai: "sk-..."
        case .gemini: "AIza..."
        case .ollama: ""
        case .lmstudio: "lm-studio-token..."
        case .openrouter: "sk-or-..."
        case .mistral: "..."
        case .groq: "gsk_..."
        case .xai: "xai-..."
        case .cohere: "..."
        case .deepinfra: "..."
        case .deepseek: "sk-..."
        case .minimax: "..."
        case .alibaba: "sk-..."
        case .moonshotai: "sk-..."
        case .zhipuai: "..."
        case .perplexity: "pplx-..."
        case .bedrock: "AKIA..."
        }
    }

    /// Base URL placeholder text
    var baseURLPlaceholder: String {
        switch self {
        case .claude: "https://api.anthropic.com"
        case .openai: "https://api.openai.com (or custom endpoint)"
        case .gemini: "https://generativelanguage.googleapis.com"
        case .ollama: "http://localhost:11434"
        case .openrouter: "https://openrouter.ai/api"
        case .mistral: "https://api.mistral.ai"
        case .groq: "https://api.groq.com"
        case .xai: "https://api.x.ai"
        case .cohere: "https://api.cohere.ai"
        case .deepinfra: "https://api.deepinfra.com"
        case .deepseek: "https://api.deepseek.com"
        case .minimax: "https://api.minimax.chat/v1"
        case .alibaba: "https://dashscope-intl.aliyuncs.com/compatible-mode/v1"
        case .moonshotai: "https://api.moonshot.ai/v1"
        case .zhipuai: "https://open.bigmodel.cn/api/paas/v4"
        case .perplexity: "https://api.perplexity.ai"
        case .bedrock: "https://bedrock-runtime.<region>.amazonaws.com"
        case .lmstudio: "http://127.0.0.1:1234/v1"
        }
    }
}
