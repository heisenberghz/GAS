import Foundation
@testable import Motive
import Testing

struct OpenCodeAPIClientTests {

    // MARK: - PermissionReply Wire Values

    @Test func permissionReplyOnceWireValue() {
        let reply = OpenCodeAPIClient.PermissionReply.once
        #expect(reply.wireValue == "once")
    }

    @Test func permissionReplyAlwaysWireValue() {
        let reply = OpenCodeAPIClient.PermissionReply.always
        #expect(reply.wireValue == "always")
    }

    @Test func permissionReplyRejectWireValue() {
        let reply = OpenCodeAPIClient.PermissionReply.reject(nil)
        #expect(reply.wireValue == "reject")
    }

    @Test func permissionReplyRejectWithMessageWireValue() {
        let reply = OpenCodeAPIClient.PermissionReply.reject("Not allowed")
        #expect(reply.wireValue == "reject")
    }

    // MARK: - API Error Descriptions

    @Test func apiErrorNoBaseURLDescription() {
        let error = OpenCodeAPIClient.APIError.noBaseURL
        #expect(error.errorDescription?.contains("no base URL") == true)
    }

    @Test func apiErrorHTTPErrorDescription() {
        let error = OpenCodeAPIClient.APIError.httpError(statusCode: 404, body: "Not Found")
        let desc = error.errorDescription ?? ""
        #expect(desc.contains("404"))
        #expect(desc.contains("Not Found"))
    }

    @Test func apiErrorHTTPErrorWithoutBody() {
        let error = OpenCodeAPIClient.APIError.httpError(statusCode: 500, body: nil)
        let desc = error.errorDescription ?? ""
        #expect(desc.contains("500"))
    }

    @Test func apiErrorDecodingDescription() {
        let error = OpenCodeAPIClient.APIError.decodingError("Missing field")
        #expect(error.errorDescription?.contains("Missing field") == true)
    }

    @Test func apiErrorNetworkDescription() {
        let underlyingError = NSError(domain: "test", code: -1009, userInfo: [NSLocalizedDescriptionKey: "No internet"])
        let error = OpenCodeAPIClient.APIError.networkError(underlyingError)
        #expect(error.errorDescription?.contains("No internet") == true)
    }

    // MARK: - Client Initial State

    @Test func clientStartsWithNoBaseURL() async throws {
        let client = OpenCodeAPIClient()
        // Attempting to create a session without a base URL should throw noBaseURL
        do {
            _ = try await client.createSession()
            Issue.record("Expected noBaseURL error")
        } catch let error as OpenCodeAPIClient.APIError {
            guard case .noBaseURL = error else {
                Issue.record("Expected noBaseURL, got \(error)")
                return
            }
        }
    }

    // MARK: - Session Info

    @Test func sessionInfoStoresIdAndTitle() {
        let info = OpenCodeAPIClient.SessionInfo(id: "sess-123", title: "Test Session")
        #expect(info.id == "sess-123")
        #expect(info.title == "Test Session")
    }

    @Test func sessionInfoWithNilTitle() {
        let info = OpenCodeAPIClient.SessionInfo(id: "sess-456", title: nil)
        #expect(info.id == "sess-456")
        #expect(info.title == nil)
    }

    // MARK: - Model Payload Routing

    @Test func openRouterModelWithSlash_keepsWholeModelID() {
        let payload = OpenCodeAPIClient.makeModelPayload(
            model: "anthropic/claude-sonnet-4",
            modelProviderID: "openrouter"
        )
        #expect(payload?["providerID"] == "openrouter")
        #expect(payload?["modelID"] == "anthropic/claude-sonnet-4")
    }

    @Test func nonOpenRouterModelWithSlash_splitsProviderAndModel() {
        let payload = OpenCodeAPIClient.makeModelPayload(
            model: "openai/gpt-4o-mini",
            modelProviderID: "openai"
        )
        #expect(payload?["providerID"] == "openai")
        #expect(payload?["modelID"] == "gpt-4o-mini")
    }

    @Test func rawModelWithoutSlash_usesSelectedProvider() {
        let payload = OpenCodeAPIClient.makeModelPayload(
            model: "gpt-5",
            modelProviderID: "openai"
        )
        #expect(payload?["providerID"] == "openai")
        #expect(payload?["modelID"] == "gpt-5")
    }
}
