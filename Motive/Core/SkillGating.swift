//
//  SkillGating.swift
//  Motive
//
//  OpenClaw-style gating rules for skills.
//

import Foundation

enum SkillGating {
    static func evaluate(
        entry: SkillEntry,
        config: SkillsConfig,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        platform: String = SkillPlatform.current
    ) -> SkillEligibility {
        var reasons: [String] = []
        let skillKey = resolveSkillKey(entry)
        let skillConfig = config.entries[skillKey] ?? config.entries[entry.name]

        // Check enabled/disabled state
        // Priority: 1. User explicit config > 2. metadata.defaultEnabled > 3. system skill check
        if let explicitEnabled = skillConfig?.enabled {
            // User has explicitly set enabled state
            if !explicitEnabled {
                reasons.append("disabled")
                return SkillEligibility(isEligible: false, reasons: reasons)
            }
        } else {
            // Use metadata.defaultEnabled if present
            // System skills are enabled by default
            let isSystemSkill = SkillManager.systemSkillIds.contains(entry.name)
            let defaultEnabled = entry.metadata?.defaultEnabled ?? isSystemSkill
            if !defaultEnabled {
                reasons.append("disabled_by_default")
                return SkillEligibility(isEligible: false, reasons: reasons)
            }
        }

        if entry.source == .bundled, !isBundledAllowed(entry: entry, config: config) {
            reasons.append("bundled_not_allowed")
            return SkillEligibility(isEligible: false, reasons: reasons)
        }

        if let osList = entry.metadata?.os, !osList.isEmpty, !osList.contains(platform) {
            reasons.append("os_mismatch")
            return SkillEligibility(isEligible: false, reasons: reasons)
        }

        if entry.metadata?.always == true {
            return SkillEligibility(isEligible: true, reasons: [])
        }

        if let requires = entry.metadata?.requires {
            if !requires.bins.isEmpty {
                for bin in requires.bins where !hasBinary(bin) {
                    reasons.append("missing_bin:\(bin)")
                }
            }

            if !requires.anyBins.isEmpty {
                let hasAny = requires.anyBins.contains { hasBinary($0) }
                if !hasAny {
                    reasons.append("missing_any_bin")
                }
            }

            if !requires.env.isEmpty {
                for envName in requires.env {
                    if environment[envName]?.isEmpty == false {
                        continue
                    }
                    if let configEnv = skillConfig?.env[envName], !configEnv.isEmpty {
                        continue
                    }
                    if let apiKey = skillConfig?.apiKey,
                       !apiKey.isEmpty,
                       entry.metadata?.primaryEnv == envName
                    {
                        continue
                    }
                    reasons.append("missing_env:\(envName)")
                }
            }

            if !requires.config.isEmpty {
                for configPath in requires.config where !isConfigPathTruthy(configPath, entryConfig: skillConfig) {
                    reasons.append("missing_config:\(configPath)")
                }
            }
        }

        return SkillEligibility(isEligible: reasons.isEmpty, reasons: reasons)
    }

    static func resolveSkillKey(_ entry: SkillEntry) -> String {
        if let key = entry.metadata?.skillKey, !key.isEmpty {
            return key
        }
        return entry.name
    }

    private static func isBundledAllowed(entry: SkillEntry, config: SkillsConfig) -> Bool {
        let allowlist = config.allowBundled.map { $0.lowercased() }.filter { !$0.isEmpty }
        if allowlist.isEmpty {
            return true
        }
        let skillKey = resolveSkillKey(entry).lowercased()
        return allowlist.contains(skillKey) || allowlist.contains(entry.name.lowercased())
    }

