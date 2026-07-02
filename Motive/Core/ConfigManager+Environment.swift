import Foundation

@MainActor
extension ConfigManager {
    func makeEnvironment() -> [String: String] {
        // Sync and config generation (side effects - kept in ConfigManager)
        syncToOpenCodeAuth()
        generateOpenCodeConfig()

        let inputs = EnvironmentBuilder.Inputs(
            provider: provider,
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            debugMode: debugMode,
            skillsSystemEnabled: skillsSystemEnabled,
            browserUseEnabled: browserUseEnabled,
            browserAgentProvider: browserAgentProvider,
            cachedBrowserAgentAPIKey: cachedBrowserAgentAPIKey,
            browserAgentBaseUrl: browserAgentBaseUrl,
            openCodeConfigPath: openCodeConfigPath,
            openCodeConfigDir: openCodeConfigDir,
            memoryEnabled: memoryEnabled,
            workspaceDirectory: workspaceDirectory.path
        )
        return EnvironmentBuilder.build(from: inputs)
    }

    /// Build extended PATH for OpenCode's runtime environment.
    ///
    /// Uses `CommandRunner.effectivePaths()` as the single source of truth,
    /// then adds additional paths specific to this context (app bundle resources,
    /// NVM versions, and Node.js version managers).
    ///
    /// IMPORTANT: `CommandRunner.effectivePaths()` is also used by `SkillGating.hasBinary()`
    /// to check skill eligibility. Both MUST share the same base paths so that a skill
    /// marked "ready" can actually find its binaries at runtime.
    func buildExtendedPath(base: String?) -> String {
        PathBuilder.buildExtendedPath(base: base)
    }

    /// Get system PATH from macOS path_helper utility
    func getSystemPath() -> String? {
        PathBuilder.getSystemPath()
    }
}
