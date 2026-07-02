//
//  ToolPermissionPolicy.swift
//  Motive
//
//  Models OpenCode's native per-tool + per-pattern permission system.
//

import Foundation
import os

// MARK: - Trust Level

/// Trust levels controlling how aggressively the AI operates.
///
/// - `careful`: Ask before edits and shell commands (safest).
/// - `balanced`: Auto-approve file edits; ask for unknown shell commands.
/// - `yolo`: Allow everything except protected system paths (fastest).
enum TrustLevel: String, CaseIterable, Codable, Sendable {
    case careful
    case balanced
    case yolo

    var displayName: String {
        switch self {
        case .careful: L10n.Settings.trustCareful
        case .balanced: L10n.Settings.trustBalanced
        case .yolo: L10n.Settings.trustYolo
        }
    }

    var description: String {
        switch self {
        case .careful:
            L10n.Settings.trustCarefulDesc
        case .balanced:
            L10n.Settings.trustBalancedDesc
        case .yolo:
            L10n.Settings.trustYoloDesc
        }
    }

    var systemSymbol: String {
        switch self {
        case .careful: "shield.checkered"
        case .balanced: "gauge.with.dots.needle.50percent"
        case .yolo: "bolt.shield"
        }
    }
}

// MARK: - Tool Permission Categories

/// Tool permission categories matching OpenCode's permission system.
/// Each category corresponds to a tool or tool group in OpenCode.
enum ToolPermission: String, CaseIterable, Codable, Hashable, Sendable {
    case edit // File editing (create, modify, overwrite)
    case bash // Shell commands
    case read // File reading
    case glob // File searching
    case grep // Content searching
    case list // Directory listing
    case task // Subtask creation
    case question // Native question popup (must always be allowed)
    case webfetch // Web fetching
    case websearch // Web searching
    case externalDirectory = "external_directory" // External directory access

    /// Human-readable display name.
    var displayName: String {
        switch self {
        case .edit: "Edit"
        case .bash: "Bash"
        case .read: "Read"
        case .glob: "Glob"
        case .grep: "Grep"
        case .list: "List"
        case .task: "Task"
        case .question: "Question"
        case .webfetch: "Web Fetch"
        case .websearch: "Web Search"
        case .externalDirectory: "External Directory"
        }
    }

    /// Localized description for the Settings UI.
    var localizedDescription: String {
        switch self {
        case .edit: "Create, modify, or overwrite files"
        case .bash: "Run shell commands"
        case .read: "Read file contents"
        case .glob: "Search for files by pattern"
        case .grep: "Search file contents"
        case .list: "List directory contents"
        case .task: "Create subtask agents"
        case .question: "Ask user questions via native popup"
        case .webfetch: "Fetch web content"
        case .websearch: "Search the web"
        case .externalDirectory: "Access directories outside the project"
        }
    }

    /// SF Symbol name for the Settings UI.
    var systemSymbol: String {
        switch self {
        case .edit: "pencil"
        case .bash: "terminal"
        case .read: "doc.text"
        case .glob: "doc.text.magnifyingglass"
        case .grep: "magnifyingglass"
        case .list: "folder"
        case .task: "arrow.triangle.branch"
        case .question: "questionmark.bubble"
        case .webfetch: "globe"
        case .websearch: "magnifyingglass.circle"
        case .externalDirectory: "folder.badge.questionmark"
        }
    }

    /// Risk level for visual indication.
    var riskLevel: RiskLevel {
        switch self {
        case .edit: .medium
        case .bash: .high
        case .read, .glob, .grep, .list:
            .low
        case .task: .medium
        case .question: .low
        case .webfetch, .websearch:
            .low
        case .externalDirectory: .medium
        }
    }

    /// Whether this tool shows up in the primary Settings section.
    /// Low-risk tools are collapsed into an "Advanced" section.
    var isPrimary: Bool {
        switch self {
        case .edit, .bash, .read, .externalDirectory:
            true
        default:
            false
        }
    }
}

// MARK: - Risk Level

/// Risk levels for permission operations.
enum RiskLevel: Int, Comparable, Sendable {
    case low = 0
    case medium = 1
    case high = 2
    case critical = 3

    static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var displayName: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .critical: "Critical"
        }
    }

    var color: String {
        switch self {
        case .low: "green"
        case .medium: "yellow"
        case .high: "orange"
        case .critical: "red"
        }
    }
}

// MARK: - Permission Action

/// Permission actions matching OpenCode's PermissionAction type.
enum PermissionAction: String, Codable, CaseIterable, Sendable {
    case allow
    case ask
    case deny

