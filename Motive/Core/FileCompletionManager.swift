//
//  FileCompletionManager.swift
//  Motive
//
//  File and directory completion for @ mentions
//

import Combine
import Foundation

/// Manages file and directory completion for @ mentions
@MainActor
final class FileCompletionManager: ObservableObject {
    static let shared = FileCompletionManager()

    @Published var items: [FileCompletionItem] = []
    @Published var isLoading: Bool = false
    @Published var currentPath: String = ""

    private var fileManager = FileManager.default

    /// Get the base directory for file completion
    /// - If current project is ~/.motive (default), use home directory
    /// - Otherwise use current project directory
    func getBaseDirectory(for configManager: ConfigManager) -> URL {
        let baseDir: URL
        if configManager.currentProjectPath.isEmpty {
            // Default project - use home directory
            baseDir = fileManager.homeDirectoryForCurrentUser
            Log.config("🔍 getBaseDirectory: using home (currentProjectPath is empty) -> \(baseDir.path)")
        } else {
            // Custom project - use project root
            baseDir = URL(fileURLWithPath: configManager.currentProjectPath)
            Log.config("🔍 getBaseDirectory: using project '\(configManager.currentProjectPath)' -> \(baseDir.path)")
        }
        return baseDir
    }

    /// Parse @ query to extract path components
    /// Returns (basePath, searchQuery)
    /// Examples:
    ///   "@" -> ("", "")
    ///   "@src" -> ("", "src")
    ///   "@src/" -> ("src", "")
    ///   "@src/com" -> ("src", "com")
    func parseAtQuery(_ query: String) -> (basePath: String, searchQuery: String) {
        guard query.hasPrefix("@") else { return ("", "") }

        let path = String(query.dropFirst()) // Remove @

        if path.isEmpty {
            return ("", "")
        }

        // Find last slash to separate directory from search query
        if let lastSlashIndex = path.lastIndex(of: "/") {
            let basePath = String(path[..<lastSlashIndex])
            let searchQuery = String(path[path.index(after: lastSlashIndex)...])
            return (basePath, searchQuery)
        } else {
            // No slash - entire thing is search query in root
            return ("", path)
        }
    }

    /// Load files and directories for completion
    func loadItems(query: String, baseDir: URL) {
        let (basePath, searchQuery) = parseAtQuery(query)
        currentPath = basePath
        isLoading = true

        Log.config("🔍 FileCompletion - query: '\(query)', basePath: '\(basePath)', searchQuery: '\(searchQuery)'")

        // Build full directory path
        var targetDir = baseDir
        if !basePath.isEmpty {
            targetDir = baseDir.appendingPathComponent(basePath)
        }
        targetDir = targetDir.standardizedFileURL

        Log.config("🔍 FileCompletion - targetDir: \(targetDir.path)")

        // Check if directory exists
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: targetDir.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            items = []
            isLoading = false
            return
        }

        do {
            let contents = try fileManager.contentsOfDirectory(
                at: targetDir,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )

            Log.config("🔍 FileCompletion - found \(contents.count) items in directory")

            var result: [FileCompletionItem] = []

            for url in contents {
                let name = url.lastPathComponent

                // Filter by search query
                if !searchQuery.isEmpty {
                    guard name.localizedCaseInsensitiveContains(searchQuery) else { continue }
                }

                let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                let isDir = resourceValues?.isDirectory ?? false
                let size = resourceValues?.fileSize

                // Build the full @ path for insertion
                let fullPath: String = if basePath.isEmpty {
                    name
                } else {
                    "\(basePath)/\(name)"
                }

                result.append(FileCompletionItem(
                    name: name,
                    path: fullPath,
                    fullURL: url,
                    isDirectory: isDir,
                    size: size
                ))
            }

            // Sort: directories first, then alphabetically
            result.sort { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory {
                    return lhs.isDirectory
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }

            items = Array(result.prefix(50)) // Limit to 50 items
            Log.config("🔍 FileCompletion - loaded \(items.count) items, first 3: \(items.prefix(3).map(\.name).joined(separator: ", "))")

        } catch {
            Log.config("FileCompletion error: \(error)")
            items = []
        }

        isLoading = false
    }

    /// Clear completion state
    func clear() {
        items = []
        currentPath = ""
        isLoading = false
    }
}

// MARK: - File Completion Item

struct FileCompletionItem: Identifiable, Equatable {
    var id: String {
        path
    }

    let name: String
    let path: String // Relative path for @ insertion
    let fullURL: URL
    let isDirectory: Bool
    let size: Int?

    var icon: String {
        if isDirectory {
            return "folder.fill"
        }
        return iconForExtension(fullURL.pathExtension)
    }

    var sizeString: String? {
        guard let size, !isDirectory else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    private func iconForExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "swift": "swift"
        case "js", "ts", "jsx", "tsx": "chevron.left.forwardslash.chevron.right"
        case "py": "text.page"
        case "json", "yaml", "yml", "toml": "doc.text"
        case "md", "txt", "rtf": "doc.plaintext"
        case "html", "css", "scss": "globe"
        case "png", "jpg", "jpeg", "gif", "svg", "webp": "photo"
        case "mp4", "mov", "avi": "video"
        case "mp3", "wav", "aac": "music.note"
        case "zip", "tar", "gz", "rar": "doc.zipper"
        case "pdf": "doc.richtext"
        case "sh", "bash", "zsh": "terminal"
        default: "doc"
        }
    }
}
