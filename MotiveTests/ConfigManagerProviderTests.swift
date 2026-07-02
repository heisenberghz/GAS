import Foundation
@testable import Motive
import Testing

@Suite("ConfigManager Provider Normalization")
struct ConfigManagerProviderTests {

    @Test @MainActor func baseURLNormalizationForOpenAI() {
        let config = ConfigManager()

        // Mocking behavior by setting provider and baseURL
        // Note: provider is @Published, so we can set it.
        config.provider = .openai

        // Test case 1: Custom base URL without /v1
        config.baseURL = "http://192.168.1.50:3333"
        #expect(config.normalizedBaseURL == "http://192.168.1.50:3333/v1")

        // Test case 2: Custom base URL WITH /v1 (should not append again)
        config.baseURL = "http://192.168.1.50:3333/v1"
        #expect(config.normalizedBaseURL == "http://192.168.1.50:3333/v1")

        // Test case 3: Custom base URL with /v1/ (trailing slash)
        config.baseURL = "http://192.168.1.50:3333/v1/"
        #expect(config.normalizedBaseURL == "http://192.168.1.50:3333/v1/")

        // Test case 4: Non-OpenAI provider (should not normalize)
        config.provider = .claude
        config.baseURL = "https://api.anthropic.com" // although claude has a fixed URL usually
        #expect(config.normalizedBaseURL == "https://api.anthropic.com")
    }

    @Test @MainActor func baseURLNormalizationForLMStudio() {
        let config = ConfigManager()
        config.provider = .lmstudio

        // Test case 1: LM Studio default style
        config.baseURL = "http://localhost:1234"
        #expect(config.normalizedBaseURL == "http://localhost:1234/v1")

        // Test case 2: Custom Local IP
        config.baseURL = "http://192.168.1.50:3333"
        #expect(config.normalizedBaseURL == "http://192.168.1.50:3333/v1")
    }
}