    var displayName: String {
        switch self {
        case .allow: "Allow"
        case .ask: "Ask"
        case .deny: "Deny"
        }
    }
}

// MARK: - Permission Rule

/// A pattern-based permission rule for a specific tool.
struct ToolPermissionRule: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let pattern: String // e.g., "*.ts", "git *", "/System/**"
    let action: PermissionAction
    let description: String?

    init(
        id: UUID = UUID(),
        pattern: String,
        action: PermissionAction,
        description: String? = nil
    ) {
        self.id = id
        self.pattern = pattern
        self.action = action
        self.description = description
    }
}

// MARK: - Per-Tool Configuration

/// Configuration for a single tool's permission rules.
struct ToolPermissionConfig: Codable, Sendable {
    let tool: ToolPermission
    var defaultAction: PermissionAction
    var rules: [ToolPermissionRule]

    init(
        tool: ToolPermission,
        defaultAction: PermissionAction,
        rules: [ToolPermissionRule] = []
    ) {
        self.tool = tool
        self.defaultAction = defaultAction
        self.rules = rules
    }
}

// MARK: - Tool Permission Policy Manager

/// Manages tool permission policies and generates opencode.json permission rules.
///
/// Maps directly to OpenCode's native per-tool + per-pattern permission system.
@MainActor
final class ToolPermissionPolicy {
    static let shared = ToolPermissionPolicy()

    private static let userDefaultsKey = "toolPermissionPolicies"
    private var configs: [ToolPermission: ToolPermissionConfig]
    private let logger = Logger(subsystem: "com.velvet.motive", category: "ToolPermissionPolicy")

    private init() {
        configs = Self.loadConfigs()
    }

    // MARK: - Public API

    /// Get the configuration for a specific tool.
    func config(for tool: ToolPermission) -> ToolPermissionConfig {
        configs[tool] ?? ToolPermissionConfig(tool: tool, defaultAction: .ask)
    }

    /// Update the configuration for a specific tool.
    func setConfig(_ config: ToolPermissionConfig) {
        configs[config.tool] = config
        saveConfigs()
    }

    /// Update the default action for a tool.
    func setDefaultAction(_ action: PermissionAction, for tool: ToolPermission) {
        var config = self.config(for: tool)
        config = ToolPermissionConfig(
            tool: tool,
            defaultAction: action,
            rules: config.rules
        )
        configs[tool] = config
        saveConfigs()
    }

    /// Add a pattern rule to a tool.
    func addRule(_ rule: ToolPermissionRule, to tool: ToolPermission) {
        var config = self.config(for: tool)
        var rules = config.rules
        rules.append(rule)
        config = ToolPermissionConfig(
            tool: tool,
            defaultAction: config.defaultAction,
            rules: rules
        )
        configs[tool] = config
        saveConfigs()
    }

    /// Remove a rule by ID from a tool.
    func removeRule(id: UUID, from tool: ToolPermission) {
        var config = self.config(for: tool)
        var rules = config.rules
        rules.removeAll { $0.id == id }
        config = ToolPermissionConfig(
            tool: tool,
            defaultAction: config.defaultAction,
            rules: rules
        )
        configs[tool] = config
        saveConfigs()
    }

    /// Reset all configurations to defaults for the current trust level.
    func resetToDefaults() {
        configs = Self.defaultConfigs()
        saveConfigs()
    }

    /// Apply a trust level, resetting all tool configs to that level's preset.
    func applyTrustLevel(_ level: TrustLevel) {
        configs = Self.configsForTrustLevel(level)
        saveConfigs()
        logger.info("Applied trust level: \(level.rawValue)")
    }

    /// Generate the permission rules dictionary for opencode.json.
    ///
    /// Output format matches OpenCode's permission configuration:
    /// - Simple: `"tool": "action"` when no pattern rules
    /// - Pattern-based: `"tool": { "pattern": "action", ..., "*": "default" }` with rules
    func toOpenCodePermissionRules() -> [String: Any] {
        var rules: [String: Any] = [:]

        // Always prepend system protection rules
        let protectedRules = Self.protectedPathRules()

        for tool in ToolPermission.allCases {
            let config = self.config(for: tool)
            let toolProtectedRules = protectedRules.filter { $0.tool == tool }

            if config.rules.isEmpty, toolProtectedRules.isEmpty {
                // Simple format: just the default action
                rules[tool.rawValue] = config.defaultAction.rawValue
            } else {
                // Pattern-based format
                var patternRules: [String: String] = [:]

                // Protected paths first (highest priority in OpenCode's last-match-wins)
                // Note: OpenCode uses last-match-wins, so we put protected rules first
                // and user rules + default after

                // User-defined pattern rules
                for rule in config.rules {
                    patternRules[rule.pattern] = rule.action.rawValue
                }

                // Protected system paths (these are always deny, overriding user rules)
                for rule in toolProtectedRules {
                    patternRules[rule.pattern] = rule.action.rawValue
                }

                // Default action as wildcard
                patternRules["*"] = config.defaultAction.rawValue

                rules[tool.rawValue] = patternRules
            }
        }

        return rules
    }