    private static func hasBinary(_ bin: String) -> Bool {
        // Use CommandRunner's effectivePaths which includes common tool locations
        // GUI apps don't inherit shell PATH, so we need extended paths
        let paths = CommandRunner.effectivePaths()
        for path in paths {
            let candidate = (path as NSString).appendingPathComponent(bin)
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return true
            }
        }
        return false
    }

    private static func isConfigPathTruthy(_ path: String, entryConfig: SkillEntryConfig?) -> Bool {
        guard let value = entryConfig?.config[path]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else {
            return false
        }
        let lower = value.lowercased()
        return !(lower == "false" || lower == "0" || lower == "no")
    }

    // MARK: - Status Building

    static func buildStatus(
        entry: SkillEntry,
        config: SkillsConfig,
        commandRunner: CommandRunnerProtocol,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        platform: String = SkillPlatform.current
    ) -> SkillStatusEntry {
        let eligibility = evaluate(entry: entry, config: config, environment: environment, platform: platform)
        let missing = detectMissingDeps(entry: entry, commandRunner: commandRunner, config: config, environment: environment)
        let installOptions = resolveInstallOptions(entry: entry, commandRunner: commandRunner, platform: platform)
        let skillKey = resolveSkillKey(entry)
        let entryConfig = config.entries[skillKey] ?? config.entries[entry.name]

        // Determine disabled state using priority:
        // 1. User explicit config > 2. metadata.defaultEnabled > 3. system skill check
        let disabled: Bool
        if let explicitEnabled = entryConfig?.enabled {
            disabled = !explicitEnabled
        } else {
            // Use metadata.defaultEnabled if present
            // Otherwise, system skills are enabled by default
            let isSystemSkill = SkillManager.systemSkillIds.contains(entry.name)
            let defaultEnabled = entry.metadata?.defaultEnabled ?? isSystemSkill
            disabled = !defaultEnabled
        }

        return SkillStatusEntry(
            entry: entry,
            eligible: eligibility.isEligible,
            disabled: disabled,
            missing: missing,
            installOptions: installOptions
        )
    }

    static func detectMissingDeps(
        entry: SkillEntry,
        commandRunner: CommandRunnerProtocol,
        config: SkillsConfig,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> SkillMissingDeps {
        var missing = SkillMissingDeps()
        let skillKey = resolveSkillKey(entry)
        let skillConfig = config.entries[skillKey] ?? config.entries[entry.name]

        guard let requires = entry.metadata?.requires else {
            return missing
        }

        // Check bins
        missing.bins = requires.bins.filter { !commandRunner.hasBinary($0) }

        // Check env
        for envName in requires.env {
            if environment[envName]?.isEmpty == false {
                continue
            }
            if let configEnv = skillConfig?.env[envName], !configEnv.isEmpty {
                continue
            }
            if let apiKey = skillConfig?.apiKey,
               !apiKey.isEmpty,
               entry.metadata?.primaryEnv == envName
            {
                continue
            }
            missing.env.append(envName)
        }

        // Check config
        for configPath in requires.config {
            if !isConfigPathTruthy(configPath, entryConfig: skillConfig) {
                missing.config.append(configPath)
            }
        }

        return missing
    }

    static func resolveInstallOptions(
        entry: SkillEntry,
        commandRunner: CommandRunnerProtocol,
        platform: String = SkillPlatform.current
    ) -> [SkillInstallOption] {
        guard let installSpecs = entry.metadata?.install else { return [] }

        return installSpecs.enumerated().compactMap { index, spec in
            // Check OS match
            if let osList = spec.os, !osList.isEmpty, !osList.contains(platform) {
                return nil
            }

            let id = spec.id ?? "\(spec.kind.rawValue)-\(index)"
            let label = spec.label ?? "Install via \(spec.kind.rawValue)"
            let available = isInstallerAvailable(spec.kind, commandRunner: commandRunner)

            return SkillInstallOption(id: id, label: label, kind: spec.kind, available: available)
        }
    }

    private static func isInstallerAvailable(_ kind: InstallKind, commandRunner: CommandRunnerProtocol) -> Bool {
        switch kind {
        case .brew:
            commandRunner.hasBinary("brew")
        case .node:
            commandRunner.hasBinary("npm") || commandRunner.hasBinary("pnpm")
        case .go:
            commandRunner.hasBinary("go")
        case .uv:
            commandRunner.hasBinary("uv")
        case .apt:
            commandRunner.hasBinary("apt")
        case .download:
            true
        }
    }
}

enum SkillPlatform {
    static var current: String {
        #if os(macOS)
            return "darwin"
        #elseif os(Linux)
            return "linux"
        #elseif os(Windows)
            return "win32"
        #else
            return "unknown"
        #endif
    }
}
