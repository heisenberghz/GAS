//
//  SkillsSettingsView.swift
//  Motive
//
//  Compact skills management with split-pane layout
//

import Foundation
import MarkdownUI
import SwiftUI

struct SkillsSettingsView: View {
    @EnvironmentObject private var configManager: ConfigManager
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = SkillsSettingsViewModel()
    @State private var searchText: String = ""
    @State private var selectedSkillId: String?
    @State private var markdownContent: String = ""
    @State private var markdownError: String? = nil
    @State private var isMarkdownLoading: Bool = false
    @State private var showSkillBrowser: Bool = false

    /// Filtered skills based on search
    private var filteredSkills: [SkillStatusEntry] {
        if searchText.isEmpty {
            return viewModel.statusEntries
        }
        let lowercasedSearch = searchText.lowercased()
        return viewModel.statusEntries.filter { status in
            status.entry.name.lowercased().contains(lowercasedSearch) ||
                status.entry.description.lowercased().contains(lowercasedSearch)
        }
    }

    /// The currently selected skill status
    private var selectedSkill: SkillStatusEntry? {
        guard let id = selectedSkillId else { return nil }
        return viewModel.statusEntries.first { $0.entry.name == id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Controls bar
            controlsBar

            // Main content: List + Detail
            HStack(alignment: .top, spacing: 0) {
                // Skills list (left)
                skillsList
                    .frame(width: 240)

                // Divider
                Rectangle()
                    .fill(SettingsUIStyle.dividerColor)
                    .frame(width: SettingsUIStyle.borderWidth)

                // Detail panel (right)
                detailPanel
                    .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.Aurora.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(SettingsUIStyle.borderColor, lineWidth: SettingsUIStyle.borderWidth)
            )
        }
        .onAppear {
            viewModel.setConfigManager(configManager)
            viewModel.onRestartNeeded = { [weak appState] in
                appState?.scheduleAgentRestart()
            }
            if selectedSkillId == nil, let first = viewModel.statusEntries.first {
                selectedSkillId = first.entry.name
                loadMarkdown(for: first.entry)
            }
        }
        .onChange(of: viewModel.statusEntries) { _, newValue in
            if let id = selectedSkillId, newValue.contains(where: { $0.entry.name == id }) {
                return
            }
            if let first = newValue.first {
                selectedSkillId = first.entry.name
                loadMarkdown(for: first.entry)
            }
        }
        .onChange(of: selectedSkillId) { _, newValue in
            guard let id = newValue,
                  let entry = viewModel.statusEntries.first(where: { $0.entry.name == id })?.entry
            else {
                return
            }
            loadMarkdown(for: entry)
        }
        // Skill changes use scheduleAgentRestart() which waits for
        // any running task to finish before restarting the agent.
        .sheet(isPresented: $showSkillBrowser) {
            SkillBrowserView()
                .environmentObject(configManager)
                .environmentObject(appState)
        }
    }

    // MARK: - Controls Bar

    private var controlsBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                // Enable toggle
                HStack(spacing: 8) {
                    Toggle("", isOn: $configManager.skillsSystemEnabled)
                        .toggleStyle(.switch)
                        .tint(Color.Aurora.primary)
                        .scaleEffect(0.85)
                        .controlSize(.small)
                        .onChange(of: configManager.skillsSystemEnabled) { _, _ in
                            viewModel.refresh()
                        }

                    Text(L10n.Settings.skillsEnable)
                        .font(.system(size: 13))
                        .foregroundColor(Color.Aurora.textSecondary)
                }

                Spacer()

                // Search field
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundColor(Color.Aurora.textMuted)

                    TextField(L10n.Settings.skillsSearch, text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .frame(width: 120)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.Aurora.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(SettingsUIStyle.borderColor, lineWidth: SettingsUIStyle.borderWidth)
                )

