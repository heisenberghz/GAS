//
//  EnvironmentBuilderTests.swift
//  MotiveTests
//

@testable import Motive
import XCTest

@MainActor
final class EnvironmentBuilderTests: XCTestCase {

    // MARK: - Helpers

    /// Convenience factory that returns Inputs with sensible defaults.
    /// Override individual fields as needed via the parameters.
    private func makeInputs(
        provider: ConfigManager.Provider = .claude,
        apiKey: String = "",
        baseURL: String = "",
        debugMode: Bool = false,
        skillsSystemEnabled: Bool = false,
        browserUseEnabled: Bool = false,
        browserAgentProvider: ConfigManager.BrowserAgentProvider = .anthropic,
        cachedBrowserAgentAPIKey: String? = nil,
        browserAgentBaseUrl: String = "",
        openCodeConfigPath: String = "",
        openCodeConfigDir: String = "",
        memoryEnabled: Bool = false,
        workspaceDirectory: String = ""
    ) -> EnvironmentBuilder.Inputs {
        EnvironmentBuilder.Inputs(
            provider: provider,
            apiKey: apiKey,
            baseURL: baseURL,
            debugMode: debugMode,
            skillsSystemEnabled: skillsSystemEnabled,
            browserUseEnabled: browserUseEnabled,
            browserAgentProvider: browserAgentProvider,
            cachedBrowserAgentAPIKey: cachedBrowserAgentAPIKey,
            browserAgentBaseUrl: browserAgentBaseUrl,
            openCodeConfigPath: openCodeConfigPath,
            openCodeConfigDir: openCodeConfigDir,
            memoryEnabled: memoryEnabled,
            workspaceDirectory: workspaceDirectory
        )
    }

    /// A minimal base environment for isolation. By passing this instead of
    /// the real ProcessInfo environment we avoid interference from the host.
    private let emptyBase: [String: String] = [:]

    // MARK: - API Key Injection

    func testAPIKeySetForClaude() {
        let inputs = makeInputs(provider: .claude, apiKey: "sk-test-key-123")
        let env = EnvironmentBuilder.build(from: inputs, baseEnvironment: emptyBase)

        XCTAssertEqual(env["ANTHROPIC_API_KEY"], "sk-test-key-123")
    }

    func testAPIKeySetForOpenAI() {
        let inputs = makeInputs(provider: .openai, apiKey: "sk-openai-abc")
        let env = EnvironmentBuilder.build(from: inputs, baseEnvironment: emptyBase)

        XCTAssertEqual(env["OPENAI_API_KEY"], "sk-openai-abc")
    }

    func testAPIKeySetForGemini() {
        let inputs = makeInputs(provider: .gemini, apiKey: "gemini-key-xyz")
        let env = EnvironmentBuilder.build(from: inputs, baseEnvironment: emptyBase)

        XCTAssertEqual(env["GOOGLE_GENERATIVE_AI_API_KEY"], "gemini-key-xyz")
    }

    func testAPIKeySetForOpenRouter() {
        let inputs = makeInputs(provider: .openrouter, apiKey: "or-key-456")
        let env = EnvironmentBuilder.build(from: inputs, baseEnvironment: emptyBase)

        XCTAssertEqual(env["OPENROUTER_API_KEY"], "or-key-456")
    }

    func testAPIKeySetForDeepSeek() {
        let inputs = makeInputs(provider: .deepseek, apiKey: "sk-deepseek-789")
        let env = EnvironmentBuilder.build(from: inputs, baseEnvironment: emptyBase)

        XCTAssertEqual(env["DEEPSEEK_API_KEY"], "sk-deepseek-789")
    }

    // MARK: - API Key Not Set When Empty

    func testAPIKeyNotSetWhenEmpty() {
        let inputs = makeInputs(provider: .claude, apiKey: "")
        let env = EnvironmentBuilder.build(from: inputs, baseEnvironment: emptyBase)

        XCTAssertNil(
            env["ANTHROPIC_API_KEY"],
            "ANTHROPIC_API_KEY should not be present when apiKey is empty"
        )
    }

    func testAPIKeyNotSetForOllama() {
        // Ollama does not require an API key; even if one is supplied the
        // code should skip injection because requiresAPIKey is false.
        let inputs = makeInputs(provider: .ollama, apiKey: "unexpected-key")
        let env = EnvironmentBuilder.build(from: inputs, baseEnvironment: emptyBase)

        // Ollama's envKeyName is "" so nothing meaningful should be set.
        // Verify typical key names are absent.
        XCTAssertNil(env["ANTHROPIC_API_KEY"])
        XCTAssertNil(env["OPENAI_API_KEY"])
    }

    // MARK: - Debug Mode

    func testDebugModeEnabled() {
        let inputs = makeInputs(debugMode: true)
        let env = EnvironmentBuilder.build(from: inputs, baseEnvironment: emptyBase)

        XCTAssertEqual(env["DEBUG"], "1")
    }

