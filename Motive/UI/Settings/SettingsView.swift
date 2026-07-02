//
//  SettingsView.swift
//  Motive
//
//  Settings Window
//  Premium macOS-native layout with sidebar navigation
//

import SwiftUI

// MARK: - Settings View

struct SettingsView: View {
    var initialTab: SettingsTab = .general
    @State private var selectedTab: SettingsTab? = .general
    @State private var searchText: String = ""
    init(initialTab: SettingsTab = .general) {
        self.initialTab = initialTab
        _selectedTab = State(initialValue: initialTab)
    }

    private var activeTab: SettingsTab {
        selectedTab ?? .general
    }

    private var filteredTabs: [SettingsTab] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return SettingsTab.allCases }
        return SettingsTab.allCases.filter { tab in
            tab.title.lowercased().contains(query) || tab.subtitle.lowercased().contains(query)
        }
    }

    var body: some View {
        NavigationSplitView {
            List(filteredTabs, selection: $selectedTab) { tab in
                Label(tab.title, systemImage: tab.icon)
                    .font(.Aurora.body)
                    .tag(tab)
                    .accessibilityLabel(tab.title)
                    .accessibilityHint(L10n.Settings.openSettingsHintFormat.localized(with: tab.title))
            }
            .tint(SettingsUIStyle.selectionTint)
            .listStyle(.sidebar)
            .frame(minWidth: 220)
            .searchable(text: $searchText, placement: .sidebar, prompt: L10n.Settings.searchPrompt)
        } detail: {
            SettingsDetailView(tab: activeTab)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(width: activeTab.windowSize.width, height: activeTab.windowSize.height)
        .background(Color.Aurora.background)
    }
}

// MARK: - Settings Tab

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case scheduledTasks
    case persona
    case model
    case usage
    case skills
    case memory
    case permissions
    case advanced
    case about

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .general: L10n.Settings.general
        case .scheduledTasks: L10n.Settings.scheduledTasks
        case .persona: L10n.Settings.persona
        case .model: L10n.Settings.aiProvider
        case .usage: L10n.Settings.usage
        case .skills: L10n.Settings.skills
        case .memory: L10n.Settings.memory
        case .permissions: L10n.Settings.permissions
        case .advanced: L10n.Settings.advanced
        case .about: L10n.Settings.about
        }
    }

    var subtitle: String {
        switch self {
        case .general: L10n.Settings.generalSubtitle
        case .scheduledTasks: L10n.Settings.scheduledTasksSubtitle
        case .persona: L10n.Settings.personaSubtitle
        case .model: L10n.Settings.aiProviderSubtitle
        case .usage: L10n.Settings.usageSubtitle
        case .skills: L10n.Settings.skillsSubtitle
        case .memory: L10n.Settings.memorySubtitle
        case .permissions: L10n.Settings.permissionsSubtitle
        case .advanced: L10n.Settings.advancedSubtitle
        case .about: L10n.Settings.aboutSubtitle
        }
    }

    var icon: String {
        switch self {
        case .general: "gearshape.fill"
        case .scheduledTasks: "calendar.badge.clock"
        case .persona: "person.fill"
        case .model: "cpu.fill"
        case .usage: "chart.bar.fill"
        case .skills: "sparkles"
        case .memory: "brain.fill"
        case .permissions: "lock.shield.fill"
        case .advanced: "wrench.and.screwdriver.fill"
        case .about: "info.circle.fill"
        }
    }

    /// Fixed window size for all tabs
    var windowSize: CGSize {
        CGSize(width: 920, height: 640)
    }

    @ViewBuilder
    var contentView: some View {
        switch self {
        case .general:
            GeneralSettingsView()
        case .scheduledTasks:
            ScheduledTasksSettingsView()
        case .persona:
            PersonaSettingsView()
        case .model:
            ModelConfigView()
        case .usage:
            UsageSettingsView()
        case .skills:
            SkillsSettingsView()
        case .memory:
            MemorySettingsView()
        case .permissions:
            PermissionPolicyView()
        case .advanced:
            AdvancedSettingsView()
        case .about:
            AboutView()
        }
    }
}

// MARK: - Settings Detail

private struct SettingsDetailView: View {
    let tab: SettingsTab

