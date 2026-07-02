import Foundation

@MainActor
extension ConfigManager {
    var skillsConfig: SkillsConfig {
        get {
            guard let data = skillsConfigJSON.data(using: .utf8),
                  let config = try? JSONDecoder().decode(SkillsConfig.self, from: data)
            else {
                return SkillsConfig()
            }
            return config
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8)
            {
                skillsConfigJSON = json
            }
        }
    }

    func skillEntryConfig(for name: String) -> SkillEntryConfig? {
        let config = skillsConfig
        return config.entries[name]
    }

    func updateSkillEntryConfig(name: String, update: (inout SkillEntryConfig) -> Void) {
        var config = skillsConfig
        var entry = config.entries[name] ?? SkillEntryConfig()
        update(&entry)
        config.entries[name] = entry
        skillsConfig = config
    }
}
