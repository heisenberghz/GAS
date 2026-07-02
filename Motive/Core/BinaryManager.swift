//
//  BinaryManager.swift
//  Motive
//
//  Manages OpenCode binary discovery, import, signing, and resolution.
//  Extracted from ConfigManager+Binary.swift.
//

import Foundation

@MainActor
final class BinaryManager {
    // MARK: - Storage Callbacks

    private let getSourcePath: () -> String
    private let setSourcePath: (String) -> Void
    private let setBinaryStatus: (ConfigManager.BinaryStatus) -> Void

    init(
        getSourcePath: @escaping () -> String,
        setSourcePath: @escaping (String) -> Void,
        setBinaryStatus: @escaping (ConfigManager.BinaryStatus) -> Void
    ) {
        self.getSourcePath = getSourcePath
        self.setSourcePath = setSourcePath
        self.setBinaryStatus = setBinaryStatus
    }

    // MARK: - Directory Management

    /// User workspace directory (~/.motive/)
    var workspaceDirectory: URL {
        WorkspaceManager.defaultWorkspaceURL
    }

    /// App support directory for runtime files (~/Library/Application Support/Motive/)
    var appSupportDirectory: URL? {
        let fileManager = FileManager.default

        if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let motiveDir = appSupport.appendingPathComponent("Motive")

            if !fileManager.fileExists(atPath: motiveDir.path) {
                do {
                    try fileManager.createDirectory(at: motiveDir, withIntermediateDirectories: true, attributes: nil)
                    Log.config(" Created directory at \(motiveDir.path)")
                    return motiveDir
                } catch {
                    Log.config(" Failed to create Application Support directory: \(error)")
                }
            } else {
                return motiveDir
            }
        }

