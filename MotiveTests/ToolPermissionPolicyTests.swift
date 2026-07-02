import Foundation
@testable import Motive
import Testing

// MARK: - ToolPermission Type Tests

struct ToolPermissionTypeTests {

    @Test func allToolPermissionCasesExist() {
        let all = ToolPermission.allCases
        #expect(all.contains(.edit))
        #expect(all.contains(.bash))
        #expect(all.contains(.read))
        #expect(all.contains(.glob))
        #expect(all.contains(.grep))
        #expect(all.contains(.list))
        #expect(all.contains(.task))
        #expect(all.contains(.webfetch))
        #expect(all.contains(.websearch))
        #expect(all.contains(.externalDirectory))
    }

    @Test func toolPermissionRawValues() {
        #expect(ToolPermission.edit.rawValue == "edit")
        #expect(ToolPermission.bash.rawValue == "bash")
        #expect(ToolPermission.externalDirectory.rawValue == "external_directory")
    }

    @Test func toolPermissionDisplayNames() {
        #expect(ToolPermission.edit.displayName == "Edit")
        #expect(ToolPermission.bash.displayName == "Bash")
        #expect(ToolPermission.externalDirectory.displayName == "External Directory")
    }

    @Test func toolPermissionRiskLevels() {
        #expect(ToolPermission.bash.riskLevel == .high)
        #expect(ToolPermission.edit.riskLevel == .medium)
        #expect(ToolPermission.read.riskLevel == .low)
        #expect(ToolPermission.glob.riskLevel == .low)
    }

    @Test func primaryToolsAreCorrect() {
        #expect(ToolPermission.edit.isPrimary == true)
        #expect(ToolPermission.bash.isPrimary == true)
        #expect(ToolPermission.read.isPrimary == true)
        #expect(ToolPermission.externalDirectory.isPrimary == true)
        #expect(ToolPermission.glob.isPrimary == false)
        #expect(ToolPermission.grep.isPrimary == false)
        #expect(ToolPermission.websearch.isPrimary == false)
    }
}

// MARK: - Permission Action Tests

struct PermissionActionTests {

    @Test func allActionCases() {
        let all = PermissionAction.allCases
        #expect(all.count == 3)
        #expect(all.contains(.allow))
        #expect(all.contains(.ask))
        #expect(all.contains(.deny))
    }

    @Test func actionRawValues() {
        #expect(PermissionAction.allow.rawValue == "allow")
        #expect(PermissionAction.ask.rawValue == "ask")
        #expect(PermissionAction.deny.rawValue == "deny")
    }

    @Test func actionDisplayNames() {
        #expect(PermissionAction.allow.displayName == "Allow")
        #expect(PermissionAction.ask.displayName == "Ask")
        #expect(PermissionAction.deny.displayName == "Deny")
    }
}

// MARK: - Risk Level Tests

struct RiskLevelTests {

    @Test func riskLevelOrdering() {
        #expect(RiskLevel.low < RiskLevel.medium)
        #expect(RiskLevel.medium < RiskLevel.high)
        #expect(RiskLevel.high < RiskLevel.critical)
    }

    @Test func riskLevelDisplayNames() {
        #expect(RiskLevel.low.displayName == "Low")
        #expect(RiskLevel.medium.displayName == "Medium")
        #expect(RiskLevel.high.displayName == "High")
        #expect(RiskLevel.critical.displayName == "Critical")
    }
}

// MARK: - ToolPermissionRule Tests

struct ToolPermissionRuleTests {

    @Test func ruleInitialization() {
        let rule = ToolPermissionRule(pattern: "*.ts", action: .allow, description: "TypeScript files")
        #expect(rule.pattern == "*.ts")
        #expect(rule.action == .allow)
        #expect(rule.description == "TypeScript files")
    }

    @Test func ruleEquality() {
        let id = UUID()
        let rule1 = ToolPermissionRule(id: id, pattern: "*.ts", action: .allow)
        let rule2 = ToolPermissionRule(id: id, pattern: "*.ts", action: .allow)
        #expect(rule1 == rule2)
    }

    @Test func ruleInequality() {
        let rule1 = ToolPermissionRule(pattern: "*.ts", action: .allow)
        let rule2 = ToolPermissionRule(pattern: "*.ts", action: .deny)
        #expect(rule1 != rule2)
    }

    @Test func ruleCodable() throws {
        let rule = ToolPermissionRule(pattern: "git *", action: .allow, description: "Git commands")
        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(ToolPermissionRule.self, from: data)
        #expect(decoded.pattern == rule.pattern)
        #expect(decoded.action == rule.action)
        #expect(decoded.description == rule.description)
    }
}

// MARK: - ToolPermissionConfig Tests

struct ToolPermissionConfigTests {

    @Test func configInitWithDefaults() {
        let config = ToolPermissionConfig(tool: .edit, defaultAction: .ask)
        #expect(config.tool == .edit)
        #expect(config.defaultAction == .ask)
        #expect(config.rules.isEmpty)
    }