    func testDebugModeDisabled() {
        let inputs = makeInputs(debugMode: false)
        let env = EnvironmentBuilder.build(from: inputs, baseEnvironment: emptyBase)

        XCTAssertNil(
            env["DEBUG"],
            "DEBUG should not be present when debugMode is false"
        )
    }

    // MARK: - Config Path Injection

    func testOpenCodeConfigPathSet() {
        let path = "/tmp/motive-test/opencode.json"
        let inputs = makeInputs(openCodeConfigPath: path)
        let env = EnvironmentBuilder.build(from: inputs, baseEnvironment: emptyBase)

        XCTAssertEqual(env["OPENCODE_CONFIG"], path)
    }

    func testOpenCodeConfigPathEmpty() {
        let inputs = makeInputs(openCodeConfigPath: "")
        let env = EnvironmentBuilder.build(from: inputs, baseEnvironment: emptyBase)

        XCTAssertNil(
            env["OPENCODE_CONFIG"],
            "OPENCODE_CONFIG should not be present when openCodeConfigPath is empty"
        )
    }

    // MARK: - Config Dir Injection

    func testOpenCodeConfigDirSet() {
        let configPath = "/tmp/motive-test/opencode.json"
        let configDir = "/tmp/motive-test"
        let inputs = makeInputs(openCodeConfigPath: configPath, openCodeConfigDir: configDir)
        let env = EnvironmentBuilder.build(from: inputs, baseEnvironment: emptyBase)

        XCTAssertEqual(env["OPENCODE_CONFIG_DIR"], configDir)
    }

    func testOpenCodeConfigDirNotSetWhenConfigPathEmpty() {
        // Config dir is only set when config path is non-empty
        let inputs = makeInputs(openCodeConfigPath: "", openCodeConfigDir: "/tmp/motive-test")
        let env = EnvironmentBuilder.build(from: inputs, baseEnvironment: emptyBase)

        XCTAssertNil(
            env["OPENCODE_CONFIG_DIR"],
            "OPENCODE_CONFIG_DIR should not be set when openCodeConfigPath is empty"
        )
    }

    func testOpenCodeConfigDirNotSetWhenDirEmpty() {
        let inputs = makeInputs(openCodeConfigPath: "/tmp/config.json", openCodeConfigDir: "")
        let env = EnvironmentBuilder.build(from: inputs, baseEnvironment: emptyBase)

        XCTAssertNil(
            env["OPENCODE_CONFIG_DIR"],
            "OPENCODE_CONFIG_DIR should not be set when openCodeConfigDir is empty"
        )
    }

    // MARK: - Memory Environment

    func testMemoryEnvironmentSetWhenEnabled() {
        let inputs = makeInputs(
            memoryEnabled: true,
            workspaceDirectory: "/tmp/motive-workspace"
        )
        let env = EnvironmentBuilder.build(from: inputs, baseEnvironment: emptyBase)
        XCTAssertEqual(env["MOTIVE_WORKSPACE"], "/tmp/motive-workspace")
    }

    func testMemoryEnvironmentNotSetWhenDisabled() {
        let inputs = makeInputs(
            memoryEnabled: false,
            workspaceDirectory: "/tmp/motive-workspace"
        )
        let env = EnvironmentBuilder.build(from: inputs, baseEnvironment: emptyBase)
        XCTAssertNil(env["MOTIVE_WORKSPACE"])
    }

    // MARK: - Proxy Variables Cleared

    func testProxyVariablesRemovedFromBaseEnvironment() {
        let baseWithProxies: [String: String] = [
            "HTTP_PROXY": "http://proxy:8080",
            "http_proxy": "http://proxy:8080",
            "HTTPS_PROXY": "https://proxy:8080",
            "https_proxy": "https://proxy:8080",
            "ALL_PROXY": "socks5://proxy:1080",
            "all_proxy": "socks5://proxy:1080",
            "NO_PROXY": "localhost",
            "no_proxy": "localhost",
            "SOCKS_PROXY": "socks5://proxy:1080",
            "socks_proxy": "socks5://proxy:1080",
        ]

        let inputs = makeInputs()
        let env = EnvironmentBuilder.build(from: inputs, baseEnvironment: baseWithProxies)

        XCTAssertNil(env["HTTP_PROXY"], "HTTP_PROXY should be removed")
        XCTAssertNil(env["http_proxy"], "http_proxy should be removed")
        XCTAssertNil(env["HTTPS_PROXY"], "HTTPS_PROXY should be removed")
        XCTAssertNil(env["https_proxy"], "https_proxy should be removed")
        XCTAssertNil(env["ALL_PROXY"], "ALL_PROXY should be removed")
        XCTAssertNil(env["all_proxy"], "all_proxy should be removed")
        XCTAssertNil(env["NO_PROXY"], "NO_PROXY should be removed")
        XCTAssertNil(env["no_proxy"], "no_proxy should be removed")
        XCTAssertNil(env["SOCKS_PROXY"], "SOCKS_PROXY should be removed")
        XCTAssertNil(env["socks_proxy"], "socks_proxy should be removed")
    }

