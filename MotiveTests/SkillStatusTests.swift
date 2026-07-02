@testable import Motive
import Testing

struct SkillStatusTests {

    @Test func detectsMissingBins() {
        let mock = MockCommandRunner()
        // Don't stub any binaries, so all will be missing

        var entry = makeEntry(name: "test-skill")
        var req = SkillRequirements()
        req.bins = ["missing-bin-xyz"]
        entry.metadata = SkillMetadata(requires: req)

        let missing = SkillGating.detectMissingDeps(
            entry: entry,
            commandRunner: mock,
            config: SkillsConfig()
        )

        #expect(missing.bins.contains("missing-bin-xyz"))
    }

    @Test func detectsMissingEnv() {
        let mock = MockCommandRunner()

        var entry = makeEntry(name: "test-skill")
        var req = SkillRequirements()
        req.env = ["MISSING_ENV_VAR"]
        entry.metadata = SkillMetadata(requires: req)

        let missing = SkillGating.detectMissingDeps(
            entry: entry,
            commandRunner: mock,
            config: SkillsConfig(),
            environment: [:] // Empty environment
        )

        #expect(missing.env.contains("MISSING_ENV_VAR"))
    }

    @Test func envSatisfiedByConfigNotMissing() {
        let mock = MockCommandRunner()

        var entry = makeEntry(name: "test-skill")
        var req = SkillRequirements()
        req.env = ["API_KEY"]
        entry.metadata = SkillMetadata(requires: req)

        var config = SkillsConfig()
        config.entries["test-skill"] = SkillEntryConfig(env: ["API_KEY": "secret"])

        let missing = SkillGating.detectMissingDeps(
            entry: entry,
            commandRunner: mock,
            config: config,
            environment: [:]
        )

        #expect(missing.env.isEmpty)
    }

    @Test func installOptionAvailableWhenBrewExists() {
        let mock = MockCommandRunner()
        mock.stubbedBinaries = ["brew"]

        var entry = makeEntry(name: "test-skill")
        entry.metadata = SkillMetadata(
            install: [SkillInstallSpec(id: "brew", kind: .brew, label: "Install via brew", formula: "gh")]
        )

        let options = SkillGating.resolveInstallOptions(
            entry: entry,
            commandRunner: mock,
            platform: "darwin"
        )

        #expect(options.count == 1)
        #expect(options.first?.available == true)
    }

    @Test func installOptionUnavailableWhenBrewMissing() {
        let mock = MockCommandRunner()
        // Don't stub brew

        var entry = makeEntry(name: "test-skill")
        entry.metadata = SkillMetadata(
            install: [SkillInstallSpec(id: "brew", kind: .brew, label: "Install via brew", formula: "gh")]
        )

        let options = SkillGating.resolveInstallOptions(
            entry: entry,
            commandRunner: mock,
            platform: "darwin"
        )

        #expect(options.count == 1)
        #expect(options.first?.available == false)
    }

    @Test func installOptionsFilteredByOS() {
        let mock = MockCommandRunner()
        mock.stubbedBinaries = ["apt"]

        var entry = makeEntry(name: "test-skill")
        entry.metadata = SkillMetadata(
            install: [SkillInstallSpec(id: "apt", kind: .apt, label: "Install via apt", os: ["linux"], package: "gh")]
        )

        let options = SkillGating.resolveInstallOptions(
            entry: entry,
            commandRunner: mock,
            platform: "darwin" // Not linux
        )

        #expect(options.isEmpty)
    }

    @Test func buildStatusCombinesAllInfo() {
        let mock = MockCommandRunner()
        mock.stubbedBinaries = ["brew"]

        var entry = makeEntry(name: "test-skill")
        var req = SkillRequirements()
        req.bins = ["missing-tool"]
        entry.metadata = SkillMetadata(
            requires: req,
            install: [SkillInstallSpec(id: "brew", kind: .brew, formula: "missing-tool")]
        )

        let status = SkillGating.buildStatus(
            entry: entry,
            config: SkillsConfig(),
            commandRunner: mock,
            platform: "darwin"
        )

        #expect(status.missing.bins.contains("missing-tool"))
        #expect(status.installOptions.count == 1)
        #expect(status.canInstall == true)
    }
}

// MARK: - Helpers

private func makeEntry(name: String) -> SkillEntry {
    SkillEntry(
        name: name,
        description: "\(name) desc",
        filePath: "/tmp/\(name)/SKILL.md",
        source: .managed,
        frontmatter: SkillFrontmatter(name: name, description: "\(name) desc"),
        metadata: nil,
        wiring: .none,
        eligibility: SkillEligibility(isEligible: true, reasons: [])
    )
}