    @Test func configInitWithRules() {
        let rules = [
            ToolPermissionRule(pattern: "*.ts", action: .allow),
            ToolPermissionRule(pattern: "/System/**", action: .deny),
        ]
        let config = ToolPermissionConfig(tool: .bash, defaultAction: .ask, rules: rules)
        #expect(config.rules.count == 2)
    }

    @Test func configCodable() throws {
        let config = ToolPermissionConfig(
            tool: .bash,
            defaultAction: .ask,
            rules: [
                ToolPermissionRule(pattern: "git *", action: .allow, description: "Git")
            ]
        )
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ToolPermissionConfig.self, from: data)
        #expect(decoded.tool == .bash)
        #expect(decoded.defaultAction == .ask)
        #expect(decoded.rules.count == 1)
        #expect(decoded.rules[0].pattern == "git *")
    }
}

// MARK: - Default Configs Tests

@MainActor
struct DefaultConfigsTests {

    @Test func defaultConfigsExistForAllTools() {
        let defaults = ToolPermissionPolicy.defaultConfigs()
        for tool in ToolPermission.allCases {
            #expect(defaults[tool] != nil, "Missing default config for \(tool.rawValue)")
        }
    }

    @Test func editDefaultsToAsk() {
        let defaults = ToolPermissionPolicy.defaultConfigs()
        #expect(defaults[.edit]?.defaultAction == .ask)
    }

    @Test func bashDefaultsToAskWithAllowRules() {
        let defaults = ToolPermissionPolicy.defaultConfigs()
        let bashConfig = defaults[.bash]
        #expect(bashConfig?.defaultAction == .ask)
        #expect(bashConfig?.rules.isEmpty == false)
        // Should have allow rules for git, npm, yarn, pnpm
        let allowedPatterns = bashConfig?.rules.filter { $0.action == .allow }.map(\.pattern) ?? []
        #expect(allowedPatterns.contains("git *"))
        #expect(allowedPatterns.contains("npm *"))
    }

    @Test func readDefaultsToAllow() {
        let defaults = ToolPermissionPolicy.defaultConfigs()
        #expect(defaults[.read]?.defaultAction == .allow)
    }

    @Test func lowRiskToolsDefaultToAllow() {
        let defaults = ToolPermissionPolicy.defaultConfigs()
        #expect(defaults[.glob]?.defaultAction == .allow)
        #expect(defaults[.grep]?.defaultAction == .allow)
        #expect(defaults[.list]?.defaultAction == .allow)
        #expect(defaults[.webfetch]?.defaultAction == .allow)
        #expect(defaults[.websearch]?.defaultAction == .allow)
    }
}

// MARK: - OpenCode Permission Rules Generation

@MainActor
struct PermissionRulesGenerationTests {

    @Test func simpleToolGeneratesStringValue() {
        // A tool with no custom rules should produce a simple string like "allow"
        let config = ToolPermissionConfig(tool: .read, defaultAction: .allow)
        // Test the format: when no rules, output is just the action string
        let rules = generateRulesForConfig(config, protectedRules: [])
        if let stringValue = rules as? String {
            #expect(stringValue == "allow")
        } else {
            Issue.record("Expected simple string value for tool with no rules")
        }
    }

    @Test func toolWithRulesGeneratesPatternDict() {
        let config = ToolPermissionConfig(
            tool: .bash,
            defaultAction: .ask,
            rules: [
                ToolPermissionRule(pattern: "git *", action: .allow),
            ]
        )
        let rules = generateRulesForConfig(config, protectedRules: [])
        if let dict = rules as? [String: String] {
            #expect(dict["git *"] == "allow")
            #expect(dict["*"] == "ask")
        } else {
            Issue.record("Expected dictionary value for tool with rules")
        }
    }

    @Test func protectedRulesAreDeny() {
        let config = ToolPermissionConfig(tool: .edit, defaultAction: .allow)
        let protectedRules: [(pattern: String, action: PermissionAction)] = [
            ("/System/**", .deny),
            ("/usr/**", .deny),
        ]
        let rules = generateRulesForConfig(config, protectedRules: protectedRules)
        if let dict = rules as? [String: String] {
            #expect(dict["/System/**"] == "deny")
            #expect(dict["/usr/**"] == "deny")
            #expect(dict["*"] == "allow")
        } else {
            Issue.record("Expected dictionary with protected rules")
        }
    }

    /// Helper to simulate the rule generation logic from ToolPermissionPolicy
    private func generateRulesForConfig(
        _ config: ToolPermissionConfig,
        protectedRules: [(pattern: String, action: PermissionAction)]
    ) -> Any {
        if config.rules.isEmpty, protectedRules.isEmpty {
            return config.defaultAction.rawValue
        }

        var patternRules: [String: String] = [:]
        for rule in config.rules {
            patternRules[rule.pattern] = rule.action.rawValue
        }
        for protected in protectedRules {
            patternRules[protected.pattern] = protected.action.rawValue
        }
        patternRules["*"] = config.defaultAction.rawValue
        return patternRules
    }
}
