import Foundation
@testable import Motive
import Testing

/// Tests that the refactored SystemPromptBuilder output is clean of legacy MCP references
/// and correctly references the native question tool.
@MainActor
@Suite("SystemPromptBuilder Cleanup")
struct SystemPromptBuilderTests {

    // MARK: - Legacy Cleanup

    @Test("prompt must NOT contain AskUserQuestion")
    func noAskUserQuestion() {
        let builder = SystemPromptBuilder()
        let prompt = builder.build()
        #expect(
            !prompt.contains("AskUserQuestion"),
            "Prompt should not reference legacy AskUserQuestion MCP tool"
        )
    }

    @Test("prompt must NOT contain question DISABLED")
    func noQuestionDisabled() {
        let builder = SystemPromptBuilder()
        let prompt = builder.build()
        let lower = prompt.lowercased()
        #expect(
            !lower.contains("question") || !lower.contains("disabled") ||
                !lower.contains("question tool is disabled"),
            "Prompt should not contain 'question DISABLED' references"
        )
        // More specific check
        #expect(!prompt.contains("DISABLED"), "Prompt should not contain DISABLED keyword")
    }

    @Test("prompt must NOT contain request_file_permission")
    func noRequestFilePermission() {
        let builder = SystemPromptBuilder()
        let prompt = builder.build()
        #expect(
            !prompt.contains("request_file_permission"),
            "Prompt should not reference legacy file permission MCP tool"
        )
    }

    @Test("prompt must NOT contain built-in question tool is DISABLED")
    func noBuiltInQuestionDisabled() {
        let builder = SystemPromptBuilder()
        let prompt = builder.build()
        #expect(
            !prompt.contains("built-in question tool is DISABLED"),
            "Prompt should not contain legacy question disable instruction"
        )
    }

    @Test("prompt must NOT reference ask-user-question skill")
    func noAskUserQuestionSkill() {
        let builder = SystemPromptBuilder()
        let prompt = builder.build()
        #expect(
            !prompt.contains("ask-user-question"),
            "Prompt should not reference deprecated ask-user-question skill"
        )
        #expect(
            !prompt.contains("ask_user_question"),
            "Prompt should not reference deprecated ask_user_question skill"
        )
    }

    // MARK: - Native Question Tool References

    @Test("prompt MUST contain question tool references")
    func hasQuestionToolReferences() {
        let builder = SystemPromptBuilder()
        let prompt = builder.build()
        #expect(
            prompt.contains("question` tool") || prompt.contains("question tool"),
            "Prompt should reference the question tool"
        )
    }

    @Test("prompt clarifies question is a tool not a command")
    func questionIsToolNotCommand() {
        let builder = SystemPromptBuilder()
        let prompt = builder.build()
        #expect(
            prompt.contains("NOT a shell command"),
            "Prompt should clarify question is not a shell command"
        )
        #expect(
            prompt.contains("NOT a skill"),
            "Prompt should clarify question is not a skill"
        )
    }

    @Test("prompt MUST contain instructions for options")
    func hasOptionsInstructions() {
        let builder = SystemPromptBuilder()
        let prompt = builder.build()
        #expect(
            prompt.contains("options") || prompt.contains("Options"),
            "Prompt should mention options for question tool"
        )
    }

    @Test("prompt MUST contain options reference")
    func hasOptionsReference() {
        let builder = SystemPromptBuilder()
        let prompt = builder.build()
        #expect(
            prompt.contains("options") || prompt.contains("Options"),
            "Prompt should mention options for question tool"
        )
    }

    // MARK: - Section Structure

    @Test("prompt contains identity section")
    func hasIdentitySection() {
        let builder = SystemPromptBuilder()
        let prompt = builder.build()
        #expect(prompt.contains("<identity>"), "Prompt should contain identity section")
        #expect(prompt.contains("</identity>"), "Prompt should close identity section")
    }

    @Test("prompt contains environment section")
    func hasEnvironmentSection() {
        let builder = SystemPromptBuilder()
        let prompt = builder.build()
        #expect(prompt.contains("<environment>"), "Prompt should contain environment section")
        #expect(prompt.contains("</environment>"), "Prompt should close environment section")
    }

    @Test("prompt contains communication section")
    func hasCommunicationSection() {
        let builder = SystemPromptBuilder()
        let prompt = builder.build()
        #expect(prompt.contains("<communication>"), "Prompt should contain communication section")
        #expect(prompt.contains("</communication>"), "Prompt should close communication section")
    }

    @Test("prompt contains behavior section")
    func hasBehaviorSection() {
        let builder = SystemPromptBuilder()
        let prompt = builder.build()
        #expect(prompt.contains("<behavior>"), "Prompt should contain behavior section")
        #expect(prompt.contains("</behavior>"), "Prompt should close behavior section")
    }

    @Test("prompt contains examples section")
    func hasExamplesSection() {
        let builder = SystemPromptBuilder()
        let prompt = builder.build()
        #expect(prompt.contains("<examples>"), "Prompt should contain examples section")
        #expect(prompt.contains("</examples>"), "Prompt should close examples section")
    }

    // MARK: - Communication Guidelines

    @Test("prompt distinguishes conversation vs decision")
    func distinguishesConversationVsDecision() {
        let builder = SystemPromptBuilder()
        let prompt = builder.build()
        #expect(prompt.contains("Conversation"), "Prompt should mention conversation")
        #expect(
            prompt.contains("Decision") || prompt.contains("decision"),
            "Prompt should mention decisions"
        )
    }

    @Test("prompt includes working directory when provided")
    func includesWorkingDirectory() {
        let builder = SystemPromptBuilder()
        let prompt = builder.build(workingDirectory: "/Users/test/project")
        #expect(
            prompt.contains("/Users/test/project"),
            "Prompt should include the working directory when provided"
        )
    }

    @Test("prompt omits working directory when nil")
    func omitsWorkingDirectoryWhenNil() {
        let builder = SystemPromptBuilder()
        let prompt = builder.build(workingDirectory: nil)
        #expect(
            !prompt.contains("Working Directory:"),
            "Prompt should not include working directory placeholder when nil"
        )
    }

    // Skills are now synced to OpenCode's skill directory and discovered
    // natively — no system prompt listing or formatAvailableSkills needed.
}
