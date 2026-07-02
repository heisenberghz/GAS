import Foundation

@MainActor
extension ConfigManager {
    // MARK: - Directory Management (delegated to BinaryManager)

    /// User workspace directory (~/.motive/)
    var workspaceDirectory: URL {
        binaryManager.workspaceDirectory
    }

    /// App support directory for runtime files (~/Library/Application Support/Motive/)
    var appSupportDirectory: URL? {
        binaryManager.appSupportDirectory
    }

    /// Runtime directory for node_modules, browser-use, etc.
    var runtimeDirectory: URL? {
        binaryManager.runtimeDirectory
    }

    /// Binary storage directory (kept in Application Support for signing)
    var binaryStorageDirectory: URL? {
        binaryManager.binaryStorageDirectory
    }

    /// Directory containing managed skills (now in workspace)
    var skillsManagedDirectoryURL: URL? {
        binaryManager.skillsManagedDirectoryURL
    }

    // MARK: - Binary Management (delegated to BinaryManager)

    /// Import and sign an external opencode binary
    func importBinary(from sourceURL: URL) async throws {
        try await binaryManager.importBinary(from: sourceURL)
    }

    /// Resolve the OpenCode binary path
    func resolveBinary() -> (url: URL?, error: String?) {
        binaryManager.resolveBinary()
    }

    /// Get the binary URL, importing and signing if necessary
    func getSignedBinaryURL() async -> (url: URL?, error: String?) {
        await binaryManager.getSignedBinaryURL(sourcePath: openCodeBinarySourcePath)
    }
}
