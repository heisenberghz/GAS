@testable import Motive
import Testing

@MainActor
struct SkillGatingTests {
    @Test func disabledSkillIsExcluded() async {
        let entry = makeEntry(name: "slack", source: .bundled)
        var config = SkillsConfig()
        config.entries["slack"] = SkillEntryConfig(enabled: false)

        let result = await SkillGating.evaluate(entry: entry, config: config, environment: [:])
        #expect(result.isEligible == false)
        #expect(result.reasons.contains("disabled"))
    }

    @Test func allowBundledBlocksWhenNotListed() async {
        let entry = makeEntry(name: "some-skill", source: .bundled)
        var config = SkillsConfig()
        config.allowBundled = ["another-skill"]

        let result = await SkillGating.evaluate(entry: entry, config: config, environment: [:])
        #expect(result.isEligible == false)
        #expect(result.reasons.contains("bundled_not_allowed"))
    }

    @Test func osMismatchExcludes() async {
        var entry = makeEntry(name: "linux-only", source: .managed)
        entry.metadata = SkillMetadata(always: false, os: ["linux"], primaryEnv: nil, emoji: nil, homepage: nil, requires: nil, skillKey: nil)

        let result = await SkillGating.evaluate(entry: entry, config: SkillsConfig(), environment: [:], platform: "darwin")
        #expect(result.isEligible == false)
        #expect(result.reasons.contains("os_mismatch"))
    }

    @Test func requiresEnvIsSatisfiedByConfig() async {
        var entry = makeEntry(name: "slack", source: .managed)
        var req = SkillRequirements()
        req.env = ["SLACK_TOKEN"]
        entry.metadata = SkillMetadata(always: false, os: [], primaryEnv: "SLACK_TOKEN", emoji: nil, homepage: nil, requires: req, skillKey: nil)

        var config = SkillsConfig()
        config.entries["slack"] = SkillEntryConfig(enabled: true, env: ["SLACK_TOKEN": "abc"], apiKey: nil, config: [:])

        let result = await SkillGating.evaluate(entry: entry, config: config, environment: [:])
        #expect(result.isEligible == true)
    }

    @Test func alwaysBypassesRequires() async {
        var entry = makeEntry(name: "always", source: .managed)
        var req = SkillRequirements()
        req.env = ["MISSING_ENV"]
        entry.metadata = SkillMetadata(always: true, os: [], primaryEnv: nil, emoji: nil, homepage: nil, requires: req, skillKey: nil)

        let result = await SkillGating.evaluate(entry: entry, config: SkillsConfig(), environment: [:])
        #expect(result.isEligible == true)
    }

    @Test func requiresConfigChecksTruthy() async {
        var entry = makeEntry(name: "config-skill", source: .managed)
        var req = SkillRequirements()
        req.config = ["feature.enabled"]
        entry.metadata = SkillMetadata(always: false, os: [], primaryEnv: nil, emoji: nil, homepage: nil, requires: req, skillKey: nil)

        var config = SkillsConfig()
        config.entries["config-skill"] = SkillEntryConfig(enabled: true, env: [:], apiKey: nil, config: ["feature.enabled": "true"])

        let result = await SkillGating.evaluate(entry: entry, config: config, environment: [:])
        #expect(result.isEligible == true)
    }

    @Test func requiresAnyBinsFailsWhenMissing() async {
        var entry = makeEntry(name: "any-bin", source: .managed)
        var req = SkillRequirements()
        req.anyBins = ["definitely_missing_bin_123"]
        entry.metadata = SkillMetadata(always: false, os: [], primaryEnv: nil, emoji: nil, homepage: nil, requires: req, skillKey: nil)

        let result = await SkillGating.evaluate(entry: entry, config: SkillsConfig(), environment: [:])
        #expect(result.isEligible == false)
        #expect(result.reasons.contains("missing_any_bin"))
    }
}

private func makeEntry(name: String, source: SkillSource) -> SkillEntry {
    SkillEntry(
        name: name,
        description: "\(name) desc",
        filePath: "/tmp/\(name)/SKILL.md",
        source: source,
        frontmatter: SkillFrontmatter(name: name, description: "\(name) desc"),
        metadata: nil,
        wiring: .none,
        eligibility: SkillEligibility(isEligible: true, reasons: [])
    )
}
