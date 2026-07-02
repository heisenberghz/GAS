//
//  ConfigManager+Project.swift
//  Motive
//
//  Thin facade delegating to ProjectManager.
//

import Foundation

extension ConfigManager {
    // MARK: - Project Directory Management (delegated to ProjectManager)

    /// Default global working directory when no project is selected
    static var defaultProjectDirectory: URL {
        ProjectManager.defaultProjectDirectory
    }

    /// Maximum number of recent projects to keep
    static var maxRecentProjects: Int {
        ProjectManager.maxRecentProjects
    }

    /// Get the current project directory URL
    var currentProjectURL: URL {
        projectManager.currentProjectURL
    }

    /// Get the display name for current project
    var currentProjectDisplayName: String {
        projectManager.currentProjectDisplayName
    }

    /// Get shortened path for display (replaces home with ~)
    var currentProjectShortPath: String {
        projectManager.currentProjectShortPath
    }

    /// Recent projects list
    var recentProjects: [RecentProject] {
        get { projectManager.recentProjects }
        set { projectManager.recentProjects = newValue }
    }

    /// Set the current project directory
    @discardableResult
    func setProjectDirectory(_ path: String?) -> Bool {
        projectManager.setProjectDirectory(path)
    }

    /// Record a recent project without changing current project
    func recordRecentProject(_ path: String) {
        projectManager.recordRecentProject(path)
    }

    /// Ensure the current project is included in recent projects
    func ensureCurrentProjectInRecents() {
        projectManager.ensureCurrentProjectInRecents()
    }

    /// Ensure the default project directory exists
    func ensureDefaultProjectDirectory() {
        projectManager.ensureDefaultProjectDirectory()
    }
}

// MARK: - Recent Project Model

struct RecentProject: Codable, Identifiable, Equatable, Sendable {
    var id: String {
        path
    }

    let path: String
    let name: String
    let lastUsed: Date

    /// Get shortened path for display (replaces home with ~)
    var shortPath: String {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(homeDir) {
            return "~" + path.dropFirst(homeDir.count)
        }
        return path
    }
}
