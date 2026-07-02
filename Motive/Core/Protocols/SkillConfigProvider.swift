//
//  SkillConfigProvider.swift
//  Motive
//
//  Protocol to break SkillRegistry's direct dependency on ConfigManager.
//

import Foundation

@MainActor
protocol SkillConfigProvider: AnyObject {
    var skillsSystemEnabled: Bool { get }
    var skillsConfig: SkillsConfig { get }
    var skillsManagedDirectoryURL: URL? { get }
    var currentProjectURL: URL { get }
}