    var body: some View {
        VStack(alignment: .leading, spacing: AuroraSpacing.space4) {
            HStack(alignment: .center, spacing: AuroraSpacing.space2 + 2) {
                Image(systemName: tab.icon)
                    .font(.Aurora.headline.weight(.semibold))
                    .foregroundColor(Color.Aurora.microAccent)
                Text(tab.title)
                    .font(.Aurora.title2)
                    .foregroundColor(Color.Aurora.textPrimary)
            }
            .padding(.horizontal, AuroraSpacing.space7)
            .padding(.top, AuroraSpacing.space6)

            Text(tab.subtitle)
                .font(.Aurora.bodySmall)
                .foregroundColor(Color.Aurora.textSecondary)
                .padding(.horizontal, AuroraSpacing.space7)

            Divider()
                .padding(.horizontal, AuroraSpacing.space7)

            Group {
                if tab == .skills || tab == .advanced {
                    tab.contentView
                        .padding(.horizontal, AuroraSpacing.space7)
                        .padding(.bottom, AuroraSpacing.space6)
                } else {
                    ScrollView {
                        tab.contentView
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, AuroraSpacing.space7)
                            .padding(.bottom, AuroraSpacing.space6)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.Aurora.background)
    }
}

// MARK: - New Setting Section Component

struct SettingSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AuroraSpacing.space2 + 2) {
            Text(title)
                .font(.Aurora.caption.weight(.semibold))
                .foregroundColor(Color.Aurora.textSecondary)
                .textCase(.uppercase)
                .tracking(0.6)
                .padding(.leading, 2)

            VStack(spacing: 0) {
                content
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.Aurora.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(SettingsUIStyle.borderColor, lineWidth: SettingsUIStyle.borderWidth)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.Aurora.microAccent.opacity(0.07), lineWidth: 0.5)
            )
        }
    }
}

// MARK: - New Setting Row Component

struct SettingRow<Content: View>: View {
    let label: String
    var description: String?
    let content: Content
    var showDivider: Bool = true

    init(_ label: String, description: String? = nil, showDivider: Bool = true, @ViewBuilder content: () -> Content) {
        self.label = label
        self.description = description
        self.showDivider = showDivider
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: AuroraSpacing.space4) {
                // Label
                VStack(alignment: .leading, spacing: 3) {
                    Text(label)
                        .font(.Aurora.bodySmall.weight(.medium))
                        .foregroundColor(Color.Aurora.textPrimary)

                    if let description {
                        Text(description)
                            .font(.Aurora.caption.weight(.regular))
                            .foregroundColor(Color.Aurora.textMuted)
                            .lineLimit(2)
                    }
                }

                Spacer()

                // Control
                content
            }
            .padding(.horizontal, AuroraSpacing.space4)
            .padding(.vertical, AuroraSpacing.space3)

            // Divider
            if showDivider {
                Rectangle()
                    .fill(SettingsUIStyle.dividerColor)
                    .frame(height: SettingsUIStyle.borderWidth)
                    .padding(.leading, AuroraSpacing.space4)
            }
        }
    }
}

// MARK: - Collapsible Section (for Advanced)

struct CollapsibleSection<Content: View>: View {
    let title: String
    var icon: String?
    let content: Content

    @State private var isExpanded: Bool = true

    init(_ title: String, icon: String? = nil, expanded: Bool = true, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self._isExpanded = State(initialValue: expanded)
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header (clickable)
            Button {
                withAnimation(.auroraFast) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.Aurora.caption.weight(.semibold))
                            .foregroundColor(Color.Aurora.microAccent)
                    }

                    Text(title)
                        .font(.Aurora.caption.weight(.semibold))
                        .foregroundColor(Color.Aurora.textSecondary)
                        .textCase(.uppercase)
                        .tracking(0.5)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.Aurora.micro.weight(.semibold))
                        .foregroundColor(Color.Aurora.textMuted)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Content
            if isExpanded {
                VStack(spacing: 0) {
                    content
                }
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.Aurora.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(SettingsUIStyle.borderColor, lineWidth: SettingsUIStyle.borderWidth)
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Shared Settings Styling

enum SettingsUIStyle {
    static let borderColor = Color.Aurora.border.opacity(0.45)
    static let dividerColor = Color.Aurora.border.opacity(0.42)
    static let borderWidth: CGFloat = 0.75
    static let selectionTint = Color.Aurora.primary
    static let actionTint = Color.Aurora.primary
}

private struct SettingsInputFieldModifier: ViewModifier {
    let cornerRadius: CGFloat
    let borderColor: Color?
    @Environment(\.colorScheme) private var colorScheme

    private var backgroundColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.02)
    }

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(borderColor ?? SettingsUIStyle.borderColor, lineWidth: SettingsUIStyle.borderWidth)
            )
    }
}

extension View {
    func settingsSoftBorder(cornerRadius: CGFloat) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(SettingsUIStyle.borderColor, lineWidth: SettingsUIStyle.borderWidth)
        )
    }

    func settingsInputField(cornerRadius: CGFloat = 6, borderColor: Color? = nil) -> some View {
        modifier(SettingsInputFieldModifier(cornerRadius: cornerRadius, borderColor: borderColor))
    }
}
