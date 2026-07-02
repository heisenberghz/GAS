//
//  SkillsSettingsViewModel.swift
//  Motive
//
//  ViewModel for Skills settings UI.
//

import Combine
import Foundation

@MainActor
final class SkillsSettingsViewModel: ObservableObject {
    @Published var statusEntries: [SkillStatusEntry] = []
    @Published var installingSkillKey: String? = nil
    @Published var installMessages: [String: SkillInstallMessage] = [:]
    @Published var isLoading: Bool = false
    @Published var error: String? = nil

    /// Called when a config change requires an agent restart.
    var onRestartNeeded: (() -> Void)?

    struct SkillInstallMessage: Equatable {
        var kind: MessageKind
        var message: String

        enum MessageKind {
            case success
            case error
        }
    }

    private let registry: SkillRegistry
    private let installer: SkillInstallerProtocol
    private let commandRunner: CommandRunnerProtocol
    private weak var configManager: ConfigManager?
    private var cancellables = Set<AnyCancellable>()
    private var loadTask: Task<Void, Never>?

    init(
        registry: SkillRegistry = .shared,
        installer: SkillInstallerProtocol? = nil,
        commandRunner: CommandRunnerProtocol? = nil,
        configManager: ConfigManager? = nil
    ) {
        self.registry = registry
        self.commandRunner = commandRunner ?? CommandRunner.shared
        self.installer = installer ?? SkillInstaller(commandRunner: self.commandRunner)
        self.configManager = configManager

        // Subscribe to registry changes
        registry.$entries
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshStatusEntriesAsync()
            }
            .store(in: &cancellables)
    }

    func setConfigManager(_ manager: ConfigManager) {
        self.configManager = manager
        refreshStatusEntriesAsync()
    }

    func refresh() {
        // Clear binary cache to pick up newly installed tools
        if let runner = commandRunner as? CommandRunner {
            runner.clearBinaryCache()
        }
        registry.refresh()
        refreshStatusEntriesAsync()
    }

    private func refreshStatusEntriesAsync() {
        loadTask?.cancel()
        isLoading = true
        error = nil

        let config = configManager?.skillsConfig ?? SkillsConfig()
        let entries = registry.entries
        let runner = commandRunner

        loadTask = Task.detached(priority: .userInitiated) { [weak self] in
            // Build status entries off main thread
            let statuses = entries.map { entry in
                SkillGating.buildStatus(
                    entry: entry,
                    config: config,
                    commandRunner: runner
                )
            }

            await MainActor.run { [weak self] in
                guard let self, !Task.isCancelled else { return }
                self.statusEntries = statuses
                self.isLoading = false
            }
        }
    }

    func toggleSkill(_ name: String, enabled: Bool) {
        guard let configManager else { return }

        // Prevent enabling blocked skills (skills with missing dependencies)
        if enabled {
            if let status = statusEntries.first(where: { $0.entry.name == name }),
               !status.missing.isEmpty
            {
                // Skill is blocked - cannot enable
                return
            }
        }

        var skillsConfig = configManager.skillsConfig
        var entryConfig = skillsConfig.entries[name] ?? SkillEntryConfig()
        entryConfig.enabled = enabled
        skillsConfig.entries[name] = entryConfig
        configManager.skillsConfig = skillsConfig

        registry.refresh()
        refreshStatusEntriesAsync()

        // Regenerate OpenCode config so the updated skills list is applied
        // This uses whitelist approach: deny all, only allow enabled skills
        configManager.generateOpenCodeConfig()

        onRestartNeeded?()
    }

    func install(_ entry: SkillEntry, option: SkillInstallOption) async {
        guard let spec = findInstallSpec(entry: entry, optionId: option.id) else {
            installMessages[entry.name] = SkillInstallMessage(
                kind: .error,
                message: "Install spec not found"
            )
            return
        }

        installingSkillKey = entry.name
        installMessages[entry.name] = nil

        // Clear binary cache before install
        if let runner = commandRunner as? CommandRunner {
            runner.clearBinaryCache()
        }

        let result = await installer.install(spec: spec, timeoutSeconds: 120)

        installMessages[entry.name] = SkillInstallMessage(
            kind: result.ok ? .success : .error,
            message: result.message
        )

        installingSkillKey = nil

        // Clear cache again and refresh to update dependency status
        if let runner = commandRunner as? CommandRunner {
            runner.clearBinaryCache()
        }
        registry.refresh()
        refreshStatusEntriesAsync()
    }

    func clearInstallMessage(for name: String) {
        installMessages[name] = nil
    }

    // MARK: - API Key Management

    func getApiKey(for skillName: String) -> String {
        guard let configManager else { return "" }
        let skillsConfig = configManager.skillsConfig
        return skillsConfig.entries[skillName]?.apiKey ?? ""
    }

    func saveApiKey(for skillName: String, key: String) {
        guard let configManager else { return }

        var skillsConfig = configManager.skillsConfig
        var entryConfig = skillsConfig.entries[skillName] ?? SkillEntryConfig()
        entryConfig.apiKey = key
        skillsConfig.entries[skillName] = entryConfig
        configManager.skillsConfig = skillsConfig

        // Refresh to update eligibility based on new API key
        registry.refresh()
        refreshStatusEntriesAsync()

        // Regenerate OpenCode config so updated environment variables are applied
        configManager.generateOpenCodeConfig()

        onRestartNeeded?()
    }

    private func findInstallSpec(entry: SkillEntry, optionId: String) -> SkillInstallSpec? {
        guard let installSpecs = entry.metadata?.install else { return nil }

        for (index, spec) in installSpecs.enumerated() {
            let id = spec.id ?? "\(spec.kind.rawValue)-\(index)"
            if id == optionId {
                return spec
            }
        }

        return nil
    }
}
