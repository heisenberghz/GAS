import Foundation
@testable import Motive
import Testing

/// Tests for SSE native question/permission event types and their
/// serialization for REST API replies.
struct NativeEventTests {

    // MARK: - QuestionRequest Parsing

    @Test func questionRequestWithSingleQuestion() async {
        let client = SSEClient()
        let json = """
        {
            "type": "question.asked",
            "properties": {
                "id": "q-single",
                "sessionID": "sess-1",
                "questions": [
                    {
                        "question": "Which framework?",
                        "options": [
                            {"label": "SwiftUI", "description": "Modern declarative UI"},
                            {"label": "UIKit", "description": "Imperative approach"}
                        ],
                        "multiple": false,
                        "custom": true
                    }
                ]
            }
        }
        """

        let event = await client.parseSSEData(json)
        guard case let .questionAsked(request) = event else {
            Issue.record("Expected questionAsked event")
            return
        }

        #expect(request.id == "q-single")
        #expect(request.sessionID == "sess-1")
        #expect(request.questions.count == 1)

        let q = request.questions[0]
        #expect(q.question == "Which framework?")
        #expect(q.options.count == 2)
        #expect(q.options[0].label == "SwiftUI")
        #expect(q.options[0].description == "Modern declarative UI")
        #expect(q.options[1].label == "UIKit")
        #expect(q.multiple == false)
        #expect(q.custom == true)
    }

    @Test func questionRequestWithMultipleQuestions() async {
        let client = SSEClient()
        let json = """
        {
            "type": "question.asked",
            "properties": {
                "id": "q-multi",
                "sessionID": "sess-1",
                "questions": [
                    {
                        "question": "First question?",
                        "options": [{"label": "A"}],
                        "multiple": false,
                        "custom": false
                    },
                    {
                        "question": "Second question?",
                        "options": [{"label": "X"}, {"label": "Y"}],
                        "multiple": true,
                        "custom": true
                    }
                ]
            }
        }
        """

        let event = await client.parseSSEData(json)
        guard case let .questionAsked(request) = event else {
            Issue.record("Expected questionAsked event")
            return
        }

        #expect(request.questions.count == 2)
        #expect(request.questions[0].question == "First question?")
        #expect(request.questions[0].custom == false)
        #expect(request.questions[1].question == "Second question?")
        #expect(request.questions[1].multiple == true)
        #expect(request.questions[1].custom == true)
    }

    @Test func questionRequestWithNoOptions() async {
        let client = SSEClient()
        let json = """
        {
            "type": "question.asked",
            "properties": {
                "id": "q-noop",
                "sessionID": "sess-1",
                "questions": [
                    {
                        "question": "What do you want?",
                        "multiple": false,
                        "custom": true
                    }
                ]
            }
        }
        """

        let event = await client.parseSSEData(json)
        guard case let .questionAsked(request) = event else {
            Issue.record("Expected questionAsked event")
            return
        }

        #expect(request.questions[0].options.isEmpty)
        #expect(request.questions[0].custom == true)
    }

    @Test func questionRequestDefaultsCustomToTrue() async {
        let client = SSEClient()
        // When "custom" field is missing, the parser defaults to true
        let json = """
        {
            "type": "question.asked",
            "properties": {
                "id": "q-default",
                "sessionID": "sess-1",
                "questions": [
                    {
                        "question": "Pick one:",
                        "options": [{"label": "A"}],
                        "multiple": false
                    }
                ]
            }
        }
        """

        let event = await client.parseSSEData(json)
        guard case let .questionAsked(request) = event else {
            Issue.record("Expected questionAsked event")
            return
        }

        // Default should be true per SSEClient implementation
        #expect(request.questions[0].custom == true)
    }

    @Test func questionRequestInfersPlanExitContextAndPath() async {
        let client = SSEClient()
        let json = """
        {
            "type": "question.asked",
            "properties": {
                "id": "q-plan-exit",
                "sessionID": "sess-1",
                "tool": {
                    "messageID": "msg-1",
                    "callID": "call-1"
                },
                "questions": [
                    {
                        "question": "Plan at .opencode/plans/123-demo.md is complete. Would you like to switch to the build agent and start implementing?",
                        "options": [{"label": "Yes"}, {"label": "No"}],
                        "multiple": false,
                        "custom": false
                    }
                ]
            }
        }
        """

        let event = await client.parseSSEData(json)
        guard case let .questionAsked(request) = event else {
            Issue.record("Expected questionAsked event")
            return
        }

        #expect(request.toolContext == "plan_exit")
        #expect(request.planFilePath == ".opencode/plans/123-demo.md")
    }

