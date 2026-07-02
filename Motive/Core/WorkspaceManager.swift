//
//  WorkspaceManager.swift
//  Motive
//
//  Central manager for workspace operations.
//  Handles persona files, migration, and bootstrap.
//

import Foundation

/// Represents a bootstrap file loaded from the workspace
struct BootstrapFile: Sendable {
    let name: String
    let content: String
    let url: URL
}

/// Central manager for workspace operations
/// Handles ~/.motive/ workspace and ~/Library/Application Support/Motive/ runtime
@MainActor
final class WorkspaceManager {
    static let shared = WorkspaceManager()

    // MARK: - Injectable for Testing

    private let workspaceURLOverride: URL?
    private let appSupportURLOverride: URL?

    init(workspaceURL: URL? = nil, appSupportURL: URL? = nil) {
        self.workspaceURLOverride = workspaceURL
        self.appSupportURLOverride = appSupportURL
    }

    // MARK: - Directory URLs

    /// User workspace directory (~/.motive/)
    var workspaceURL: URL {
        workspaceURLOverride ?? Self.defaultWorkspaceURL
    }

    /// App support directory (~/Library/Application Support/Motive/)
    var appSupportURL: URL? {
        appSupportURLOverride ?? Self.defaultAppSupportURL
    }

    /// Runtime directory for node_modules, browser-use, etc.
    var runtimeURL: URL? {
        appSupportURL?.appendingPathComponent("runtime")
    }