    // MARK: - Defaults

    /// Default configurations using the persisted trust level.
    static func defaultConfigs() -> [ToolPermission: ToolPermissionConfig] {
        let rawValue = UserDefaults.standard.string(forKey: "trustLevel") ?? TrustLevel.balanced.rawValue
        let level = TrustLevel(rawValue: rawValue) ?? .balanced
        return configsForTrustLevel(level)
    }

    /// Generate tool configs for a specific trust level.
    static func configsForTrustLevel(_ level: TrustLevel) -> [ToolPermission: ToolPermissionConfig] {
        switch level {
        case .careful: carefulConfigs()
        case .balanced: balancedConfigs()
        case .yolo: yoloConfigs()
        }
    }

    // MARK: Careful — Ask for edits and bash

    private static func carefulConfigs() -> [ToolPermission: ToolPermissionConfig] {
        var configs: [ToolPermission: ToolPermissionConfig] = [:]

        configs[.edit] = ToolPermissionConfig(
            tool: .edit,
            defaultAction: .ask
        )

        configs[.bash] = ToolPermissionConfig(
            tool: .bash,
            defaultAction: .ask,
            rules: [
                ToolPermissionRule(pattern: "git *", action: .allow, description: "Git commands"),
                ToolPermissionRule(pattern: "npm *", action: .allow, description: "NPM commands"),
                ToolPermissionRule(pattern: "yarn *", action: .allow, description: "Yarn commands"),
                ToolPermissionRule(pattern: "pnpm *", action: .allow, description: "PNPM commands"),
                ToolPermissionRule(pattern: "browser-use-sidecar *", action: .allow, description: "Browser automation commands"),
                ToolPermissionRule(pattern: "sleep *", action: .allow, description: "Sleep commands"),
            ]
        )

        configs[.read] = ToolPermissionConfig(tool: .read, defaultAction: .allow)
        configs[.glob] = ToolPermissionConfig(tool: .glob, defaultAction: .allow)
        configs[.grep] = ToolPermissionConfig(tool: .grep, defaultAction: .allow)
        configs[.list] = ToolPermissionConfig(tool: .list, defaultAction: .allow)
        configs[.task] = ToolPermissionConfig(tool: .task, defaultAction: .allow)
        configs[.question] = ToolPermissionConfig(tool: .question, defaultAction: .allow)
        configs[.webfetch] = ToolPermissionConfig(tool: .webfetch, defaultAction: .allow)
        configs[.websearch] = ToolPermissionConfig(tool: .websearch, defaultAction: .allow)
        configs[.externalDirectory] = ToolPermissionConfig(tool: .externalDirectory, defaultAction: .allow)

        return configs
    }

    // MARK: Balanced — Auto-edit, ask for unknown bash

