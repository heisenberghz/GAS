//
//  SkillRegistry.swift
//  Motive
//
//  Central registry for OpenClaw-style skills.
//

import Combine
import Foundation

@MainActor
final class SkillRegistry: ObservableObject {
    static let shared = SkillRegistry()

    @Published private(set) var entries: [SkillEntry] = []
    @Published private(set) var snapshotVersion: Int = 0

    private weak var configProvider: SkillConfigProvider?

    /// Backwards-compatible accessor for code that needs ConfigManager specifically
    private var configManager: ConfigManager? {
        configProvider as? ConfigManager
    }

    private var watcher: SkillWatcher?

    private init() {}

    func setConfigManager(_ manager: ConfigManager) {
        configProvider = manager
        refresh()
        configureWatcher()
    }

    func setConfigProvider(_ provider: SkillConfigProvider) {
        configProvider = provider
        refresh()
        configureWatcher()
    }

    func refresh() {
        guard let configProvider else { return }
        if !configProvider.skillsSystemEnabled {
            entries = []
            return
        }

        let config = configProvider.skillsConfig
        let extraDirs = config.load.extraDirs.map { SkillRegistry.resolveUserPath($0) }
        let managedDir = configProvider.skillsManagedDirectoryURL
        let workspaceDir = configProvider.currentProjectURL.appendingPathComponent("skills")
        let builtIns = buildBuiltInEntries(managedDir: managedDir)

        let extraEntries = extraDirs.flatMap { SkillLoader.loadEntries(from: $0, source: .extra) }
        let managedEntriesAll = managedDir.map { SkillLoader.loadEntries(from: $0, source: .managed) } ?? []
        let builtInNames = Set(builtIns.map(\.name))
        let managedEntries = managedEntriesAll.filter { !builtInNames.contains($0.name) }
        let workspaceEntries = SkillLoader.loadEntries(from: workspaceDir, source: .workspace)

        let merged = SkillLoader.mergeByPrecedence(
            extra: extraEntries,
            bundled: builtIns,
            managed: managedEntries,
            workspace: workspaceEntries
        )

        let evaluated = merged.map { entry in
            var updated = entry
            updated.eligibility = SkillGating.evaluate(entry: entry, config: config)
            return updated
        }

        entries = evaluated
        bumpSnapshot(reason: "refresh")
        configureWatcher()
    }

    #if DEBUG
        func setEntriesForTesting(_ entries: [SkillEntry]) {
            self.entries = entries
        }
    #endif

    func eligibleEntries() -> [SkillEntry] {
        entries.filter(\.eligibility.isEligible)
    }

    /// Check if a skill is enabled using the same logic as the permission whitelist:
    /// 1. User explicit config > 2. metadata.defaultEnabled > 3. false
    func isSkillEnabled(_ entry: SkillEntry) -> Bool {
        guard let configProvider else { return entry.metadata?.defaultEnabled ?? false }
        let config = configProvider.skillsConfig
        let skillKey = entry.metadata?.skillKey ?? entry.name
        let entryConfig = config.entries[skillKey] ?? config.entries[entry.name]
        if let explicitEnabled = entryConfig?.enabled {
            return explicitEnabled
        }
        return entry.metadata?.defaultEnabled ?? false
    }

    func mcpEntries() -> [SkillEntry] {
        eligibleEntries().filter {
            if case let .mcp(spec) = $0.wiring {
                return spec.enabled ?? true
            }
            return false
        }
    }

    func environmentOverrides() -> [String: String] {
        guard let configProvider else { return [:] }
        let config = configProvider.skillsConfig
        var overrides: [String: String] = [:]
        for entry in eligibleEntries() {
            let key = SkillGating.resolveSkillKey(entry)
            let entryConfig = config.entries[key] ?? config.entries[entry.name]
            if let entryConfig {
                for (envKey, value) in entryConfig.env where !value.isEmpty {
                    overrides[envKey] = value
                }
                if let apiKey = entryConfig.apiKey,
                   !apiKey.isEmpty,
                   let primaryEnv = entry.metadata?.primaryEnv,
                   overrides[primaryEnv]?.isEmpty ?? true
                {
                    overrides[primaryEnv] = apiKey
                }
            }
        }
        return overrides
    }

    /// Sync enabled skills to OpenCode's skills directory so they are natively discovered.
    ///
    /// OpenCode scans `$OPENCODE_CONFIG_DIR/skills/<name>/SKILL.md` to register skills.
    /// This method:
    ///   1. Copies SKILL.md for every enabled skill into the target directory
    ///   2. Removes directories for skills that are not enabled (prevents phantom tools)
    ///   3. Skips skills already managed by SkillManager (browser-automation etc.)
    ///
    /// After this call, OpenCode's native `skill` tool can find skills by name.
    func syncSkillsToDirectory(_ skillsDir: URL) {
        let fm = FileManager.default
        try? fm.createDirectory(at: skillsDir, withIntermediateDirectories: true)

        // Names managed by SkillManager.writeSkillFiles() — don't touch those
        let managedBySkillManager = Set(SkillManager.shared.skills.map(\.id))

        // Enabled skill names — the ground truth for what should exist on disk
        let enabledNames = Set(
            entries.filter { isSkillEnabled($0) && !managedBySkillManager.contains($0.name) }
                .map(\.name)
        )

        // 1. Write / update enabled skills
        for entry in entries where enabledNames.contains(entry.name) {
            let destDir = skillsDir.appendingPathComponent(entry.name)
            let destFile = destDir.appendingPathComponent("SKILL.md")

            // Read source SKILL.md content
            guard let content = try? String(contentsOfFile: entry.filePath, encoding: .utf8) else {
                continue
            }

            do {
                try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
                try content.write(to: destFile, atomically: true, encoding: .utf8)
            } catch {
                Log.debug("Failed to sync skill '\(entry.name)': \(error)")
            }
        }

        // 2. Remove directories for disabled / non-existent skills
        let existingDirs = (try? fm.contentsOfDirectory(atPath: skillsDir.path)) ?? []
        for dirname in existingDirs {
            // Skip SkillManager-managed skills
            guard !managedBySkillManager.contains(dirname) else { continue }
            // Skip currently enabled skills
            guard !enabledNames.contains(dirname) else { continue }
            // Skip hidden files
            guard !dirname.hasPrefix(".") else { continue }

            let dirURL = skillsDir.appendingPathComponent(dirname)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dirURL.path, isDirectory: &isDir), isDir.boolValue else { continue }

            do {
                try fm.removeItem(at: dirURL)
                Log.debug("Removed disabled skill directory: \(dirname)")
            } catch {
                Log.debug("Failed to remove skill directory '\(dirname)': \(error)")
            }
        }

