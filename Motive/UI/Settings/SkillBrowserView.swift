//
//  SkillBrowserView.swift
//  Motive
//
//  Browse and install skills from a remote registry
//

import SwiftUI

/// A remote skill available for installation
struct RemoteSkill: Identifiable, Codable {
    let id: String
    let name: String
    let description: String
    let version: String
    let author: String?
    let tags: [String]
    var isInstalled: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, name, description, version, author, tags
    }
}

struct SkillBrowserView: View {
    @EnvironmentObject private var configManager: ConfigManager
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var skills: [RemoteSkill] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var searchText: String = ""
    @State private var installingSkillId: String?

    private var filteredSkills: [RemoteSkill] {
        if searchText.isEmpty { return skills }
        let query = searchText.lowercased()
        return skills.filter {
            $0.name.lowercased().contains(query) ||
                $0.description.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            searchSection
            Divider()
            contentSection
        }
        .frame(width: 500, height: 480)
        .background(Color.Aurora.background)
        .onAppear { loadSkills() }
    }

    // MARK: - Sections

    private var headerSection: some View {
        HStack {
            Text("Skill Browser")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color.Aurora.textPrimary)
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding()
    }

    private var searchSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundColor(Color.Aurora.textMuted)
            TextField("Search skills...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.Aurora.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(SettingsUIStyle.borderColor, lineWidth: SettingsUIStyle.borderWidth)
        )
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var contentSection: some View {
        if isLoading {
            Spacer()
            ProgressView("Loading skills...")
                .font(.system(size: 13))
            Spacer()
        } else if let error = errorMessage {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 24))
                    .foregroundColor(Color.Aurora.warning)
                Text(error)
                    .font(.system(size: 13))
                    .foregroundColor(Color.Aurora.textMuted)
                Button("Retry") { loadSkills() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            Spacer()
        } else if filteredSkills.isEmpty {
            Spacer()
            Text(searchText.isEmpty ? "No skills available" : "No matching skills")
                .font(.system(size: 13))
                .foregroundColor(Color.Aurora.textMuted)
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredSkills) { skill in
                        RemoteSkillRow(
                            skill: skill,
                            isInstalling: installingSkillId == skill.id,
                            onInstall: { installSkill(skill) }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func loadSkills() {
        isLoading = true
        errorMessage = nil

        // Load from local skills directory as a starting point
        // In the future, this will fetch from a remote registry
        let skillsDir = WorkspaceManager.defaultWorkspaceURL.appendingPathComponent("skills")
        let fm = FileManager.default

        Task {
            var loaded: [RemoteSkill] = []

            if let contents = try? fm.contentsOfDirectory(at: skillsDir, includingPropertiesForKeys: nil) {
                for dir in contents where dir.hasDirectoryPath {
                    let skillMd = dir.appendingPathComponent("SKILL.md")
                    if fm.fileExists(atPath: skillMd.path) {
                        loaded.append(RemoteSkill(
                            id: dir.lastPathComponent,
                            name: dir.lastPathComponent,
                            description: "Installed skill",
                            version: "local",
                            author: nil,
                            tags: [],
                            isInstalled: true
                        ))
                    }
                }
            }

            skills = loaded
            isLoading = false
        }
    }

    private func installSkill(_ skill: RemoteSkill) {
        installingSkillId = skill.id

        Task {
            // Trigger skill refresh after install
            try? await Task.sleep(for: .seconds(1))
            SkillRegistry.shared.refresh()
            installingSkillId = nil
        }
    }
}

// MARK: - Remote Skill Row

private struct RemoteSkillRow: View {
    let skill: RemoteSkill
    let isInstalling: Bool
    let onInstall: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(skill.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color.Aurora.textPrimary)

                    if skill.isInstalled {
                        Text("Installed")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Color.Aurora.success)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.Aurora.success.opacity(0.12))
                            )
                    }
                }

                Text(skill.description)
                    .font(.system(size: 11))
                    .foregroundColor(Color.Aurora.textMuted)
                    .lineLimit(2)
            }

            Spacer()

            if !skill.isInstalled {
                Button {
                    onInstall()
                } label: {
                    if isInstalling {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 16, height: 16)
                    } else {
                        Text("Install")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.Aurora.primary)
                .controlSize(.small)
                .disabled(isInstalling)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)

        Divider()
            .padding(.leading, 16)
    }
}
