//
//  EnvironmentBuilder.swift
//  Motive
//

import Foundation

enum EnvironmentBuilder {

    struct Inputs {
        let provider: ConfigManager.Provider
        let apiKey: String
        let baseURL: String
        let debugMode: Bool
        let skillsSystemEnabled: Bool
        let browserUseEnabled: Bool
        let browserAgentProvider: ConfigManager.BrowserAgentProvider
        let cachedBrowserAgentAPIKey: String?
        let browserAgentBaseUrl: String
        let openCodeConfigPath: String
        let openCodeConfigDir: String
        let memoryEnabled: Bool
        let workspaceDirectory: String
    }

    /// Build the environment dictionary for the OpenCode subprocess.
    /// This is a pure function — all dependencies are passed via `inputs`.
    ///
    /// NOTE: The caller is responsible for invoking `syncToOpenCodeAuth()` and
    /// `generateOpenCodeConfig()` **before** calling this method, as those are
    /// side-effecting operations that belong in ConfigManager.
    static func build(from inputs: Inputs, baseEnvironment: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var environment = baseEnvironment
        let apiKeyValue = inputs.apiKey

        // Remove proxy environment variables to avoid SOCKS proxy errors with browser-use
        // browser-use uses httpx which doesn't have socksio installed by default
        let proxyKeys = [
            "ALL_PROXY",
            "all_proxy",
            "HTTP_PROXY",
            "http_proxy",
            "HTTPS_PROXY",
            "https_proxy",
            "NO_PROXY",
            "no_proxy",
            "SOCKS_PROXY",
            "socks_proxy"
        ]
        for key in proxyKeys {
            environment.removeValue(forKey: key)
        }

        // Extend PATH with common Node.js installation paths
        // This is critical because /bin/sh doesn't load user's shell config
        environment["PATH"] = PathBuilder.buildExtendedPath(base: environment["PATH"])
        environment["TERM"] = "dumb"
        environment["NO_COLOR"] = "1"
        environment["FORCE_COLOR"] = "0"
        environment["CI"] = "1"
        // Register as CLI client so OpenCode exposes plan_enter/plan_exit.
        // We still use the HTTP API + SSE flow from Motive; this value controls
        // feature gating in OpenCode's tool registry.
        environment["OPENCODE_CLIENT"] = "cli"
        environment["OPENCODE_EXPERIMENTAL_PLAN_MODE"] = "1"

        if inputs.provider.requiresAPIKey {
            if !apiKeyValue.isEmpty {
                // Set environment variable for the provider
                let envKeyName = inputs.provider.envKeyName
                environment[envKeyName] = apiKeyValue
                Log.config(" Using \(inputs.provider.displayName) API key (\(envKeyName)): \(apiKeyValue.prefix(10))...")
            } else {
                Log.config(" WARNING - No API key configured for \(inputs.provider.displayName)!")
            }
        } else if inputs.provider.allowsOptionalAPIKey, !apiKeyValue.isEmpty {
            // Local providers (LM Studio, Ollama) may have authentication enabled
            // Pass the key both as OPENAI_API_KEY (for OpenAI-compatible endpoint recognition) and
            // via the config file options.apiKey (handled by OpenCodeConfigGenerator)
            environment["OPENAI_API_KEY"] = apiKeyValue
            Log.config(" Using \(inputs.provider.displayName) optional API token (server auth enabled)")
        } else {
            Log.config(" Using \(inputs.provider.displayName) (no API key needed)")
        }

        // Note: baseURL is configured via opencode.json provider.options.baseURL
        // Environment variables are not needed as OpenCode reads from config file

        if inputs.debugMode {
            environment["DEBUG"] = "1"
        }

        // Inject skill-specific environment overrides (OpenClaw-style)
        if inputs.skillsSystemEnabled {
            let overrides = SkillRegistry.shared.environmentOverrides()
            for (key, value) in overrides {
                if environment[key]?.isEmpty ?? true {
                    environment[key] = value
                }
            }
        }

        // Set Browser Agent API key for browser-use-sidecar agent_task
        // Only use cached value to avoid triggering additional Keychain prompts
        if inputs.browserUseEnabled, let cachedKey = inputs.cachedBrowserAgentAPIKey, !cachedKey.isEmpty {
            let envKeyName = inputs.browserAgentProvider.envKeyName
            environment[envKeyName] = cachedKey
            Log.config(" Browser Agent API key (\(envKeyName)): \(cachedKey.prefix(10))...")

            // Set base URL if configured
            if let baseUrlEnvName = inputs.browserAgentProvider.baseUrlEnvName, !inputs.browserAgentBaseUrl.isEmpty {
                environment[baseUrlEnvName] = inputs.browserAgentBaseUrl
                Log.config(" Browser Agent Base URL (\(baseUrlEnvName)): \(inputs.browserAgentBaseUrl)")
            }
        }

        // Set OPENCODE_CONFIG if we generated a config file
        if !inputs.openCodeConfigPath.isEmpty {
            environment["OPENCODE_CONFIG"] = inputs.openCodeConfigPath
            Log.config(" Using OpenCode config: \(inputs.openCodeConfigPath)")

            // Verify the config file exists
            if FileManager.default.fileExists(atPath: inputs.openCodeConfigPath) {
                Log.config(" Config file verified at: \(inputs.openCodeConfigPath)")
            } else {
                Log.config(" WARNING - Config file NOT found at: \(inputs.openCodeConfigPath)")
            }

            if !inputs.openCodeConfigDir.isEmpty {
                environment["OPENCODE_CONFIG_DIR"] = inputs.openCodeConfigDir
                Log.config(" Using OpenCode config dir: \(inputs.openCodeConfigDir)")
            }
        } else {
            Log.config(" WARNING - openCodeConfigPath is empty!")
        }

        // Motive workspace and memory plugin environment
        if inputs.memoryEnabled {
            environment["MOTIVE_WORKSPACE"] = inputs.workspaceDirectory
        }

        return environment
    }
}

