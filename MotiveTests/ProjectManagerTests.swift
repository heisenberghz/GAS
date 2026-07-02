import Foundation
@testable import Motive
import Testing

@Suite("ProjectManager")
struct ProjectManagerTests {

    @Test @MainActor func defaultProjectURL() {
        var path = ""
        var json = "[]"
        let manager = ProjectManager(
            getCurrentPath: { path },
            setCurrentPath: { path = $0 },
            getRecentJSON: { json },
            setRecentJSON: { json = $0 }
        )
        let expected = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".motive")
        #expect(manager.currentProjectURL == expected)
    }

    @Test @MainActor func defaultDisplayName() {
        var path = ""
        var json = "[]"
        let manager = ProjectManager(
            getCurrentPath: { path },
            setCurrentPath: { path = $0 },
            getRecentJSON: { json },
            setRecentJSON: { json = $0 }
        )
        #expect(manager.currentProjectDisplayName == "~/.motive")
    }

    @Test @MainActor func defaultShortPath() {
        var path = ""
        var json = "[]"
        let manager = ProjectManager(
            getCurrentPath: { path },
            setCurrentPath: { path = $0 },
            getRecentJSON: { json },
            setRecentJSON: { json = $0 }
        )
        #expect(manager.currentProjectShortPath == "~/.motive")
    }

    @Test @MainActor func setProjectDirectoryToNilResets() {
        var path = "/some/path"
        var json = "[]"
        let manager = ProjectManager(
            getCurrentPath: { path },
            setCurrentPath: { path = $0 },
            getRecentJSON: { json },
            setRecentJSON: { json = $0 }
        )
        let result = manager.setProjectDirectory(nil)
        #expect(result == true)
        #expect(path == "")
    }

    @Test @MainActor func setProjectDirectoryToEmptyResets() {
        var path = "/some/path"
        var json = "[]"
        let manager = ProjectManager(
            getCurrentPath: { path },
            setCurrentPath: { path = $0 },
            getRecentJSON: { json },
            setRecentJSON: { json = $0 }
        )
        let result = manager.setProjectDirectory("")
        #expect(result == true)
        #expect(path == "")
    }

    @Test @MainActor func setProjectDirectoryToExistingPath() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("motive-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        var path = ""
        var json = "[]"
        let manager = ProjectManager(
            getCurrentPath: { path },
            setCurrentPath: { path = $0 },
            getRecentJSON: { json },
            setRecentJSON: { json = $0 }
        )
        let result = manager.setProjectDirectory(tempDir.path)
        #expect(result == true)
        #expect(path == tempDir.path)
    }

    @Test @MainActor func setProjectDirectoryToNonexistentFails() {
        var path = ""
        var json = "[]"
        let manager = ProjectManager(
            getCurrentPath: { path },
            setCurrentPath: { path = $0 },
            getRecentJSON: { json },
            setRecentJSON: { json = $0 }
        )
        let result = manager.setProjectDirectory("/nonexistent/path/that/does/not/exist")
        #expect(result == false)
        #expect(path == "")
    }

    @Test @MainActor func shortPathReplacesHomeWithTilde() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let testPath = homeDir + "/Projects/MyApp"
        var path = testPath
        var json = "[]"
        let manager = ProjectManager(
            getCurrentPath: { path },
            setCurrentPath: { path = $0 },
            getRecentJSON: { json },
            setRecentJSON: { json = $0 }
        )
        #expect(manager.currentProjectShortPath == "~/Projects/MyApp")
    }

    @Test @MainActor func ensureDefaultProjectDirectoryCreatesDir() {
        var path = ""
        var json = "[]"
        let manager = ProjectManager(
            getCurrentPath: { path },
            setCurrentPath: { path = $0 },
            getRecentJSON: { json },
            setRecentJSON: { json = $0 }
        )
        manager.ensureDefaultProjectDirectory()
        let exists = FileManager.default.fileExists(atPath: ProjectManager.defaultProjectDirectory.path)
        #expect(exists == true)
    }

    @Test @MainActor func recentProjectsStartEmpty() {
        var path = ""
        var json = "[]"
        let manager = ProjectManager(
            getCurrentPath: { path },
            setCurrentPath: { path = $0 },
            getRecentJSON: { json },
            setRecentJSON: { json = $0 }
        )
        #expect(manager.recentProjects.isEmpty)
    }

    @Test @MainActor func recordRecentProjectAddsToList() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("motive-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        var path = ""
        var json = "[]"
        let manager = ProjectManager(
            getCurrentPath: { path },
            setCurrentPath: { path = $0 },
            getRecentJSON: { json },
            setRecentJSON: { json = $0 }
        )
        manager.recordRecentProject(tempDir.path)
        #expect(manager.recentProjects.count == 1)
        #expect(manager.recentProjects[0].path == tempDir.path)
    }

    @Test @MainActor func recordRecentProjectSkipsNonexistent() {
        var path = ""
        var json = "[]"
        let manager = ProjectManager(
            getCurrentPath: { path },
            setCurrentPath: { path = $0 },
            getRecentJSON: { json },
            setRecentJSON: { json = $0 }
        )
        manager.recordRecentProject("/nonexistent/path")
        #expect(manager.recentProjects.isEmpty)
    }
}