    @Test func questionRequestInfersPlanEnterContextAndPath() async {
        let client = SSEClient()
        let json = """
        {
            "type": "question.asked",
            "properties": {
                "id": "q-plan-enter",
                "sessionID": "sess-1",
                "questions": [
                    {
                        "question": "Would you like to switch to the plan agent and create a plan saved to .opencode/plans/456-design.md?",
                        "options": [{"label": "Yes"}, {"label": "No"}],
                        "multiple": false,
                        "custom": false
                    }
                ]
            }
        }
        """

        let event = await client.parseSSEData(json)
        guard case let .questionAsked(request) = event else {
            Issue.record("Expected questionAsked event")
            return
        }

        #expect(request.toolContext == "plan_enter")
        #expect(request.planFilePath == ".opencode/plans/456-design.md")
    }

    // MARK: - NativePermissionRequest Parsing

    @Test func permissionRequestWithDiffMetadata() async {
        let client = SSEClient()
        let json = """
        {
            "type": "permission.asked",
            "properties": {
                "id": "p-diff",
                "sessionID": "sess-1",
                "permission": "edit",
                "patterns": ["src/App.tsx"],
                "metadata": {
                    "filepath": "src/App.tsx",
                    "diff": "added export statement"
                },
                "always": ["src/**"]
            }
        }
        """

        let event = await client.parseSSEData(json)
        guard case let .permissionAsked(request) = event else {
            Issue.record("Expected permissionAsked event")
            return
        }

        #expect(request.id == "p-diff")
        #expect(request.permission == "edit")
        #expect(request.patterns == ["src/App.tsx"])
        #expect(request.metadata["filepath"] == "src/App.tsx")
        #expect(request.metadata["diff"] == "added export statement")
        #expect(request.always == ["src/**"])
    }

    @Test func permissionRequestForBash() async {
        let client = SSEClient()
        let json = """
        {
            "type": "permission.asked",
            "properties": {
                "id": "p-bash",
                "sessionID": "sess-1",
                "permission": "bash",
                "patterns": ["rm -rf node_modules"],
                "metadata": {},
                "always": ["rm *"]
            }
        }
        """

        let event = await client.parseSSEData(json)
        guard case let .permissionAsked(request) = event else {
            Issue.record("Expected permissionAsked event")
            return
        }

        #expect(request.permission == "bash")
        #expect(request.patterns == ["rm -rf node_modules"])
        #expect(request.metadata.isEmpty)
        #expect(request.always == ["rm *"])
    }

    @Test func permissionRequestWithEmptyAlways() async {
        let client = SSEClient()
        let json = """
        {
            "type": "permission.asked",
            "properties": {
                "id": "p-noa",
                "sessionID": "sess-1",
                "permission": "read",
                "patterns": ["/etc/hosts"],
                "metadata": {}
            }
        }
        """

        let event = await client.parseSSEData(json)
        guard case let .permissionAsked(request) = event else {
            Issue.record("Expected permissionAsked event")
            return
        }

        #expect(request.always.isEmpty)
    }

    @Test func permissionRequestMultiplePatterns() async {
        let client = SSEClient()
        let json = """
        {
            "type": "permission.asked",
            "properties": {
                "id": "p-multi",
                "sessionID": "sess-1",
                "permission": "edit",
                "patterns": ["file1.ts", "file2.ts", "file3.ts"],
                "metadata": {},
                "always": []
            }
        }
        """

        let event = await client.parseSSEData(json)
        guard case let .permissionAsked(request) = event else {
            Issue.record("Expected permissionAsked event")
            return
        }

        #expect(request.patterns.count == 3)
        #expect(request.patterns == ["file1.ts", "file2.ts", "file3.ts"])
    }

    // MARK: - Permission Reply Format Mapping

    @Test func permissionReplyOnce() {
        let reply = OpenCodeAPIClient.PermissionReply.once
        #expect(reply.wireValue == "once")
    }

    @Test func permissionReplyAlways() {
        let reply = OpenCodeAPIClient.PermissionReply.always
        #expect(reply.wireValue == "always")
    }

    @Test func permissionReplyReject() {
        let reply = OpenCodeAPIClient.PermissionReply.reject(nil)
        #expect(reply.wireValue == "reject")
    }

    @Test func permissionReplyRejectWithReason() {
        let reply = OpenCodeAPIClient.PermissionReply.reject("Too risky")
        #expect(reply.wireValue == "reject")
    }
}
