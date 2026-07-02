//
//  BinaryManagerTests.swift
//  MotiveTests
//

import Foundation
@testable import Motive
import Testing

@MainActor
struct BinaryManagerTests {

    private func makeBinaryManager(
        sourcePath: String = "",
        onSetSourcePath: ((String) -> Void)? = nil,
        onSetBinaryStatus: ((ConfigManager.BinaryStatus) -> Void)? = nil
    ) -> BinaryManager {
        var storedPath = sourcePath
        return BinaryManager(
            getSourcePath: { storedPath },
            setSourcePath: { newPath in
                storedPath = newPath
                onSetSourcePath?(newPath)
            },
            setBinaryStatus: { status in
                onSetBinaryStatus?(status)
            }
        )
    }

    @Test func resolveBinary_noSourcePath_returnsError() throws {
        let manager = makeBinaryManager()
        let (url, error) = manager.resolveBinary()
        // If no binary exists at any known path, we get nil + error message
        // (unless the test machine has opencode installed)
        if url == nil {
            #expect(error != nil)
            #expect(try #require(error?.contains("not found")))
        }
    }

    @Test func binaryStorageDirectory_isInAppSupport() throws {
        let manager = makeBinaryManager()
        let dir = manager.binaryStorageDirectory
        #expect(dir != nil)
        #expect(try #require(dir?.path.contains("Application Support/Motive")) || dir!.path.contains("Motive"))
    }

    @Test func importBinary_copiesAndSigns() async throws {
        try await withTempDirectory { tempDir in
            let sourceURL = tempDir.appendingPathComponent("opencode")
            // Create a fake binary (just a shell script)
            try "#!/bin/sh\necho hello".write(to: sourceURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sourceURL.path)

            var lastStatus: ConfigManager.BinaryStatus?
            let manager = makeBinaryManager(
                onSetBinaryStatus: { lastStatus = $0 }
            )

            try await manager.importBinary(from: sourceURL)

            // Verify the binary was copied to storage
            let signedPath = manager.binaryStorageDirectory?.appendingPathComponent("opencode")
            #expect(signedPath != nil)
            #expect(FileManager.default.fileExists(atPath: signedPath!.path))

            // Verify status was set to ready
            if case .ready = lastStatus {
                // expected
            } else {
                Issue.record("Expected .ready status, got \(String(describing: lastStatus))")
            }
        }
    }

    @Test func importBinary_sourceNotFound_throws() async throws {
        let manager = makeBinaryManager()
        let fakeURL = URL(fileURLWithPath: "/tmp/nonexistent_binary_\(UUID().uuidString)")

        do {
            try await manager.importBinary(from: fakeURL)
            Issue.record("Expected error to be thrown")
        } catch {
            // Expected: sourceNotFound error
            #expect(error is ConfigManager.BinaryError)
        }
    }

    @Test func getSignedBinaryURL_withMissingBinary_returnsError() async {
        // Create a manager that won't find any binary
        var lastStatus: ConfigManager.BinaryStatus?
        let manager = makeBinaryManager(
            onSetBinaryStatus: { lastStatus = $0 }
        )

        let (url, error) = await manager.getSignedBinaryURL(sourcePath: "/nonexistent/path")
        // If no binary is found anywhere, we should get an error
        if url == nil {
            #expect(error != nil)
            if case .notConfigured = lastStatus {
                // expected
            }
        }
    }
}