    // MARK: - Standard Environment Variables

    func testStandardVariablesAlwaysSet() {
        let inputs = makeInputs()
        let env = EnvironmentBuilder.build(from: inputs, baseEnvironment: emptyBase)

        XCTAssertEqual(env["TERM"], "dumb")
        XCTAssertEqual(env["NO_COLOR"], "1")
        XCTAssertEqual(env["FORCE_COLOR"], "0")
        XCTAssertEqual(env["CI"], "1")
        XCTAssertEqual(env["OPENCODE_CLIENT"], "cli")
        XCTAssertEqual(env["OPENCODE_EXPERIMENTAL_PLAN_MODE"], "1")
    }

    func testPATHIsSet() throws {
        let inputs = makeInputs()
        let env = EnvironmentBuilder.build(from: inputs, baseEnvironment: emptyBase)

        XCTAssertNotNil(env["PATH"], "PATH should always be set")
        XCTAssertFalse(try XCTUnwrap(env["PATH"]?.isEmpty), "PATH should not be empty")
    }

    // MARK: - Browser Agent API Key

    func testBrowserAgentAPIKeySetWhenEnabled() {
        let inputs = makeInputs(
            browserUseEnabled: true,
            browserAgentProvider: .anthropic,
            cachedBrowserAgentAPIKey: "browser-key-abc"
        )
        let env = EnvironmentBuilder.build(from: inputs, baseEnvironment: emptyBase)

        XCTAssertEqual(env["ANTHROPIC_API_KEY"], "browser-key-abc")
    }

    func testBrowserAgentAPIKeyNotSetWhenDisabled() {
        let inputs = makeInputs(
            browserUseEnabled: false,
            browserAgentProvider: .anthropic,
            cachedBrowserAgentAPIKey: "browser-key-abc"
        )
        let env = EnvironmentBuilder.build(from: inputs, baseEnvironment: emptyBase)

        // Since browser use is disabled AND no provider API key was given,
        // the ANTHROPIC_API_KEY should not be present.
        XCTAssertNil(env["ANTHROPIC_API_KEY"])
    }

    func testBrowserAgentAPIKeyNotSetWhenCachedKeyNil() {
        let inputs = makeInputs(
            browserUseEnabled: true,
            browserAgentProvider: .openai,
            cachedBrowserAgentAPIKey: nil
        )
        let env = EnvironmentBuilder.build(from: inputs, baseEnvironment: emptyBase)

        XCTAssertNil(env["OPENAI_API_KEY"])
    }

    func testBrowserAgentAPIKeyNotSetWhenCachedKeyEmpty() {
        let inputs = makeInputs(
            browserUseEnabled: true,
            browserAgentProvider: .openai,
            cachedBrowserAgentAPIKey: ""
        )
        let env = EnvironmentBuilder.build(from: inputs, baseEnvironment: emptyBase)

        XCTAssertNil(env["OPENAI_API_KEY"])
    }

    func testBrowserAgentBaseUrlSetWhenProviderSupportsIt() {
        let inputs = makeInputs(
            browserUseEnabled: true,
            browserAgentProvider: .anthropic,
            cachedBrowserAgentAPIKey: "key-123",
            browserAgentBaseUrl: "https://custom.api.example.com"
        )
        let env = EnvironmentBuilder.build(from: inputs, baseEnvironment: emptyBase)

        XCTAssertEqual(env["ANTHROPIC_BASE_URL"], "https://custom.api.example.com")
    }

    func testBrowserAgentBaseUrlNotSetWhenEmpty() {
        let inputs = makeInputs(
            browserUseEnabled: true,
            browserAgentProvider: .anthropic,
            cachedBrowserAgentAPIKey: "key-123",
            browserAgentBaseUrl: ""
        )
        let env = EnvironmentBuilder.build(from: inputs, baseEnvironment: emptyBase)

        XCTAssertNil(env["ANTHROPIC_BASE_URL"])
    }

    // MARK: - Base Environment Preservation

    func testBaseEnvironmentVariablesPreserved() {
        let base: [String: String] = [
            "HOME": "/Users/testuser",
            "CUSTOM_VAR": "custom_value",
        ]
        let inputs = makeInputs()
        let env = EnvironmentBuilder.build(from: inputs, baseEnvironment: base)

        XCTAssertEqual(env["HOME"], "/Users/testuser")
        XCTAssertEqual(env["CUSTOM_VAR"], "custom_value")
    }
}