                // Refresh button
                Button {
                    viewModel.refresh()
                } label: {
                    Group {
                        if viewModel.isLoading {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12))
                        }
                    }
                    .foregroundColor(Color.Aurora.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.Aurora.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(SettingsUIStyle.borderColor, lineWidth: SettingsUIStyle.borderWidth)
                    )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isLoading)
                .accessibilityLabel(L10n.Settings.skillsRefreshA11y)

                // Browse button
                Button {
                    showSkillBrowser = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "globe")
                            .font(.system(size: 11))
                        Text("Browse")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(Color.Aurora.textSecondary)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.Aurora.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(SettingsUIStyle.borderColor, lineWidth: SettingsUIStyle.borderWidth)
                    )
                }
                .buttonStyle(.plain)
            }

            // Pending-restart banner — shown when restart is deferred until task finishes
            if appState.pendingAgentRestart {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)

                    Text(L10n.Settings.skillsRestartPending)
                        .font(.system(size: 12))
                        .foregroundColor(Color.Aurora.textSecondary)

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.Aurora.info.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.Aurora.info.opacity(0.3), lineWidth: SettingsUIStyle.borderWidth)
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.auroraFast, value: appState.pendingAgentRestart)
            }
        }
        .padding(.bottom, 12)
    }

    // MARK: - Skills List

    private var skillsList: some View {
        Group {
            if viewModel.isLoading, viewModel.statusEntries.isEmpty {
                VStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(L10n.loading)
                        .font(.system(size: 11))
                        .foregroundColor(Color.Aurora.textMuted)
                        .padding(.top, 8)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if filteredSkills.isEmpty {
                VStack {
                    Spacer()
                    Image(systemName: "sparkles")
                        .font(.system(size: 24))
                        .foregroundColor(Color.Aurora.textMuted)
                    Text(searchText.isEmpty ? L10n.Settings.skillsNoSkills : L10n.Settings.skillsNoMatch)
                        .font(.system(size: 12))
                        .foregroundColor(Color.Aurora.textMuted)
                        .padding(.top, 8)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredSkills) { status in
                            SkillListItem(
                                status: status,
                                isSelected: selectedSkillId == status.entry.name,
                                onSelect: {
                                    selectedSkillId = status.entry.name
                                },
                                onToggle: { enabled in
                                    viewModel.toggleSkill(status.entry.name, enabled: enabled)
                                }
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - Detail Panel

    private var detailPanel: some View {
        Group {
            if let skill = selectedSkill {
                SkillDetail(
                    status: skill,
                    markdownContent: markdownContent,
                    markdownError: markdownError,
                    isMarkdownLoading: isMarkdownLoading,
                    isBusy: viewModel.installingSkillKey == skill.entry.name,
                    installMessage: viewModel.installMessages[skill.entry.name],
                    currentApiKey: viewModel.getApiKey(for: skill.entry.name),
                    onToggle: { enabled in
                        viewModel.toggleSkill(skill.entry.name, enabled: enabled)
                    },
                    onInstall: { option in
                        Task {
                            await viewModel.install(skill.entry, option: option)
                        }
                    },
                    onSaveApiKey: { key in
                        viewModel.saveApiKey(for: skill.entry.name, key: key)
                    }
                )
            } else {
                VStack {
                    Spacer()
                    Image(systemName: "doc.text")
                        .font(.system(size: 32))
                        .foregroundColor(Color.Aurora.textMuted)
                    Text(L10n.Settings.skillsSelect)
                        .font(.system(size: 13))
                        .foregroundColor(Color.Aurora.textMuted)
                        .padding(.top, 8)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func loadMarkdown(for entry: SkillEntry) {
        let path = entry.filePath
        isMarkdownLoading = true
        markdownError = nil
        markdownContent = ""

        DispatchQueue.global(qos: .userInitiated).async {
            let content = try? String(contentsOfFile: path, encoding: .utf8)
            let sanitized = content.map(stripFrontmatter(from:)) ?? ""
            DispatchQueue.main.async {
                isMarkdownLoading = false
                if !sanitized.isEmpty {
                    markdownContent = sanitized
                } else {
                    markdownError = L10n.Settings.skillsUnableToLoad
                }
            }
        }
    }

    private func stripFrontmatter(from content: String) -> String {
        guard content.hasPrefix("---") else { return content }
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > 2 else { return content }
        var endIndex: Int?
        for i in 1 ..< lines.count {
            if lines[i].trimmingCharacters(in: .whitespacesAndNewlines) == "---" {
                endIndex = i
                break
            }
        }
        guard let endIndex else { return content }
        let remaining = lines[(endIndex + 1)...].joined(separator: "\n")
        return remaining.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
