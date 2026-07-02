import Foundation
@testable import Motive
import Testing

struct OpenCodeServerTests {

    // MARK: - Port Detection

    @Test func parsesListeningURLFromStdout() async {
        let server = OpenCodeServer()

        // Standard format
        let url1 = await server.parseListeningURL(from: "listening on http://127.0.0.1:4096")
        #expect(url1?.absoluteString == "http://127.0.0.1:4096")

        // Capitalized
        let url2 = await server.parseListeningURL(from: "Listening on http://127.0.0.1:8080")
        #expect(url2?.absoluteString == "http://127.0.0.1:8080")

        // Localhost variant
        let url3 = await server.parseListeningURL(from: "listening on http://localhost:3000")
        #expect(url3?.absoluteString == "http://127.0.0.1:3000")

        // 0.0.0.0 variant
        let url4 = await server.parseListeningURL(from: "listening on http://0.0.0.0:5000")
        #expect(url4?.absoluteString == "http://127.0.0.1:5000")
    }

    @Test func returnsNilForNonListeningLines() async {
        let server = OpenCodeServer()

        let result1 = await server.parseListeningURL(from: "Starting server...")
        #expect(result1 == nil)

        let result2 = await server.parseListeningURL(from: "")
        #expect(result2 == nil)

        let result3 = await server.parseListeningURL(from: "Loading configuration from /home/.config")
        #expect(result3 == nil)
    }

    // MARK: - Server State

    @Test func serverStartsInStoppedState() async {
        let server = OpenCodeServer()
        let isRunning = await server.isRunning
        let url = await server.serverURL

        #expect(isRunning == false)
        #expect(url == nil)
    }

    // MARK: - Health Check

    @Test func healthCheckReturnsFalseWhenNotRunning() async {
        let server = OpenCodeServer()
        let healthy = await server.isHealthy()
        #expect(healthy == false)
    }
}
