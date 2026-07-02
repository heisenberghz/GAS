@testable import Motive
import Testing

struct SkillMcpConfigTests {
    @Test @MainActor func buildsMcpEntriesOnlyForMcpSkills() {
        let registry = SkillRegistry.shared
        let mcpEntry = SkillEntry(
            name: "slack",
            description: "Slack",
            filePath: "/tmp/slack/SKILL.md",
            source: .managed,
            frontmatter: SkillFrontmatter(name: "slack", description: "Slack"),
            metadata: nil,
            wiring: .mcp(SkillMcpSpec(type: "local", command: ["/bin/echo", "ok"], environment: [:], timeoutMs: 1000, enabled: true)),
            eligibility: SkillEligibility(isEligible: true, reasons: [])
        )
        let binEntry = SkillEntry(
            name: "bin-tool",
            description: "Bin",
            filePath: "/tmp/bin/SKILL.md",
            source: .managed,
            frontmatter: SkillFrontmatter(name: "bin-tool", description: "Bin"),
            metadata: nil,
            wiring: .bin(SkillToolSpec(command: "/bin/ls", args: [])),
            eligibility: SkillEligibility(isEligible: true, reasons: [])
        )

        registry.setEntriesForTesting([mcpEntry, binEntry])
        let mcp = registry.buildMcpConfigEntries()

        #expect(mcp["slack"] != nil)
        #expect(mcp["bin-tool"] == nil)
    }
}