        let tempDir = fileManager.temporaryDirectory.appendingPathComponent("Motive")
        if !fileManager.fileExists(atPath: tempDir.path) {
            try? fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
        }
        Log.config(" Using temp directory at \(tempDir.path)")
        return tempDir
    }

    /// Runtime directory for node_modules, browser-use, etc.
    var runtimeDirectory: URL? {
        appSupportDirectory?.appendingPathComponent("runtime")
    }

    /// Binary storage directory (kept in Application Support for signing)
    var binaryStorageDirectory: URL? {
        appSupportDirectory
    }

    /// Path to the signed opencode binary
    private var signedBinaryPath: URL? {
        binaryStorageDirectory?.appendingPathComponent("opencode")
    }

    /// Directory containing managed skills (now in workspace)
    var skillsManagedDirectoryURL: URL? {
        workspaceDirectory.appendingPathComponent("skills")
    }

    // MARK: - Binary Management

    /// Import and sign an external opencode binary
    func importBinary(from sourceURL: URL) async throws {
        let fileManager = FileManager.default

        guard let destURL = signedBinaryPath else {
            throw ConfigManager.BinaryError.noAppSupport
        }

        if let parentDir = signedBinaryPath?.deletingLastPathComponent() {
            if !fileManager.fileExists(atPath: parentDir.path) {
                do {
                    try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true, attributes: nil)
                } catch {
                    throw ConfigManager.BinaryError.directoryCreationFailed(parentDir.path, error.localizedDescription)
                }
            }
        }

        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw ConfigManager.BinaryError.sourceNotFound(sourceURL.path)
        }

        Log.config(" Importing binary from \(sourceURL.path) to \(destURL.path)")

        if fileManager.fileExists(atPath: destURL.path) {
            do {
                try fileManager.removeItem(at: destURL)
            } catch {
                Log.config(" Failed to remove existing binary: \(error)")
            }
        }

        do {
            try fileManager.copyItem(at: sourceURL, to: destURL)
        } catch {
            throw ConfigManager.BinaryError.copyFailed(error.localizedDescription)
        }

        do {
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destURL.path)
        } catch {
            Log.config(" Failed to set permissions: \(error)")
        }

        try await signBinary(at: destURL)

        setSourcePath(sourceURL.path)
        setBinaryStatus(.ready(destURL.path))

        Log.config(" Binary imported and signed successfully at \(destURL.path)")
    }

    /// Sign a binary using ad-hoc signature
    private func signBinary(at url: URL) async throws {
        Log.config(" Signing binary at \(url.path)")

        let xattrProcess = Process()
        xattrProcess.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattrProcess.arguments = ["-cr", url.path]
        try? xattrProcess.run()
        xattrProcess.waitUntilExit()
        Log.config(" Cleared extended attributes")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--force", "--deep", "--sign", "-", url.path]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrMessage = String(data: stderrData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            Log.config(" codesign failed with status \(process.terminationStatus): \(stderrMessage)")
            throw ConfigManager.BinaryError.signingFailed(stderrMessage)
        }

        let verifyProcess = Process()
        verifyProcess.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        verifyProcess.arguments = ["-v", "--verbose=4", url.path]
        let verifyPipe = Pipe()
        verifyProcess.standardError = verifyPipe
        try? verifyProcess.run()
        verifyProcess.waitUntilExit()
        let verifyOutput = String(data: verifyPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        Log.config(" Signature verification: \(verifyOutput)")

        Log.config(" Binary signed successfully")
    }

    /// Resolve the OpenCode binary path
    /// Minimum file size for a valid opencode binary (~1MB).
    /// Rejects shell script stubs or corrupted files.
    private static let minimumBinarySize: UInt64 = 1_000_000

    func resolveBinary() -> (url: URL?, error: String?) {
        let fileManager = FileManager.default

        if let signedPath = signedBinaryPath, fileManager.fileExists(atPath: signedPath.path) {
            if Self.isValidBinary(at: signedPath) {
                Log.config(" Using signed binary: \(signedPath.path)")
                setBinaryStatus(.ready(signedPath.path))
                return (signedPath, nil)
            } else {
                Log.warning("Signed binary at \(signedPath.path) is invalid (too small or not a Mach-O), removing")
                try? fileManager.removeItem(at: signedPath)
            }
        }

        // Prefer bundled OpenCode for deterministic behavior in fresh installs.
        // Support both Resources/opencode and Contents/opencode for compatibility.
        if let bundledURL = resolveBundledOpenCodeURL(fileManager: fileManager) {
            Log.config(" Using bundled OpenCode: \(bundledURL.path)")
            setBinaryStatus(.ready(bundledURL.path))
            return (bundledURL, nil)
        }

        if let nvmPath = findNvmOpenCode() {
            Log.config(" Found nvm OpenCode at \(nvmPath.path), will import on first use")
            return (nvmPath, nil)
        }

        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let globalPaths = [
            "\(homeDir)/.opencode/bin/opencode",
            "/usr/local/bin/opencode",
            "/opt/homebrew/bin/opencode"
        ]
        for path in globalPaths {
            if fileManager.fileExists(atPath: path) {
                let url = URL(fileURLWithPath: path)
                Log.config(" Found global OpenCode at \(path), will import on first use")
                return (url, nil)
            }
        }

        setBinaryStatus(.notConfigured)
        return (nil, "OpenCode CLI not found. Install via npm: npm install -g opencode-ai")
    }

    /// Get the binary URL, importing and signing if necessary
    func getSignedBinaryURL(sourcePath: String) async -> (url: URL?, error: String?) {
        let fileManager = FileManager.default

        if let signedPath = signedBinaryPath, fileManager.fileExists(atPath: signedPath.path),
           Self.isValidBinary(at: signedPath)
        {
            return (signedPath, nil)
        }

        let (sourceURL, error) = resolveBinary()
        guard let source = sourceURL else {
            return (nil, error)
        }

        if let signedPath = signedBinaryPath, source.path == signedPath.path {
            return (source, nil)
        }

        do {
            try await importBinary(from: source)
            return (signedBinaryPath, nil)
        } catch {
            let errorMsg = "Failed to import binary: \(error.localizedDescription)"
            setBinaryStatus(.error(errorMsg))
            return (nil, errorMsg)
        }
    }

    /// Scan nvm versions directory to find OpenCode installations
    private func findNvmOpenCode() -> URL? {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let nvmVersionsDir = "\(homeDir)/.nvm/versions/node"
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: nvmVersionsDir) else {
            return nil
        }

        do {
            let versions = try fileManager.contentsOfDirectory(atPath: nvmVersionsDir)
            for version in versions.sorted().reversed() {
                let platformBinaryPath = "\(nvmVersionsDir)/\(version)/lib/node_modules/opencode-ai/node_modules/opencode-darwin-arm64/bin/opencode"
                if fileManager.fileExists(atPath: platformBinaryPath) {
                    return URL(fileURLWithPath: platformBinaryPath)
                }

                let shimPath = "\(nvmVersionsDir)/\(version)/bin/opencode"
                if fileManager.fileExists(atPath: shimPath) {
                    return URL(fileURLWithPath: shimPath)
                }
            }
        } catch {
            Log.config(" Error scanning nvm directory: \(error)")
        }

        return nil
    }

    private func resolveBundledOpenCodeURL(fileManager: FileManager) -> URL? {
        if let resourceURL = Bundle.main.url(forResource: "opencode", withExtension: nil),
           fileManager.fileExists(atPath: resourceURL.path)
        {
            return resourceURL
        }
        let contentsURL = Bundle.main.bundleURL.appendingPathComponent("Contents/opencode")
        if fileManager.fileExists(atPath: contentsURL.path) {
            return contentsURL
        }
        return nil
    }

    /// Check if a file is a valid opencode binary (not a shell script stub or corrupted file)
    private static func isValidBinary(at url: URL) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attrs[.size] as? UInt64
        else {
            return false
        }
        return fileSize >= minimumBinarySize
    }
}