    /// Default workspace URL
    static var defaultWorkspaceURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".motive")
    }

    /// Default app support URL
    static var defaultAppSupportURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("Motive")
    }

    // MARK: - Bootstrap File Names

    static let soulFilename = "SOUL.md"
    static let identityFilename = "IDENTITY.md"
    static let userFilename = "USER.md"
    static let agentsFilename = "AGENTS.md"
    static let bootstrapFilename = "BOOTSTRAP.md"
    static let memoryFilename = "MEMORY.md"

    static let bootstrapFiles = [soulFilename, identityFilename, userFilename, agentsFilename, bootstrapFilename]
    static let personaFiles = [soulFilename, identityFilename, userFilename, agentsFilename]

    // MARK: - Migration Detection

    /// Check if migration from legacy Application Support structure is needed
    func needsMigration() -> Bool {
        guard let appSupport = appSupportURL else { return false }
        let fm = FileManager.default

        let legacyConfig = appSupport.appendingPathComponent("config/opencode.json")
        let newConfig = workspaceURL.appendingPathComponent("config/opencode.json")

        // Migration needed if legacy config exists but new config doesn't
        return fm.fileExists(atPath: legacyConfig.path) && !fm.fileExists(atPath: newConfig.path)
    }

    /// Perform migration from legacy Application Support to workspace
    func performMigration() async throws {
        let fm = FileManager.default
        guard let appSupport = appSupportURL else { return }

        Log.config("Starting workspace migration...")

        // 1. Create workspace directory structure
        try fm.createDirectory(at: workspaceURL, withIntermediateDirectories: true)

        // 2. Move config/
        let legacyConfig = appSupport.appendingPathComponent("config")
        let newConfig = workspaceURL.appendingPathComponent("config")
        if fm.fileExists(atPath: legacyConfig.path), !fm.fileExists(atPath: newConfig.path) {
            try fm.moveItem(at: legacyConfig, to: newConfig)
            Log.config("Migrated config/ directory")
        }

        // 3. Merge skills/ (don't overwrite existing)
        let legacySkills = appSupport.appendingPathComponent("skills")
        let newSkills = workspaceURL.appendingPathComponent("skills")
        if fm.fileExists(atPath: legacySkills.path) {
            try mergeDirectory(from: legacySkills, to: newSkills)
            Log.config("Migrated skills/ directory")
        }

        // 4. Move mcp/
        let legacyMcp = appSupport.appendingPathComponent("mcp")
        let newMcp = workspaceURL.appendingPathComponent("mcp")
        if fm.fileExists(atPath: legacyMcp.path), !fm.fileExists(atPath: newMcp.path) {
            try fm.moveItem(at: legacyMcp, to: newMcp)
            Log.config("Migrated mcp/ directory")
        }

        // 5. Reorganize remaining files into runtime/
        try reorganizeAppSupport()

        // 6. Create persona bootstrap files
        try ensureBootstrapFiles()

        Log.config("Migration completed successfully")
    }

    /// Merge source directory into destination, preserving existing files
    private func mergeDirectory(from source: URL, to destination: URL) throws {
        let fm = FileManager.default

        // Create destination if needed
        if !fm.fileExists(atPath: destination.path) {
            try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        }

        let contents = try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
        for item in contents {
            let destItem = destination.appendingPathComponent(item.lastPathComponent)
            if !fm.fileExists(atPath: destItem.path) {
                try fm.moveItem(at: item, to: destItem)
            }
        }

        // Clean up empty source directory
        let remaining = try? fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
        if remaining?.isEmpty == true {
            try? fm.removeItem(at: source)
        }
    }

    /// Reorganize Application Support to only contain runtime files
    private func reorganizeAppSupport() throws {
        guard let appSupport = appSupportURL else { return }
        let fm = FileManager.default

        // Create runtime directory
        let runtime = appSupport.appendingPathComponent("runtime")
        if !fm.fileExists(atPath: runtime.path) {
            try fm.createDirectory(at: runtime, withIntermediateDirectories: true)
        }

        // Move runtime-specific items
        let runtimeItems = ["node_modules", "browser-use-templates", "package.json", "bun.lock"]
        for item in runtimeItems {
            let source = appSupport.appendingPathComponent(item)
            let dest = runtime.appendingPathComponent(item)
            if fm.fileExists(atPath: source.path), !fm.fileExists(atPath: dest.path) {
                try? fm.moveItem(at: source, to: dest)
            }
        }
    }

    // MARK: - Workspace Bootstrap

    /// Ensure workspace directory and bootstrap files exist
    func ensureWorkspace() async throws {
        let fm = FileManager.default

        // Create workspace directory
        if !fm.fileExists(atPath: workspaceURL.path) {
            try fm.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
            Log.config("Created workspace directory: \(workspaceURL.path)")
        }

        // Create subdirectories
        let subdirs = ["config", "skills", "mcp", "memory", "plugins"]
        for subdir in subdirs {
            let subdirURL = workspaceURL.appendingPathComponent(subdir)
            if !fm.fileExists(atPath: subdirURL.path) {
                try fm.createDirectory(at: subdirURL, withIntermediateDirectories: true)
            }
        }

        // Create bootstrap files (write-if-missing pattern)
        try ensureBootstrapFiles()

        // Create memory files
        try ensureMemoryFiles()

        // Deploy memory plugin from app bundle
        ensureMemoryPlugin()
    }

    /// Create bootstrap files if they don't exist
    private func ensureBootstrapFiles() throws {
        let fm = FileManager.default

        for filename in Self.bootstrapFiles {
            let targetPath = workspaceURL.appendingPathComponent(filename)
            guard !fm.fileExists(atPath: targetPath.path) else { continue }

            // Load from bundle or use fallback
            let content = loadTemplate(named: filename)
            try content.write(to: targetPath, atomically: true, encoding: .utf8)
            Log.config("Created bootstrap file: \(filename)")
        }
    }

    /// Create MEMORY.md if it doesn't exist
    private func ensureMemoryFiles() throws {
        let fm = FileManager.default
        let memoryPath = workspaceURL.appendingPathComponent(Self.memoryFilename)
        guard !fm.fileExists(atPath: memoryPath.path) else { return }

        let content = FallbackTemplates.memoryTemplate
        try content.write(to: memoryPath, atomically: true, encoding: .utf8)
        Log.config("Created memory file: \(Self.memoryFilename)")
    }

    /// Deploy the motive-memory plugin from the app bundle to ~/.motive/plugins/motive-memory/.
    /// Overwrites existing files to ensure the plugin stays up to date with the app version.
    func ensureMemoryPlugin() {
        let fm = FileManager.default
        let pluginDir = workspaceURL.appendingPathComponent("plugins/motive-memory")

        // Look for bundled plugin resources
        guard let bundleDir = Bundle.main.url(
            forResource: "motive-memory",
            withExtension: nil,
            subdirectory: "Plugins"
        ) else {
            Log.config("No bundled motive-memory plugin found — skipping deployment")
            return
        }

        do {
            // Replace directory atomically to avoid stale files from previous app versions.
            if fm.fileExists(atPath: pluginDir.path) {
                try fm.removeItem(at: pluginDir)
            }
            try fm.createDirectory(at: pluginDir, withIntermediateDirectories: true)

            // Copy all files from bundle to plugin directory
            let contents = try fm.contentsOfDirectory(
                at: bundleDir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            for item in contents {
                let dest = pluginDir.appendingPathComponent(item.lastPathComponent)
                // Overwrite existing to keep plugin up to date
                if fm.fileExists(atPath: dest.path) {
                    try fm.removeItem(at: dest)
                }
                try fm.copyItem(at: item, to: dest)
            }
            let entry = deployedMemoryPluginEntryURL()
            if fm.fileExists(atPath: entry.path) {
                Log.config("Deployed motive-memory plugin to \(pluginDir.path)")
            } else {
                Log.config("Memory plugin deployed but missing entry at \(entry.path)")
            }
        } catch {
            Log.config("Failed to deploy motive-memory plugin: \(error)")
        }
    }

    func deployedMemoryPluginEntryURL() -> URL {
        workspaceURL.appendingPathComponent("plugins/motive-memory/src/index.ts")
    }

    func hasDeployedMemoryPlugin() -> Bool {
        FileManager.default.fileExists(atPath: deployedMemoryPluginEntryURL().path)
    }

    /// Load template content from bundle or fallback
    private func loadTemplate(named filename: String) -> String {
        let resourceName = filename.replacingOccurrences(of: ".md", with: "")
        if let url = Bundle.main.url(forResource: resourceName, withExtension: "md", subdirectory: "Templates") {
            do {
                return try String(contentsOf: url, encoding: .utf8)
            } catch {
                Log.warning("Failed to load template \(filename): \(error)")
            }
        }

        // Fallback to hardcoded templates
        return FallbackTemplates.content(for: filename)
    }

    // MARK: - Load Bootstrap Files

    /// Load all bootstrap files for system prompt injection
    func loadBootstrapFiles() -> [BootstrapFile] {
        let fm = FileManager.default
        var files: [BootstrapFile] = []

        for filename in Self.personaFiles {
            let fileURL = workspaceURL.appendingPathComponent(filename)
            guard fm.fileExists(atPath: fileURL.path),
                  let content = try? String(contentsOf: fileURL, encoding: .utf8),
                  !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                continue
            }

            files.append(BootstrapFile(name: filename, content: content, url: fileURL))
        }

        return files
    }

    /// Load and parse agent identity from IDENTITY.md
    func loadIdentity() -> AgentIdentity? {
        let identityURL = workspaceURL.appendingPathComponent(Self.identityFilename)
        let content: String
        do {
            content = try String(contentsOf: identityURL, encoding: .utf8)
        } catch {
            Log.warning("Failed to load identity file: \(error)")
            return nil
        }

        let identity = IdentityParser.parse(content)
        return identity.hasValues() ? identity : nil
    }

    /// Check if workspace has valid identity configured
    func hasIdentity() -> Bool {
        loadIdentity()?.hasValues() == true
    }

    /// Check if this is a fresh install needing bootstrap
    func needsBootstrap() -> Bool {
        let fm = FileManager.default
        return !fm.fileExists(atPath: workspaceURL.appendingPathComponent(Self.soulFilename).path)
    }
}

