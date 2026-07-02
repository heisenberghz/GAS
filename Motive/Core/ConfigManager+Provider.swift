//
//  ConfigManager+Provider.swift
//  Motive
//
//  Created by geezerrrr on 2026/1/19.
//

import Foundation

extension ConfigManager {
    // MARK: - Per-Provider Configuration Accessors

    /// Base URL for current provider (stored in Keychain per-provider)
    var baseURL: String {
        get {
            if let cached = cachedBaseURLs[provider] {
                return cached
            }
            let account = "opencode.base.url.\(provider.rawValue)"
            let value = KeychainStore.read(service: keychainService, account: account)
                ?? providerConfigStore.defaultBaseURL(for: provider)
            cachedBaseURLs[provider] = value
            return value
        }
        set {
            cachedBaseURLs[provider] = newValue
            let account = "opencode.base.url.\(provider.rawValue)"
            if newValue.isEmpty {
                KeychainStore.delete(service: keychainService, account: account)
            } else {
                KeychainStore.write(service: keychainService, account: account, value: newValue)
            }
        }
    }

    /// Returns a normalized version of the base URL for use in API calls.
    /// Ensures OpenAI-compatible endpoints include the required /v1 suffix if missing.
    var normalizedBaseURL: String {
        let raw = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return raw }

        // Only normalize for OpenAI-compatible providers (openai, lmstudio, etc.)
        // list taken from Provider.isOpenAICompatible or similar if it exists
        // Looking at the use cases, if it's an OpenAI/LM Studio provider and it's a custom URL.
        let isOpenAICompatible = provider == .openai || provider == .lmstudio || provider == .deepseek

        if isOpenAICompatible {
            // If it ends in a port and has no path, or ends in just the host, append /v1
            if let components = URLComponents(string: raw) {
                let path = components.path
                if path.isEmpty || path == "/" {
                    var normalized = components
                    normalized.path = "/v1"
                    return normalized.url?.absoluteString ?? raw
                }
            }
        }

        return raw
    }

    /// Model name for current provider
    var modelName: String {
        get { providerConfigStore.modelName(for: provider) }
        set { providerConfigStore.setModelName(newValue, for: provider) }
    }

    /// API Key for current provider (stored in Keychain per-provider)
    var apiKey: String {
        get {
            if let cached = cachedAPIKeys[provider] {
                return cached
            }
            let account = "opencode.api.key.\(provider.rawValue)"
            let value = KeychainStore.read(service: keychainService, account: account) ?? ""
            cachedAPIKeys[provider] = value
            return value
        }
        set {
            cachedAPIKeys[provider] = newValue
            let account = "opencode.api.key.\(provider.rawValue)"
            if newValue.isEmpty {
                KeychainStore.delete(service: keychainService, account: account)
            } else {
                KeychainStore.write(service: keychainService, account: account, value: newValue)
            }
        }
    }

    var hasAPIKey: Bool {
        let isCustomURL = !baseURL.isEmpty && !isDefaultBaseURL(for: provider)

        // If provider allows optional keys (LM Studio, Ollama), it's only truly optional
        // if we are using the default local/unauthenticated endpoint.
        if provider.allowsOptionalAPIKey, !isCustomURL {
            return true
        }

        // Otherwise, if the provider requires an API key, we must have one.
        if provider.requiresAPIKey {
            // Check cache first to avoid Keychain prompt
            if let cached = cachedAPIKeys[provider] {
                return !cached.isEmpty
            }
            return !apiKey.isEmpty
        }

        return true
    }

    /// Returns true if the stored base URL is the provider's default (unmodified) URL.
    private func isDefaultBaseURL(for p: Provider) -> Bool {
        let stored = cachedBaseURLs[p] ?? KeychainStore.read(service: keychainService, account: "opencode.base.url.\(p.rawValue)") ?? ""
        return stored.isEmpty || stored == providerConfigStore.defaultBaseURL(for: p)
    }

    /// Check if current provider is properly configured
    var isProviderConfigured: Bool {
        switch provider {
        case .ollama:
            !baseURL.isEmpty
        case .lmstudio:
            // LM Studio only needs a base URL; API token is optional (but required if auth enabled)
            !baseURL.isEmpty
        default:
            hasAPIKey
        }
    }

    /// Get configuration error message for current provider
    var providerConfigurationError: String? {
        if let urlError = validateBaseURLFormat() {
            return urlError
        }

        switch provider {
        case .ollama:
            if baseURL.isEmpty { return "Ollama Base URL not configured" }
        case .lmstudio:
            if baseURL.isEmpty { return "LM Studio Base URL not configured" }
        default:
            // For providers with a non-default custom base URL (OpenAI-compatible mode),
            // skip the API key check — the endpoint may not require one.
            if !baseURL.isEmpty, !isDefaultBaseURL(for: provider) {
                return nil
            }
            if provider.requiresAPIKey, apiKey.isEmpty {
                return "\(provider.displayName) API Key not configured"
            }
        }
        return nil
    }

    /// Get user-specified model override for OpenCode.
    /// - Returns: Raw user input if provided; otherwise `nil` so OpenCode can choose defaults.
    func getModelString() -> String? {
        let modelValue = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelValue.isEmpty else { return nil }
        return modelValue
    }

    /// Validate only URL syntax; never rewrite user input.
    private func validateBaseURLFormat() -> String? {
        let raw = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }

        guard let components = URLComponents(string: raw),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.host != nil
        else {
            return "Invalid Base URL format. Use a full URL like https://api.example.com/v1"
        }

        return nil
    }
}