        Log.config(" Synced \(enabledNames.count) skills to \(skillsDir.path)")
    }

    func buildMcpConfigEntries() -> [String: Any] {
        var mcp: [String: Any] = [:]
        for entry in mcpEntries() {
            guard case let .mcp(spec) = entry.wiring else { continue }
            let key = entry.name
            mcp[key] = [
                "type": spec.type ?? "local",
                "command": spec.command,
                "enabled": spec.enabled ?? true,
                "environment": spec.environment,
                "timeout": spec.timeoutMs ?? 10000
            ]
        }
        return mcp
    }

    // MARK: - Private

    private func buildBuiltInEntries(managedDir: URL?) -> [SkillEntry] {
        var entries: [SkillEntry] = []
        if let bundleURL = bundledSkillsURL() {
            entries.append(contentsOf: SkillLoader.loadEntries(from: bundleURL, source: .bundled))
        }
        let bundledNames = Set(entries.map(\.name))

        // Exclude bundled duplicates and capability skills (e.g. browser-automation)
        // which have their own dedicated section in Advanced settings.
        let builtIns = SkillManager.shared.skills.filter {
            !bundledNames.contains($0.id) && $0.type != .capability
        }
        let skillEntries = builtIns.map { skill in
            let skillPath: String = if let managedDir {
                managedDir
                    .appendingPathComponent(skill.id)
                    .appendingPathComponent("SKILL.md")
                    .path
            } else {
                skill.id
            }
            let frontmatter = SkillFrontmatter(
                name: skill.id,
                description: skill.description,
                metadataRaw: nil
            )
            // System skills are enabled by default
            var metadata = SkillMetadata()
            metadata.defaultEnabled = true

            return SkillEntry(
                name: skill.id,
                description: skill.description,
                filePath: skillPath,
                source: .bundled,
                frontmatter: frontmatter,
                metadata: metadata,
                wiring: .none,
                eligibility: SkillEligibility(isEligible: true, reasons: [])
            )
        }
        entries.append(contentsOf: skillEntries)
        return entries
    }

    private func configureWatcher() {
        guard let configProvider else { return }
        let config = configProvider.skillsConfig
        if !config.load.watch || !configProvider.skillsSystemEnabled {
            watcher?.stop()
            watcher = nil
            return
        }

        let debounceMs = config.load.watchDebounceMs
        let paths = watchPaths(provider: configProvider, config: config)
        if watcher == nil {
            watcher = SkillWatcher(debounceMs: debounceMs) { [weak self] _ in
                Task { @MainActor in
                    self?.refresh()
                }
            }
        }
        watcher?.startWatching(paths: paths)
    }

    private func watchPaths(provider: SkillConfigProvider, config: SkillsConfig) -> [String] {
        var paths: [String] = []
        let workspace = provider.currentProjectURL.appendingPathComponent("skills").path
        paths.append(workspace)
        if let managedDir = provider.skillsManagedDirectoryURL?.path {
            paths.append(managedDir)
        }
        let extra = config.load.extraDirs.map { SkillRegistry.resolveUserPath($0).path }
        paths.append(contentsOf: extra)
        return paths
    }

    private func bumpSnapshot(reason: String) {
        snapshotVersion = Int(Date().timeIntervalSince1970 * 1000)
        Log.debug("Skills snapshot updated (\(reason)) -> \(snapshotVersion)")
    }

    private static func resolveUserPath(_ path: String) -> URL {
        if path.hasPrefix("~") {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let expanded = home + path.dropFirst()
            return URL(fileURLWithPath: expanded)
        }
        return URL(fileURLWithPath: path)
    }

    private func bundledSkillsURL() -> URL? {
        #if DEBUG
            if let override = bundledSkillsURLOverride {
                return override
            }
        #endif
        guard let bundleURL = Bundle.main.url(forResource: "Skills", withExtension: "bundle"),
              let bundle = Bundle(url: bundleURL)
        else {
            return nil
        }
        return bundle.resourceURL
    }

    #if DEBUG
        private var bundledSkillsURLOverride: URL? {
            get { Self._bundledSkillsURLOverride }
            set { Self._bundledSkillsURLOverride = newValue }
        }

        private static var _bundledSkillsURLOverride: URL?

        func setBundledSkillsURLForTesting(_ url: URL?) {
            bundledSkillsURLOverride = url
        }
    #endif
}
