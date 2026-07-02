//
//  CommandRunner.swift
//  Motive
//
//  Abstraction for executing shell commands.
//  Provides testable interface via protocol.
//

import Foundation

// MARK: - Protocol

protocol CommandRunnerProtocol: Sendable {
    func run(_ argv: [String], timeout: Int, env: [String: String]?) async -> CommandResult
    func hasBinary(_ name: String) -> Bool
}

// MARK: - Result

struct CommandResult: Sendable, Equatable {
    var stdout: String
    var stderr: String
    var exitCode: Int?

    var succeeded: Bool {
        exitCode == 0
    }
}

// MARK: - Implementation

final class CommandRunner: CommandRunnerProtocol, @unchecked Sendable {
    static let shared = CommandRunner()

    private var binaryCache: [String: Bool] = [:]
    private let cacheLock = NSLock()

    private init() {}

    /// Clear the binary existence cache (call after installing new tools)
    func clearBinaryCache() {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        binaryCache.removeAll()
    }

    func run(_ argv: [String], timeout: Int, env: [String: String]? = nil) async -> CommandResult {
        guard !argv.isEmpty else {
            return CommandResult(stdout: "", stderr: "Empty command", exitCode: 1)
        }

        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = argv
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Set environment with extended PATH for GUI apps
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = Self.effectivePaths().joined(separator: ":")
        if let env {
            for (key, value) in env {
                environment[key] = value
            }
        }
        process.environment = environment

        // Run with timeout
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                do {
                    try process.run()

                    // Set timeout
                    let timeoutSeconds = Double(timeout)
                    let deadline = DispatchTime.now() + timeoutSeconds

                    DispatchQueue.global().asyncAfter(deadline: deadline) {
                        if process.isRunning {
                            process.terminate()
                        }
                    }

                    process.waitUntilExit()

                    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                    let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                    let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                    continuation.resume(returning: CommandResult(
                        stdout: stdout,
                        stderr: stderr,
                        exitCode: Int(process.terminationStatus)
                    ))
                } catch {
                    continuation.resume(returning: CommandResult(
                        stdout: "",
                        stderr: error.localizedDescription,
                        exitCode: nil
                    ))
                }
            }
        }
    }

    func hasBinary(_ name: String) -> Bool {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        if let cached = binaryCache[name] { return cached }

        let result = Self.effectivePaths().contains { path in
            FileManager.default.isExecutableFile(atPath: (path as NSString).appendingPathComponent(name))
        }
        binaryCache[name] = result
        return result
    }

    /// Build effective PATH including common tool locations.
    /// GUI apps don't inherit shell config, so we manually add known paths.
    static func effectivePaths() -> [String] {
        let systemPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        var paths = systemPath.split(separator: ":").map(String.init)
        let home = NSHomeDirectory()

        // Common macOS tool locations (order matters — first match wins)
        let extraPaths = [
            "/opt/homebrew/bin", "/opt/homebrew/sbin", // Homebrew (Apple Silicon)
            "/usr/local/bin", "/usr/local/sbin", // Homebrew (Intel)
            "/usr/bin", "/bin", "/usr/sbin", "/sbin", // System
            "\(home)/go/bin", "/usr/local/go/bin", // Go
            "\(home)/.cargo/bin", // Rust/Cargo
            "\(home)/.local/bin", // Python/pip/uv
            "/opt/homebrew/opt/python/libexec/bin", // Homebrew Python
            "/opt/homebrew/lib/node_modules/.bin", // Node (Homebrew)
            "/usr/local/lib/node_modules/.bin", // Node (Intel)
            "\(home)/Library/pnpm", // pnpm
        ]

        for path in extraPaths where !paths.contains(path) {
            paths.append(path)
        }
        return paths
    }
}

// MARK: - Mock for Testing

final class MockCommandRunner: CommandRunnerProtocol, @unchecked Sendable {
    var stubbedResults: [String: CommandResult] = [:]
    var stubbedBinaries: Set<String> = []
    var runCalls: [[String]] = []

    func run(_ argv: [String], timeout: Int, env: [String: String]?) async -> CommandResult {
        runCalls.append(argv)
        let key = argv.joined(separator: " ")
        return stubbedResults[key] ?? CommandResult(stdout: "", stderr: "", exitCode: 0)
    }

    func hasBinary(_ name: String) -> Bool {
        stubbedBinaries.contains(name)
    }

    func reset() {
        stubbedResults = [:]
        stubbedBinaries = []
        runCalls = []
    }
}
