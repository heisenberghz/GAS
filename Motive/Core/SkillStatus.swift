//
//  SkillStatus.swift
//  Motive
//
//  Status types for skill installation and dependency tracking.
//

import Foundation

// MARK: - Status Entry

struct SkillStatusEntry: Identifiable, Equatable {
    var id: String {
        entry.id
    }

    var entry: SkillEntry
    var eligible: Bool
    var disabled: Bool
    var missing: SkillMissingDeps
    var installOptions: [SkillInstallOption]

    var canInstall: Bool {
        !missing.bins.isEmpty && !installOptions.isEmpty && installOptions.contains(where: \.available)
    }
}

// MARK: - Missing Dependencies

struct SkillMissingDeps: Equatable {
    var bins: [String] = []
    var env: [String] = []
    var config: [String] = []

    var isEmpty: Bool {
        bins.isEmpty && env.isEmpty && config.isEmpty
    }

    var summary: String {
        var parts: [String] = []
        if !bins.isEmpty {
            parts.append("bins: \(bins.joined(separator: ", "))")
        }
        if !env.isEmpty {
            parts.append("env: \(env.joined(separator: ", "))")
        }
        if !config.isEmpty {
            parts.append("config: \(config.joined(separator: ", "))")
        }
        return parts.joined(separator: "; ")
    }
}

// MARK: - Install Option

struct SkillInstallOption: Identifiable, Equatable {
    var id: String
    var label: String
    var kind: InstallKind
    var available: Bool // Whether the installer tool is available (e.g., brew exists)

    var displayLabel: String {
        if available {
            label
        } else {
            "\(label) (\(kind.rawValue) not found)"
        }
    }
}
