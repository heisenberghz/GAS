//
//  PersonaSettingsView.swift
//  Motive
//
//  Settings view for editing agent persona and workspace files.
//

import AppKit
import SwiftUI

enum PersonaTab: String, CaseIterable {
    case identity
    case soul
    case user

    /// Short title for tab buttons (avoids wrapping in Japanese)
    var title: String {
        switch self {
        case .identity: L10n.Settings.personaTabIdentity
        case .soul: L10n.Settings.personaTabSoul
        case .user: L10n.Settings.personaTabUser
        }
    }

    var icon: String {
        switch self {
        case .identity: "person.crop.circle"
        case .soul: "sparkles"
        case .user: "doc.text"
        }
    }
}

struct PersonaSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedTab: PersonaTab = .identity
    @State private var identity: AgentIdentity = .init()
    @State private var soulContent: String = ""
    @State private var userContent: String = ""
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var hasChanges = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Tab bar + content in a single bordered container
            VStack(spacing: 0) {
                personaTabBar

                Divider()

                Group {
                    switch selectedTab {
                    case .identity:
                        identityContent
                    case .soul:
                        markdownEditorContent(
                            content: $soulContent,
                            placeholder: soulPlaceholder
                        )
                    case .user:
                        markdownEditorContent(
                            content: $userContent,
                            placeholder: userPlaceholder
                        )
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.Aurora.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(SettingsUIStyle.borderColor, lineWidth: SettingsUIStyle.borderWidth)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            // Footer
            footerView
        }
        .onAppear {
            loadAll()
        }
    }

    // MARK: - Tab Bar

    private var personaTabBar: some View {
        HStack(spacing: 8) {
            ForEach(PersonaTab.allCases, id: \.self) { tab in
                PersonaTabButton(
                    tab: tab,
                    isSelected: selectedTab == tab
                ) {
                    withAnimation(.auroraFast) {
                        selectedTab = tab
                    }
                }
            }

            Spacer()
        }
        .padding(10)
    }

    // MARK: - Identity Tab

    private var identityContent: some View {
        VStack(spacing: 0) {
            identityRow(
                label: L10n.Settings.personaName,
                description: L10n.Settings.personaNameDesc,
                placeholder: "Aria",
                value: Binding(
                    get: { identity.name ?? "" },
                    set: {
                        identity.name = $0.isEmpty ? nil : $0
                        hasChanges = true
                    }
                )
            )

            emojiRow(
                label: L10n.Settings.personaEmoji,
                description: L10n.Settings.personaEmojiDesc,
                value: Binding(
                    get: { identity.emoji ?? "" },
                    set: {
                        identity.emoji = $0.isEmpty ? nil : $0
                        hasChanges = true
                    }
                )
            )

            identityRow(
                label: L10n.Settings.personaCreature,
                description: L10n.Settings.personaCreatureDesc,
                placeholder: "helpful spirit",
                value: Binding(
                    get: { identity.creature ?? "" },
                    set: {
                        identity.creature = $0.isEmpty ? nil : $0
                        hasChanges = true
                    }
                )
            )

            identityRow(
                label: L10n.Settings.personaVibe,
                description: L10n.Settings.personaVibeDesc,
                placeholder: "calm and thoughtful",
                value: Binding(
                    get: { identity.vibe ?? "" },
                    set: {
                        identity.vibe = $0.isEmpty ? nil : $0
                        hasChanges = true
                    }
                ),
                showDivider: false
            )
        }
    }

    private func identityRow(
        label: String,
        description: String,
        placeholder: String,
        value: Binding<String>,
        width: CGFloat = 180,
        showDivider: Bool = true
    ) -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color.Aurora.textPrimary)
                    Text(description)
                        .font(.system(size: 12))
                        .foregroundColor(Color.Aurora.textMuted)
                }

                Spacer()

                ZStack(alignment: .leading) {
                    if value.wrappedValue.isEmpty {
                        Text(placeholder)
                            .foregroundColor(Color.Aurora.textMuted.opacity(0.5))
                            .padding(.horizontal, 10)
                    }
                    TextField("", text: value)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                }
                .frame(width: width)
                .settingsInputField(cornerRadius: 6)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if showDivider {
                Rectangle()
                    .fill(SettingsUIStyle.dividerColor)
                    .frame(height: SettingsUIStyle.borderWidth)
                    .padding(.leading, 16)
            }
        }
    }

    private func emojiRow(
        label: String,
        description: String,
        value: Binding<String>
    ) -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color.Aurora.textPrimary)
                    Text(description)
                        .font(.system(size: 12))
                        .foregroundColor(Color.Aurora.textMuted)
                }

                Spacer()

                HStack(spacing: 8) {
                    // Emoji display + hidden receiver for Character Palette
                    EmojiInputField(emoji: value)
                        .frame(width: 44, height: 36)
                        .settingsInputField(cornerRadius: 6)

                    // Emoji picker button
                    Button {
                        // Make the EmojiInputField first responder, then open picker
                        if let window = NSApp.keyWindow {
                            findAndFocusEmojiField(in: window.contentView)
                        }
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(100))
                            NSApp.orderFrontCharacterPalette(nil)
                        }
                    } label: {
                        Image(systemName: "face.smiling")
                            .font(.system(size: 14))
                            .foregroundColor(Color.Aurora.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.Aurora.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(SettingsUIStyle.borderColor, lineWidth: SettingsUIStyle.borderWidth)
                    )
                    .help(L10n.Settings.openEmojiPicker)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Rectangle()
                .fill(SettingsUIStyle.dividerColor)
                .frame(height: SettingsUIStyle.borderWidth)
                .padding(.leading, 16)
        }
    }

    private func findAndFocusEmojiField(in view: NSView?) {
        guard let view else { return }
        if let field = view as? EmojiNSTextField {
            view.window?.makeFirstResponder(field)
            return
        }
        for subview in view.subviews {
            findAndFocusEmojiField(in: subview)
        }
    }

    // MARK: - Markdown Editor Tab

    private func markdownEditorContent(
        content: Binding<String>,
        placeholder: String
    ) -> some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: Binding(
                get: { content.wrappedValue },
                set: {
                    content.wrappedValue = $0
                    hasChanges = true
                }
            ))
            .font(.system(size: 13, design: .monospaced))
            .scrollContentBackground(.hidden)
            .padding(12)

            if content.wrappedValue.isEmpty {
                Text(placeholder)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(Color.Aurora.textMuted.opacity(0.4))
                    .padding(16)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            Button {
                NSWorkspace.shared.open(WorkspaceManager.defaultWorkspaceURL)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.system(size: 11))
                    Text("~/.motive/")
                        .font(.system(size: 12))
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(Color.Aurora.textSecondary)

            Spacer()

            if hasChanges {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.Aurora.warning)
                        .frame(width: 6, height: 6)
                    Text(L10n.unsavedChanges)
                        .font(.system(size: 12))
                        .foregroundColor(Color.Aurora.textMuted)
                }
                .padding(.trailing, 8)
            }

            Button(action: saveAll) {
                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 80)
                } else {
                    Text(L10n.Settings.saveAndApply)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.Aurora.primary)
            .disabled(isSaving || !hasChanges)
        }
    }

    // MARK: - Placeholders

    private var soulPlaceholder: String {
        """
        # SOUL.md - Core Personality

        Define AI behavior guidelines:

        - Be concise and direct
        - Prioritize user's intent
        - Ask clarifying questions when needed
        - Use professional but friendly tone

        ## Special Instructions

        - Code comments in user's language
        - Prefer Swift/SwiftUI for macOS
        """
    }

    private var userPlaceholder: String {
        """
        # USER.md - About Me

        Help AI understand you better:

        - I'm a macOS developer
        - I use Swift and SwiftUI
        - My projects follow MVVM architecture
        - I prefer clean, minimal code

        ## Work Environment

        - macOS Sequoia
        - Xcode 16
        - SwiftData for persistence
        """
    }

    // MARK: - Data Operations

    private func loadAll() {
        isLoading = true

        // Load identity
        if let loaded = WorkspaceManager.shared.loadIdentity() {
            identity = loaded
        }

        // Load SOUL.md
        let soulURL = WorkspaceManager.defaultWorkspaceURL.appendingPathComponent("SOUL.md")
        if let content = try? String(contentsOf: soulURL, encoding: .utf8) {
            soulContent = content
        }

        // Load USER.md
        let userURL = WorkspaceManager.defaultWorkspaceURL.appendingPathComponent("USER.md")
        if let content = try? String(contentsOf: userURL, encoding: .utf8) {
            userContent = content
        }

        isLoading = false
        hasChanges = false
    }

    private func saveAll() {
        isSaving = true

        Task {
            do {
                // Save identity
                try await saveIdentityToFile()

                // Save SOUL.md
                let soulURL = WorkspaceManager.defaultWorkspaceURL.appendingPathComponent("SOUL.md")
                try soulContent.write(to: soulURL, atomically: true, encoding: .utf8)

                // Save USER.md
                let userURL = WorkspaceManager.defaultWorkspaceURL.appendingPathComponent("USER.md")
                try userContent.write(to: userURL, atomically: true, encoding: .utf8)

                // Restart agent to apply changes
                appState.restartAgent()

                await MainActor.run {
                    isSaving = false
                    hasChanges = false
                }
            } catch {
                Log.config("Failed to save persona: \(error)")
                await MainActor.run {
                    isSaving = false
                }
            }
        }
    }

    private func saveIdentityToFile() async throws {
        let identityURL = WorkspaceManager.defaultWorkspaceURL.appendingPathComponent("IDENTITY.md")

        // Generate markdown content
        var lines: [String] = []
        lines.append("# IDENTITY.md - Who Am I?")
        lines.append("")
        lines.append("*Configured via Motive Settings*")
        lines.append("")

        if let name = identity.name, !name.isEmpty {
            lines.append("- **Name:** \(name)")
        }

        if let emoji = identity.emoji, !emoji.isEmpty {
            lines.append("- **Emoji:** \(emoji)")
        }

        if let creature = identity.creature, !creature.isEmpty {
            lines.append("- **Creature:** \(creature)")
        }

        if let vibe = identity.vibe, !vibe.isEmpty {
            lines.append("- **Vibe:** \(vibe)")
        }

        let content = lines.joined(separator: "\n")
        try content.write(to: identityURL, atomically: true, encoding: .utf8)
    }
}

