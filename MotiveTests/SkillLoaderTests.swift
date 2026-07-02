import Foundation
@testable import Motive
import Testing

struct SkillLoaderTests {
    @Test func mergesByPrecedence() {
        func entry(name: String, description: String, source: SkillSource) -> SkillEntry {
            SkillEntry(
                name: name,
                description: description,
                filePath: "/tmp/\(name)/SKILL.md",
                source: source,
                frontmatter: SkillFrontmatter(name: name, description: description),
                metadata: nil,
                wiring: .none,
                eligibility: SkillEligibility(isEligible: true, reasons: [])
            )
        }

        let merged = SkillLoader.mergeByPrecedence(
            extra: [entry(name: "slack", description: "extra", source: .extra)],
            bundled: [entry(name: "slack", description: "bundled", source: .bundled)],
            managed: [entry(name: "slack", description: "managed", source: .managed)],
            workspace: [entry(name: "slack", description: "workspace", source: .workspace)]
        )

        #expect(merged.count == 1)
        #expect(merged.first?.description == "workspace")
    }

    @Test func parsesFrontmatterMetadataAndWiring() throws {
        try withTempDirectory { dir in
            let skillDir = dir.appendingPathComponent("slack")
            try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)

            let skillMd = """
            ---
            name: slack
            description: Slack skill
            metadata: { "openclaw": { "requires": { "env": ["SLACK_TOKEN"], }, "primaryEnv": "SLACK_TOKEN", } }
            ---

            # Slack
            """
            try skillMd.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

            let mcp = """
            {
              "type": "local",
              "command": ["{baseDir}/bin/node", "{baseDir}/mcp.js"],
              "environment": { "PORT": "9999" },
              "timeoutMs": 5000
            }
            """
            try mcp.write(to: skillDir.appendingPathComponent("mcp.json"), atomically: true, encoding: .utf8)

            let tool = """
            {
              "command": "{baseDir}/bin/tool",
              "args": ["--flag"]
            }
            """
            try tool.write(to: skillDir.appendingPathComponent("tool.json"), atomically: true, encoding: .utf8)

            let entries = SkillLoader.loadEntries(from: dir, source: .managed)
            #expect(entries.count == 1)

            let entry = try #require(entries.first)
            #expect(entry.name == "slack")
            #expect(entry.metadata?.primaryEnv == "SLACK_TOKEN")
            #expect(entry.metadata?.requires?.env.contains("SLACK_TOKEN") == true)

            if case let .mcp(spec) = entry.wiring {
                #expect(spec.command.first?.contains(skillDir.path) == true)
                #expect(spec.timeoutMs == 5000)
            } else {
                #expect(false, "Expected mcp wiring to take precedence over tool.json")
            }
        }
    }

    @Test func parsesLicenseAndCompatibility() throws {
        try withTempDirectory { dir in
            let skillDir = dir.appendingPathComponent("test-skill")
            try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)

            let skillMd = """
            ---
            name: test-skill
            description: Test skill with all fields
            license: MIT
            compatibility: Requires docker and git
            ---

            # Test
            """
            try skillMd.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

            let entries = SkillLoader.loadEntries(from: dir, source: .managed)
            let entry = try #require(entries.first)

            #expect(entry.frontmatter.license == "MIT")
            #expect(entry.frontmatter.compatibility == "Requires docker and git")
        }
    }

    @Test func parsesAllowedTools() throws {
        try withTempDirectory { dir in
            let skillDir = dir.appendingPathComponent("test-skill")
            try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)

            let skillMd = """
            ---
            name: test-skill
            description: Test skill
            allowed-tools: Bash Read Write
            ---

            # Test
            """
            try skillMd.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

            let entries = SkillLoader.loadEntries(from: dir, source: .managed)
            let entry = try #require(entries.first)

            #expect(entry.frontmatter.allowedTools == ["Bash", "Read", "Write"])
        }
    }

    @Test func parsesInstallSpecs() throws {
        try withTempDirectory { dir in
            let skillDir = dir.appendingPathComponent("github")
            try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)

            let skillMd = """
            ---
            name: github
            description: GitHub CLI skill
            metadata: { "openclaw": { "requires": { "bins": ["gh"] }, "install": [{ "id": "brew", "kind": "brew", "formula": "gh", "label": "Install via brew" }] } }
            ---

            # GitHub
            """
            try skillMd.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

            let entries = SkillLoader.loadEntries(from: dir, source: .managed)
            let entry = try #require(entries.first)

            #expect(entry.metadata?.requires?.bins == ["gh"])
            #expect(entry.metadata?.install?.count == 1)

            let install = try #require(entry.metadata?.install?.first)
            #expect(install.id == "brew")
            #expect(install.kind == .brew)
            #expect(install.formula == "gh")
            #expect(install.label == "Install via brew")
        }
    }

    @Test func parsesMultilineMetadata() throws {
        try withTempDirectory { dir in
            let skillDir = dir.appendingPathComponent("1password")
            try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)

            // This is the exact format used by OpenClaw skills
            let skillMd = """
            ---
            name: 1password
            description: 1Password CLI skill
            metadata:
              {
                "openclaw":
                  {
                    "emoji": "🔐",
                    "requires": { "bins": ["op"] },
                    "install":
                      [
                        {
                          "id": "brew",
                          "kind": "brew",
                          "formula": "1password-cli",
                          "bins": ["op"],
                          "label": "Install 1Password CLI (brew)",
                        },
                      ],
                  },
              }
            ---

            # 1Password
            """
            try skillMd.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

            let entries = SkillLoader.loadEntries(from: dir, source: .managed)
            let entry = try #require(entries.first)

            #expect(entry.name == "1password")
            #expect(entry.metadata?.emoji == "🔐")
            #expect(entry.metadata?.requires?.bins == ["op"])
            #expect(entry.metadata?.install?.count == 1)

            let install = try #require(entry.metadata?.install?.first)
            #expect(install.id == "brew")
            #expect(install.kind == .brew)
            #expect(install.formula == "1password-cli")
        }
    }
}

private func withTempDirectory(_ body: (URL) throws -> Void) throws {
    let base = URL(fileURLWithPath: NSTemporaryDirectory())
    let dir = base.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    try body(dir)
}
