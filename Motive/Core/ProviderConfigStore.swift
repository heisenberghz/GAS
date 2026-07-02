//
//  ProviderConfigStore.swift
//  Motive
//

import Foundation

/// Dictionary-style access to per-provider configuration.
/// Uses the SAME UserDefaults keys as the original @AppStorage properties
/// (e.g., "claude.baseURL", "openai.modelName") for zero migration cost.
///
/// The 34 @AppStorage properties in ConfigManager.swift remain for SwiftUI
/// bindings in settings views; this store provides an alternative access path
/// that eliminates the 17-case switch statements in ConfigManager+Provider.
@MainActor
final class ProviderConfigStore {

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Default Values

    /// Default base URL values that match the @AppStorage declarations.
    private static let defaultBaseURLs: [ConfigManager.Provider: String] = [
        .ollama: "http://localhost:11434",
        .lmstudio: "http://127.0.0.1:1234/v1",
        .alibaba: "https://dashscope-intl.aliyuncs.com/compatible-mode/v1",
        .moonshotai: "https://api.moonshot.ai/v1",
        .zhipuai: "https://open.bigmodel.cn/api/paas/v4",
    ]

    // MARK: - Base URL

    /// Default base URL for a provider (empty for most, localhost for Ollama).
    func defaultBaseURL(for provider: ConfigManager.Provider) -> String {
        Self.defaultBaseURLs[provider, default: ""]
    }

    /// Read base URL from UserDefaults (legacy path, used during migration).
    func baseURL(for provider: ConfigManager.Provider) -> String {
        defaults.string(forKey: baseURLKey(for: provider))
            ?? Self.defaultBaseURLs[provider, default: ""]
    }

    func setBaseURL(_ url: String, for provider: ConfigManager.Provider) {
        defaults.set(url, forKey: baseURLKey(for: provider))
    }

    // MARK: - Model Name

    func modelName(for provider: ConfigManager.Provider) -> String {
        defaults.string(forKey: modelNameKey(for: provider)) ?? ""
    }

    func setModelName(_ name: String, for provider: ConfigManager.Provider) {
        defaults.set(name, forKey: modelNameKey(for: provider))
    }

    // MARK: - Key Mapping

    /// Returns the UserDefaults key for a provider's base URL.
    /// These MUST match the @AppStorage key strings in ConfigManager.swift exactly:
    ///   @AppStorage("claude.baseURL"), @AppStorage("ollama.baseURL"), etc.
    private func baseURLKey(for provider: ConfigManager.Provider) -> String {
        "\(provider.rawValue).baseURL"
    }

    /// Returns the UserDefaults key for a provider's model name.
    /// These MUST match the @AppStorage key strings in ConfigManager.swift exactly:
    ///   @AppStorage("claude.modelName"), @AppStorage("openai.modelName"), etc.
    private func modelNameKey(for provider: ConfigManager.Provider) -> String {
        "\(provider.rawValue).modelName"
    }
}