// MARK: - Persona Tab Button

private struct PersonaTabButton: View {
    let tab: PersonaTab
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: tab.icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isSelected ? Color.Aurora.primary : Color.Aurora.textSecondary)

                Text(tab.title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? Color.Aurora.textPrimary : Color.Aurora.textSecondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        isSelected ? Color.Aurora.primary.opacity(0.5) : Color.clear,
                        lineWidth: SettingsUIStyle.borderWidth
                    )
            )
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { isHovering = $0 }
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.Aurora.primary.opacity(0.12)
        } else if isHovering {
            return Color.Aurora.surfaceElevated
        }
        return Color.clear
    }
}

// MARK: - Emoji Input (NSViewRepresentable)

/// Custom NSTextField that replaces its entire content on any input.
/// When the user picks an emoji from Character Palette, it replaces — never appends.
final class EmojiNSTextField: NSTextField {
    var onEmojiInserted: ((String) -> Void)?

    override func textDidChange(_ notification: Notification) {
        guard let text = currentEditor()?.string, !text.isEmpty else { return }
        // Replace everything with the last character entered
        let emoji = String(text.last!)
        onEmojiInserted?(emoji)
        self.stringValue = emoji
        // Move cursor to end
        currentEditor()?.selectedRange = NSRange(location: emoji.count, length: 0)
    }
}

/// SwiftUI wrapper for EmojiNSTextField — displays a single emoji, replaces on new input.
struct EmojiInputField: NSViewRepresentable {
    @Binding var emoji: String

    func makeNSView(context: Context) -> EmojiNSTextField {
        let field = EmojiNSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.alignment = .center
        field.font = NSFont.systemFont(ofSize: 20)
        field.focusRingType = .none
        field.stringValue = emoji
        field.placeholderString = "🌸"
        field.onEmojiInserted = { newEmoji in
            emoji = newEmoji
        }
        return field
    }

    func updateNSView(_ nsView: EmojiNSTextField, context: Context) {
        if nsView.stringValue != emoji {
            nsView.stringValue = emoji
        }
    }
}