// MARK: - Path Builder

enum PathBuilder {
    /// Build extended PATH for OpenCode's runtime environment.
    ///
    /// Uses `CommandRunner.effectivePaths()` as the single source of truth,
    /// then adds additional paths specific to this context (app bundle resources,
    /// NVM versions, and Node.js version managers).
    ///
    /// IMPORTANT: `CommandRunner.effectivePaths()` is also used by `SkillGating.hasBinary()`
    /// to check skill eligibility. Both MUST share the same base paths so that a skill
    /// marked "ready" can actually find its binaries at runtime.
    static func buildExtendedPath(base: String?) -> String {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        var pathParts: [String] = []

        // Add App Bundle Resources path for bundled binaries (browser-use-sidecar)
        if let resourcesPath = Bundle.main.resourcePath {
            pathParts.append(resourcesPath)
        }

        // NVM paths (dynamic - check all installed versions)
        let nvmVersionsDir = "\(homeDir)/.nvm/versions/node"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmVersionsDir) {
            let sortedVersions = versions
                .filter { $0.hasPrefix("v") }
                .sorted { v1, v2 in
                    let parse: (String) -> Int = { v in
                        let parts = v.dropFirst().split(separator: ".").compactMap { Int($0) }
                        let major = !parts.isEmpty ? parts[0] : 0
                        let minor = parts.count > 1 ? parts[1] : 0
                        let patch = parts.count > 2 ? parts[2] : 0
                        return major * 10000 + minor * 100 + patch
                    }
                    return parse(v1) > parse(v2)
                }
            for version in sortedVersions {
                let binPath = "\(nvmVersionsDir)/\(version)/bin"
                if FileManager.default.fileExists(atPath: binPath) {
                    pathParts.append(binPath)
                }
            }
        }

        // Node.js version manager paths (not covered by CommandRunner.effectivePaths)
        let nodeManagerPaths = [
            "\(homeDir)/.volta/bin", // Volta
            "\(homeDir)/.asdf/shims", // asdf
            "\(homeDir)/.fnm/current/bin", // fnm
            "\(homeDir)/.nodenv/shims", // nodenv
            "/opt/local/bin", // MacPorts
        ]
        for path in nodeManagerPaths {
            if FileManager.default.fileExists(atPath: path), !pathParts.contains(path) {
                pathParts.append(path)
            }
        }

        // Add all paths from CommandRunner.effectivePaths() — the single source of truth
        // for binary discovery (Go, Cargo, Python, Homebrew, pnpm, etc.)
        // This ensures that any binary found by SkillGating.hasBinary() is also
        // available in OpenCode's runtime environment.
        for path in CommandRunner.effectivePaths() where !pathParts.contains(path) {
            pathParts.append(path)
        }

        // Add system PATH from path_helper
        if let systemPath = PathBuilder.getSystemPath() {
            for path in systemPath.split(separator: ":").map(String.init) {
                if !pathParts.contains(path) {
                    pathParts.append(path)
                }
            }
        }

        // Add base PATH
        if let base {
            for path in base.split(separator: ":").map(String.init) {
                if !pathParts.contains(path) {
                    pathParts.append(path)
                }
            }
        }

        let result = pathParts.joined(separator: ":")
        Log.config(" Extended PATH: \(result.prefix(200))...")
        return result
    }

    /// Get system PATH from macOS path_helper utility
    static func getSystemPath() -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/libexec/path_helper")
        task.arguments = ["-s"]

        let pipe = Pipe()
        task.standardOutput = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                // Parse: PATH="..."; export PATH;
                if let match = output.range(of: #"PATH="([^"]+)""#, options: .regularExpression) {
                    let pathValue = output[match]
                        .dropFirst(6) // Remove PATH="
                        .dropLast(1) // Remove trailing "
                    return String(pathValue)
                }
            }
        } catch {
            Log.config(" path_helper failed: \(error)")
        }

        return nil
    }
}
