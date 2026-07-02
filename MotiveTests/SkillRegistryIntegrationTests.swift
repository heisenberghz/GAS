//
//  SkillRegistryIntegrationTests.swift
//  MotiveTests
//
//  Integration tests for SkillRegistry using mock config providers.
//

import Foundation
@testable import Motive
import Testing

@MainActor
struct SkillRegistryIntegrationTests {

    private class MockSkillConfigProvider: SkillConfigProvider {
        var skillsSystemEnabled: Bool = true
        var skillsConfig: SkillsConfig = .init()
        var skillsManagedDirectoryURL: URL?
        var currentProjectURL: URL = .init(fileURLWithPath: "/tmp/test-project")
    }

    private func makeEntry(
        name: String,
        source: SkillSource = .bundled,
        defaultEnabled: Bool? = nil,
        skillKey: String? = nil
    ) -> SkillEntry {
        let metadata = SkillMetadata(
            always: false,
            os: [],
            primaryEnv: nil,
            emoji: nil,
            homepage: nil,
            requires: nil,
            skillKey: skillKey,
            defaultEnabled: defaultEnabled
        )
        return SkillEntry(
            name: name,
            description: "\(name) desc",
            filePath: "/tmp/\(name)/SKILL.md",
            source: source,
            frontmatter: SkillFrontmatter(name: name, description: "\(name) desc"),
            metadata: metadata,
            wiring: .none,
            eligibility: SkillEligibility(isEligible: true, reasons: [])
        )
    }

    @Test func refresh_withDisabledSystem_clearsEntries() {
        let registry = SkillRegistry.shared
        let provider = MockSkillConfigProvider()
        provider.skillsSystemEnabled = false

        registry.setConfigProvider(provider)

        #expect(registry.entries.isEmpty)
    }

    @Test func isSkillEnabled_explicitConfig_overridesDefault() {
        let registry = SkillRegistry.shared
        let provider = MockSkillConfigProvider()
        provider.skillsSystemEnabled = true

        // Skill has defaultEnabled = true in metadata
        let entry = makeEntry(name: "test-skill", defaultEnabled: true)

        // But user explicitly disables it
        var config = SkillsConfig()
        config.entries["test-skill"] = SkillEntryConfig(enabled: false)
        provider.skillsConfig = config

        registry.setConfigProvider(provider)
        registry.setEntriesForTesting([entry])

        #expect(registry.isSkillEnabled(entry) == false)
    }

    @Test func isSkillEnabled_noConfig_usesDefault() {
        let registry = SkillRegistry.shared
        let provider = MockSkillConfigProvider()
        provider.skillsSystemEnabled = true
        registry.setConfigProvider(provider)

        let enabledEntry = makeEntry(name: "enabled-skill", defaultEnabled: true)
        let disabledEntry = makeEntry(name: "disabled-skill", defaultEnabled: false)
        let noDefaultEntry = makeEntry(name: "no-default-skill")

        registry.setEntriesForTesting([enabledEntry, disabledEntry, noDefaultEntry])

        #expect(registry.isSkillEnabled(enabledEntry) == true)
        #expect(registry.isSkillEnabled(disabledEntry) == false)
        #expect(registry.isSkillEnabled(noDefaultEntry) == false)
    }

    @Test func environmentOverrides_mergesApiKeys() {
        let registry = SkillRegistry.shared
        let provider = MockSkillConfigProvider()
        provider.skillsSystemEnabled = true

        var entry = makeEntry(name: "api-skill", defaultEnabled: true)
        entry.metadata = SkillMetadata(
            always: false,
            os: [],
            primaryEnv: "API_KEY",
            emoji: nil,
            homepage: nil,
            requires: nil,
            skillKey: nil,
            defaultEnabled: true
        )

        var config = SkillsConfig()
        config.entries["api-skill"] = SkillEntryConfig(
            enabled: true,
            env: ["EXTRA_VAR": "extra_value"],
            apiKey: "test-api-key",
            config: [:]
        )
        provider.skillsConfig = config

        registry.setConfigProvider(provider)
        registry.setEntriesForTesting([entry])

        let overrides = registry.environmentOverrides()
        #expect(overrides["EXTRA_VAR"] == "extra_value")
        #expect(overrides["API_KEY"] == "test-api-key")
    }

    @Test func syncSkillsToDirectory_writesEnabledSkills() throws {
        try withTempDirectory { tempDir in
            let registry = SkillRegistry.shared
            let provider = MockSkillConfigProvider()
            provider.skillsSystemEnabled = true

            // Create a real SKILL.md file for the entry
            let skillDir = tempDir.appendingPathComponent("source-skill")
            try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
            let skillFile = skillDir.appendingPathComponent("SKILL.md")
            try "# Test Skill\nThis is a test.".write(to: skillFile, atomically: true, encoding: .utf8)

            var entry = makeEntry(name: "sync-test", defaultEnabled: true)
            entry.filePath = skillFile.path

            var config = SkillsConfig()
            config.entries["sync-test"] = SkillEntryConfig(enabled: true)
            provider.skillsConfig = config

            registry.setConfigProvider(provider)
            registry.setEntriesForTesting([entry])

            let destDir = tempDir.appendingPathComponent("skills-dest")
            registry.syncSkillsToDirectory(destDir)

            let destFile = destDir.appendingPathComponent("sync-test/SKILL.md")
            #expect(FileManager.default.fileExists(atPath: destFile.path))
        }
    }
}
