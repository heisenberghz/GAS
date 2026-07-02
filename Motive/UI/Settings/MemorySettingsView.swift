//
//  MemorySettingsView.swift
//  Motive
//
//  Memory system settings panel
//

import SwiftUI

struct MemorySettingsView: View {
    @EnvironmentObject private var configManager: ConfigManager
    @EnvironmentObject private var appState: AppState

    @State private var indexFileCount: Int = 0
    @State private var indexLastSync: String = L10n.Settings.memoryNever
    @State private var memoryPreview: String = ""
    @State private var isRebuildingIndex: Bool = false
    @State private var memoryPluginAvailable: Bool = false

    private var workspaceURL: URL {
        WorkspaceManager.defaultWorkspaceURL
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Enable/Disable
            SettingSection(L10n.Settings.memorySystem) {
                SettingRow(L10n.Settings.memoryEnable, description: L10n.Settings.memoryEnableDesc) {
                    Toggle("", isOn: $configManager.memoryEnabled)
                        .toggleStyle(.switch)
                        .tint(Color.Aurora.primary)
                        .controlSize(.small)
                        .onChange(of: configManager.memoryEnabled) { _, _ in
                            appState.scheduleAgentRestart()
                        }
                }

                // TODO: Add embedding provider picker once vector search is implemented
            }

            SettingSection(L10n.Settings.memoryPluginStatus) {
                SettingRow(L10n.Settings.memoryPluginStatus, description: L10n.Settings.memoryPluginStatusDesc, showDivider: false) {
                    Text(memoryPluginAvailable ? L10n.Settings.memoryPluginAvailable : L10n.Settings.memoryPluginMissing)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(memoryPluginAvailable ? Color.Aurora.success : Color.Aurora.warning)
                        .lineLimit(1)
                }
            }

            // Index Status
            if configManager.memoryEnabled {
                SettingSection(L10n.Settings.memoryIndexStatus) {
                    SettingRow(L10n.Settings.memoryIndexedFiles, description: L10n.Settings.memoryIndexedFilesDesc) {
                        Text("\(indexFileCount)")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(Color.Aurora.textSecondary)
                    }

                    SettingRow(L10n.Settings.memoryLastSync) {
                        Text(indexLastSync)
                            .font(.system(size: 12))
                            .foregroundColor(Color.Aurora.textMuted)
                    }

                    SettingRow(L10n.Settings.memoryRebuildIndex, description: L10n.Settings.memoryRebuildIndexDesc, showDivider: false) {
                        Button {
                            rebuildIndex()
                        } label: {
                            HStack(spacing: 6) {
                                if isRebuildingIndex {
                                    ProgressView()
                                        .scaleEffect(0.5)
                                        .frame(width: 12, height: 12)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 11))
                                }
                                Text(L10n.Settings.memoryRebuild)
                                    .font(.system(size: 12, weight: .medium))
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isRebuildingIndex || !memoryPluginAvailable)
                    }
                }

                // MEMORY.md Preview
                SettingSection(L10n.Settings.memoryFileSection) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(L10n.Settings.memoryFileDesc)
                                .font(.system(size: 12))
                                .foregroundColor(Color.Aurora.textMuted)
                            Spacer()
                            Button {
                                openMemoryFile()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 10))
                                    Text(L10n.edit)
                                        .font(.system(size: 11, weight: .medium))
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)

                        ScrollView {
                            Text(memoryPreview.isEmpty ? L10n.Settings.memoryNoMemories : memoryPreview)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(memoryPreview.isEmpty ? Color.Aurora.textMuted : Color.Aurora.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                        }
                        .frame(maxHeight: 160)
                        .padding(.bottom, 12)
                    }
                }
            }
        }
        .onAppear {
            loadPluginStatus()
            loadIndexStatus()
            loadMemoryPreview()
        }
    }

    // MARK: - Actions

    private func loadIndexStatus() {
        loadPluginStatus()
        let dbPath = workspaceURL.appendingPathComponent("memory/index.sqlite")
        let fm = FileManager.default

        if !memoryPluginAvailable {
            indexFileCount = 0
            indexLastSync = L10n.Settings.memoryPluginMissing
            return
        }

        if fm.fileExists(atPath: dbPath.path) {
            let memoryDir = workspaceURL.appendingPathComponent("memory")
            let files = (try? fm.contentsOfDirectory(at: memoryDir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            indexFileCount = files.count(where: { $0.pathExtension == "md" })

            if let attrs = try? fm.attributesOfItem(atPath: dbPath.path),
               let modDate = attrs[.modificationDate] as? Date
            {
                let formatter = RelativeDateTimeFormatter()
                formatter.unitsStyle = .abbreviated
                indexLastSync = formatter.localizedString(for: modDate, relativeTo: Date())
            }
        } else {
            indexFileCount = 0
            indexLastSync = L10n.Settings.memoryNotIndexed
        }
    }

    private func loadMemoryPreview() {
        let memoryPath = workspaceURL.appendingPathComponent("MEMORY.md")
        memoryPreview = (try? String(contentsOf: memoryPath, encoding: .utf8)) ?? ""
    }

    private func rebuildIndex() {
        guard memoryPluginAvailable else { return }
        isRebuildingIndex = true
        let memoryDir = workspaceURL.appendingPathComponent("memory")
        let markerPath = memoryDir.appendingPathComponent(".rebuild")
        try? "rebuild".write(to: markerPath, atomically: true, encoding: .utf8)

        Task {
            try? await Task.sleep(for: .seconds(2))
            isRebuildingIndex = false
            loadIndexStatus()
        }
    }

    private func openMemoryFile() {
        let memoryPath = workspaceURL.appendingPathComponent("MEMORY.md")
        NSWorkspace.shared.open(memoryPath)
    }

    private func loadPluginStatus() {
        memoryPluginAvailable = WorkspaceManager.shared.hasDeployedMemoryPlugin()
    }
}
