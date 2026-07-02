//
//  ProjectManager.swift
//  Motive
//
//  Project directory management.
//  Extracted from ConfigManager+Project.swift.
//

import Foundation

@MainActor
final class ProjectManager {
    // MARK: - Storage Callbacks

    private let getCurrentPath: () -> String
    private let setCurrentPath: (String) -> Void
    private let getRecentJSON: () -> String
    private let setRecentJSON: (String) -> Void

    init(
        getCurrentPath: @escaping () -> String,
        setCurrentPath: @escaping (String) -> Void,
        getRecentJSON: @escaping () -> String,
        setRecentJSON: @escaping (String) -> Void
    ) {
        self.getCurrentPath = getCurrentPath
        self.setCurrentPath = setCurrentPath
        self.getRecentJSON = getRecentJSON
        self.setRecentJSON = setRecentJSON
    }

    // MARK: - Constants

    /// Default global working directory when no project is selected
    static var defaultProjectDirectory: URL {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        return homeDir.appendingPathComponent(".motive")
    }

    /// Maximum number of recent projects to keep
    static let maxRecentProjects = MotiveConstants.Limits.maxRecentProjects

    // MARK: - Computed Properties

    /// Get the current project directory URL
    var currentProjectURL: URL {
        let path = getCurrentPath()
        if path.isEmpty {
            return Self.defaultProjectDirectory
        }
        return URL(fileURLWithPath: path)
    }

    /// Get the display name for current project
    var currentProjectDisplayName: String {
        let path = getCurrentPath()
        if path.isEmpty {
            return "~/.motive"
        }
        let url = URL(fileURLWithPath: path)
        return url.lastPathComponent
    }

    /// Get shortened path for display (replaces home with ~)
    var currentProjectShortPath: String {
        let path = getCurrentPath()
        if path.isEmpty {
            return "~/.motive"
        }
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(homeDir) {
            return "~" + path.dropFirst(homeDir.count)
        }
        return path
    }

    /// Recent projects list
    var recentProjects: [RecentProject] {
        get {
            guard let data = getRecentJSON().data(using: .utf8) else {
                return []
            }
            do {
                return try JSONDecoder().decode([RecentProject].self, from: data)
            } catch {
                Log.error("Failed to decode recent projects: \(error)")
                return []
            }
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8)
            {
                setRecentJSON(json)
            }
        }
    }

    // MARK: - Public API

    /// Set the current project directory
    @discardableResult
    func setProjectDirectory(_ path: String?) -> Bool {
        guard let path, !path.isEmpty else {
            setCurrentPath("")
            Log.config("Project directory reset to default (~/.motive)")
            return true
        }

        var expandedPath = path
        if expandedPath.hasPrefix("~") {
            let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
            expandedPath = homeDir + expandedPath.dropFirst()
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expandedPath, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            Log.config("Project directory does not exist: \(expandedPath)")
            return false
        }

        setCurrentPath(expandedPath)
        addToRecentProjects(expandedPath)
        Log.config("Project directory set to: \(expandedPath)")
        return true
    }

    /// Record a recent project without changing current project
    func recordRecentProject(_ path: String) {
        guard !path.isEmpty else { return }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return
        }

        addToRecentProjects(path)
    }

    /// Ensure the current project is included in recent projects
    func ensureCurrentProjectInRecents() {
        let path = getCurrentPath()
        guard !path.isEmpty else { return }
        addToRecentProjects(path)
    }

    /// Ensure the default project directory exists
    func ensureDefaultProjectDirectory() {
        let defaultDir = Self.defaultProjectDirectory
        if !FileManager.default.fileExists(atPath: defaultDir.path) {
            do {
                try FileManager.default.createDirectory(at: defaultDir, withIntermediateDirectories: true)
                Log.config("Created default project directory: \(defaultDir.path)")
            } catch {
                Log.config("Failed to create default project directory: \(error)")
            }
        }
    }

    // MARK: - Private

    private func addToRecentProjects(_ path: String) {
        var projects = recentProjects

        projects.removeAll { $0.path == path }

        let project = RecentProject(
            path: path,
            name: URL(fileURLWithPath: path).lastPathComponent,
            lastUsed: Date()
        )
        projects.insert(project, at: 0)

        if projects.count > Self.maxRecentProjects {
            projects = Array(projects.prefix(Self.maxRecentProjects))
        }

        recentProjects = projects
    }
}
