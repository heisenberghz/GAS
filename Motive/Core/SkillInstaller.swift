//
//  SkillInstaller.swift
//  Motive
//
//  Handles skill dependency installation via various package managers.
//

import Foundation

// MARK: - Protocol

protocol SkillInstallerProtocol: Sendable {
    func install(spec: SkillInstallSpec, timeoutSeconds: Int) async -> SkillInstallResult
}

// MARK: - Result

struct SkillInstallResult: Sendable, Equatable {
    var ok: Bool
    var message: String
    var stdout: String
    var stderr: String
    var exitCode: Int?

    static func success(message: String = "Installed successfully", stdout: String = "", stderr: String = "") -> SkillInstallResult {
        SkillInstallResult(ok: true, message: message, stdout: stdout, stderr: stderr, exitCode: 0)
    }

    static func failure(message: String, stdout: String = "", stderr: String = "", exitCode: Int? = nil) -> SkillInstallResult {
        SkillInstallResult(ok: false, message: message, stdout: stdout, stderr: stderr, exitCode: exitCode)
    }
}

// MARK: - Implementation

final class SkillInstaller: SkillInstallerProtocol, @unchecked Sendable {
    private let commandRunner: CommandRunnerProtocol

    init(commandRunner: CommandRunnerProtocol = CommandRunner.shared) {
        self.commandRunner = commandRunner
    }

    func install(spec: SkillInstallSpec, timeoutSeconds: Int) async -> SkillInstallResult {
        let command = buildCommand(for: spec)

        guard !command.isEmpty else {
            if spec.kind == .download {
                return await handleDownloadInstall(spec: spec, timeoutSeconds: timeoutSeconds)
            }
            return .failure(message: "Missing required field for \(spec.kind.rawValue) install")
        }

        let result = await commandRunner.run(command, timeout: timeoutSeconds, env: nil)

        if result.succeeded {
            return .success(
                message: "Installed via \(spec.kind.rawValue)",
                stdout: result.stdout,
                stderr: result.stderr
            )
        } else {
            return .failure(
                message: formatFailureMessage(result, kind: spec.kind),
                stdout: result.stdout,
                stderr: result.stderr,
                exitCode: result.exitCode
            )
        }
    }

    // MARK: - Private

    private func buildCommand(for spec: SkillInstallSpec) -> [String] {
        switch spec.kind {
        case .brew:
            guard let formula = spec.formula, !formula.isEmpty else { return [] }
            return ["brew", "install", formula]

        case .node:
            guard let package = spec.package, !package.isEmpty else { return [] }
            // Check for preferred package manager
            if commandRunner.hasBinary("pnpm") {
                return ["pnpm", "add", "-g", package]
            }
            return ["npm", "install", "-g", package]

        case .go:
            guard let module = spec.module, !module.isEmpty else { return [] }
            return ["go", "install", module]

        case .uv:
            guard let package = spec.package, !package.isEmpty else { return [] }
            return ["uv", "tool", "install", package]

        case .apt:
            guard let package = spec.package, !package.isEmpty else { return [] }
            return ["sudo", "apt", "install", "-y", package]

        case .download:
            return [] // Handled separately
        }
    }

    private func handleDownloadInstall(spec: SkillInstallSpec, timeoutSeconds: Int) async -> SkillInstallResult {
        guard let url = spec.url, !url.isEmpty else {
            return .failure(message: "Download install requires url")
        }

        // Determine target directory
        let targetDir: String
        if let dir = spec.targetDir, !dir.isEmpty {
            targetDir = dir.replacingOccurrences(of: "~", with: FileManager.default.homeDirectoryForCurrentUser.path)
        } else {
            let toolsDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".motive")
                .appendingPathComponent("tools")
            targetDir = toolsDir.path
        }

        // Create target directory
        try? FileManager.default.createDirectory(
            atPath: targetDir,
            withIntermediateDirectories: true
        )

        // Download with curl
        let downloadPath = "\(targetDir)/\(URL(string: url)?.lastPathComponent ?? "download")"
        let curlResult = await commandRunner.run(
            ["curl", "-fsSL", "-o", downloadPath, url],
            timeout: timeoutSeconds,
            env: nil
        )

        guard curlResult.succeeded else {
            return .failure(
                message: "Download failed: \(curlResult.stderr)",
                stdout: curlResult.stdout,
                stderr: curlResult.stderr,
                exitCode: curlResult.exitCode
            )
        }

        // Extract if needed
        if let archive = spec.archive, !archive.isEmpty, spec.extract != false {
            let extractResult = await extractArchive(
                path: downloadPath,
                archiveType: archive,
                targetDir: targetDir,
                stripComponents: spec.stripComponents ?? 0,
                timeoutSeconds: timeoutSeconds
            )

            if !extractResult.succeeded {
                return .failure(
                    message: "Extraction failed: \(extractResult.stderr)",
                    stdout: extractResult.stdout,
                    stderr: extractResult.stderr,
                    exitCode: extractResult.exitCode
                )
            }

            // Clean up archive
            try? FileManager.default.removeItem(atPath: downloadPath)
        }

        return .success(message: "Downloaded to \(targetDir)")
    }

    private func extractArchive(
        path: String,
        archiveType: String,
        targetDir: String,
        stripComponents: Int,
        timeoutSeconds: Int
    ) async -> CommandResult {
        var command: [String]

        switch archiveType.lowercased() {
        case "tar.gz", "tgz":
            command = ["tar", "-xzf", path, "-C", targetDir]
            if stripComponents > 0 {
                command.append(contentsOf: ["--strip-components=\(stripComponents)"])
            }

        case "tar.bz2", "tbz2":
            command = ["tar", "-xjf", path, "-C", targetDir]
            if stripComponents > 0 {
                command.append(contentsOf: ["--strip-components=\(stripComponents)"])
            }

        case "zip":
            command = ["unzip", "-o", path, "-d", targetDir]

        default:
            return CommandResult(stdout: "", stderr: "Unknown archive type: \(archiveType)", exitCode: 1)
        }

        return await commandRunner.run(command, timeout: timeoutSeconds, env: nil)
    }

    private func formatFailureMessage(_ result: CommandResult, kind: InstallKind) -> String {
        let code = result.exitCode.map { "exit \($0)" } ?? "unknown exit"
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)

        if stderr.isEmpty {
            return "Install via \(kind.rawValue) failed (\(code))"
        }

        let truncated = stderr.count > 200 ? String(stderr.prefix(200)) + "..." : stderr
        return "Install via \(kind.rawValue) failed (\(code)): \(truncated)"
    }
}