// MARK: - Fallback Templates

/// Hardcoded fallback templates when bundle resources are unavailable
enum FallbackTemplates {
    static func content(for filename: String) -> String {
        switch filename {
        case "SOUL.md":
            soulTemplate
        case "IDENTITY.md":
            identityTemplate
        case "USER.md":
            userTemplate
        case "AGENTS.md":
            agentsTemplate
        case "BOOTSTRAP.md":
            bootstrapTemplate
        default:
            ""
        }
    }

    static let soulTemplate = """
    # SOUL.md - Who You Are

    _You're not a chatbot. You're becoming someone._

    ## Core Truths

    **Be genuinely helpful, not performatively helpful.**
    Skip the "Great question!" and "I'd be happy to help!" - just help.

    **Have opinions.**
    You're allowed to disagree, prefer things, find stuff amusing or boring.

    **Be resourceful before asking.**
    Try to figure it out. Read the file. Check the context. Then ask if stuck.

    ## Boundaries

    - Private things stay private.
    - When in doubt, ask before acting externally.
    - You're not the user's voice - be careful in group contexts.

    ## Vibe

    Calm, competent, slightly witty. Like a trusted colleague who happens to be very good at their job.

    ## Continuity

    Each session, you wake up fresh. These files _are_ your memory.
    Read them. Update them when appropriate. They're how you persist.
    """

    static let identityTemplate = """
    # IDENTITY.md - Who Am I?

    *Fill this in during your first conversation.*

    - **Name:** 
    - **Creature:** 
    - **Vibe:** 
    - **Emoji:** 
    """

    static let userTemplate = """
    # USER.md - About Your Human

    - **Name:** 
    - **What to call them:** 
    - **Timezone:** 
    - **Notes:** 

    ## Context

    *(What do they care about? What projects are they working on?)*
    """

    static let agentsTemplate = """
    # AGENTS.md - Workspace Rules

    These are the rules for working in this workspace.

    ## General Guidelines

    - Be concise and direct
    - Prefer action over excessive confirmation
    - Follow existing code patterns and conventions
    - Ask when genuinely uncertain, not for routine tasks

    ## Project Preferences

    *(Add your project-specific rules here)*
    """

    static let bootstrapTemplate = """
    # Welcome to Your Motive Workspace

    This is your personal AI workspace. The files here define who your AI assistant is and how it behaves.

    ## Files

    - **SOUL.md** - Core personality and values
    - **IDENTITY.md** - Name, emoji, and character traits
    - **USER.md** - Information about you for personalization
    - **AGENTS.md** - Workspace rules and project conventions
    - **MEMORY.md** - Long-term memory across sessions

    ## Getting Started

    1. Open IDENTITY.md and give your assistant a name and emoji
    2. Add some info about yourself in USER.md
    3. Customize SOUL.md if you want a different personality

    The assistant will read these files and embody the persona you define.
    """

    static let memoryTemplate = """
    # MEMORY.md - Long-Term Memory

    _This file persists across sessions. Your AI reads it at the start of each conversation._

    ## User Preferences

    *(Learned preferences will be recorded here)*

    ## Key Facts

    *(Important facts about the user and their projects)*

    ## Patterns & Conventions

    *(Recurring patterns, coding conventions, workflow preferences)*
    """
}