    private static func balancedConfigs() -> [ToolPermission: ToolPermissionConfig] {
        var configs: [ToolPermission: ToolPermissionConfig] = [:]

        configs[.edit] = ToolPermissionConfig(
            tool: .edit,
            defaultAction: .allow
        )

        configs[.bash] = ToolPermissionConfig(
            tool: .bash,
            defaultAction: .ask,
            rules: [
                ToolPermissionRule(pattern: "git *", action: .allow, description: "Git commands"),
                ToolPermissionRule(pattern: "npm *", action: .allow, description: "NPM commands"),
                ToolPermissionRule(pattern: "yarn *", action: .allow, description: "Yarn commands"),
                ToolPermissionRule(pattern: "pnpm *", action: .allow, description: "PNPM commands"),
                ToolPermissionRule(pattern: "bun *", action: .allow, description: "Bun commands"),
                ToolPermissionRule(pattern: "cargo *", action: .allow, description: "Cargo commands"),
                ToolPermissionRule(pattern: "swift *", action: .allow, description: "Swift commands"),
                ToolPermissionRule(pattern: "xcodebuild *", action: .allow, description: "Xcode build commands"),
                ToolPermissionRule(pattern: "python *", action: .allow, description: "Python commands"),
                ToolPermissionRule(pattern: "pip *", action: .allow, description: "Pip commands"),
                ToolPermissionRule(pattern: "go *", action: .allow, description: "Go commands"),
                ToolPermissionRule(pattern: "make *", action: .allow, description: "Make commands"),
                ToolPermissionRule(pattern: "cmake *", action: .allow, description: "CMake commands"),
                ToolPermissionRule(pattern: "docker *", action: .allow, description: "Docker commands"),
                ToolPermissionRule(pattern: "kubectl *", action: .allow, description: "Kubectl commands"),
                ToolPermissionRule(pattern: "cat *", action: .allow, description: "Cat commands"),
                ToolPermissionRule(pattern: "ls *", action: .allow, description: "List commands"),
                ToolPermissionRule(pattern: "find *", action: .allow, description: "Find commands"),
                ToolPermissionRule(pattern: "grep *", action: .allow, description: "Grep commands"),
                ToolPermissionRule(pattern: "rg *", action: .allow, description: "Ripgrep commands"),
                ToolPermissionRule(pattern: "echo *", action: .allow, description: "Echo commands"),
                ToolPermissionRule(pattern: "mkdir *", action: .allow, description: "Mkdir commands"),
                ToolPermissionRule(pattern: "cp *", action: .allow, description: "Copy commands"),
                ToolPermissionRule(pattern: "mv *", action: .allow, description: "Move commands"),
                ToolPermissionRule(pattern: "touch *", action: .allow, description: "Touch commands"),
                ToolPermissionRule(pattern: "head *", action: .allow, description: "Head commands"),
                ToolPermissionRule(pattern: "tail *", action: .allow, description: "Tail commands"),
                ToolPermissionRule(pattern: "wc *", action: .allow, description: "Word count commands"),
                ToolPermissionRule(pattern: "sort *", action: .allow, description: "Sort commands"),
                ToolPermissionRule(pattern: "browser-use-sidecar *", action: .allow, description: "Browser automation commands"),
                ToolPermissionRule(pattern: "sleep *", action: .allow, description: "Sleep commands"),
            ]
        )

        configs[.read] = ToolPermissionConfig(tool: .read, defaultAction: .allow)
        configs[.glob] = ToolPermissionConfig(tool: .glob, defaultAction: .allow)
        configs[.grep] = ToolPermissionConfig(tool: .grep, defaultAction: .allow)
        configs[.list] = ToolPermissionConfig(tool: .list, defaultAction: .allow)
        configs[.task] = ToolPermissionConfig(tool: .task, defaultAction: .allow)
        configs[.question] = ToolPermissionConfig(tool: .question, defaultAction: .allow)
        configs[.webfetch] = ToolPermissionConfig(tool: .webfetch, defaultAction: .allow)
        configs[.websearch] = ToolPermissionConfig(tool: .websearch, defaultAction: .allow)
        configs[.externalDirectory] = ToolPermissionConfig(tool: .externalDirectory, defaultAction: .allow)

        return configs
    }

    // MARK: YOLO — Allow everything (except protected paths)

    private static func yoloConfigs() -> [ToolPermission: ToolPermissionConfig] {
        var configs: [ToolPermission: ToolPermissionConfig] = [:]

        for tool in ToolPermission.allCases {
            configs[tool] = ToolPermissionConfig(tool: tool, defaultAction: .allow)
        }

        return configs
    }

    /// Protected system paths that are always deny regardless of user settings.
    private static func protectedPathRules() -> [(tool: ToolPermission, pattern: String, action: PermissionAction)] {
        [
            (.edit, "/System/**", .deny),
            (.edit, "/usr/**", .deny),
            (.edit, "~/.ssh/**", .deny),
            (.edit, "~/.gnupg/**", .deny),
            (.bash, "rm -rf /", .deny),
            (.bash, "rm -rf /*", .deny),
        ]
    }

    // MARK: - Persistence

    private static func loadConfigs() -> [ToolPermission: ToolPermissionConfig] {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            return defaultConfigs()
        }

        let decoded: [String: ToolPermissionConfig]
        do {
            decoded = try JSONDecoder().decode([String: ToolPermissionConfig].self, from: data)
        } catch {
            Log.error("Failed to decode tool permission configs: \(error)")
            return defaultConfigs()
        }

        var configs = defaultConfigs()
        for (key, config) in decoded {
            if let tool = ToolPermission(rawValue: key) {
                configs[tool] = config
            }
        }
        return configs
    }

    private func saveConfigs() {
        var dict: [String: ToolPermissionConfig] = [:]
        for (tool, config) in configs {
            dict[tool.rawValue] = config
        }
        do {
            let data = try JSONEncoder().encode(dict)
            UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
        } catch {
            Log.error("Failed to encode tool permission configs: \(error)")
        }
    }
}
