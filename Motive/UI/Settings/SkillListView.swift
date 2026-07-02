//
//  SkillListView.swift
//  Motive
//
//  Skill list status enum and list item view
//

import SwiftUI

// MARK: - Skill Status Type

// Two dimensions:
// 1. Dependency: Ready (deps satisfied) vs Blocked (missing deps)
// 2. Enabled: Enabled vs Disabled (only meaningful when Ready)

enum SkillListStatus {
    case blockedDisabled // Missing deps + disabled
    case blockedEnabled // Missing deps + enabled (shouldn't happen but handle it)
    case readyDisabled // Deps OK but disabled
    case readyEnabled // Deps OK and enabled - fully active

    var color: Color {
        switch self {
        case .blockedDisabled, .blockedEnabled:
            Color.Aurora.warning // Orange for blocked
        case .readyDisabled:
            Color.Aurora.textMuted // Gray for disabled
        case .readyEnabled:
            Color.Aurora.success // Green for active
        }
    }

    var icon: String {
        switch self {
        case .blockedDisabled, .blockedEnabled:
            "exclamationmark.circle.fill" // Warning for blocked
        case .readyDisabled:
            "minus.circle.fill" // Minus for disabled
        case .readyEnabled:
            "checkmark.circle.fill" // Check for active
        }
    }
}

// MARK: - Skill List Item

struct SkillListItem: View {
    let status: SkillStatusEntry
    let isSelected: Bool
    let onSelect: () -> Void
    let onToggle: (Bool) -> Void

    @State private var isHovering = false

    /// Determine the display status based on dependency and enabled state
    private var listStatus: SkillListStatus {
        let isBlocked = !status.missing.isEmpty
        let isDisabled = status.disabled

        if isBlocked {
            return isDisabled ? .blockedDisabled : .blockedEnabled
        } else {
            return isDisabled ? .readyDisabled : .readyEnabled
        }
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                // Emoji or icon
                Group {
                    if let emoji = status.entry.metadata?.emoji {
                        Text(emoji)
                            .font(.system(size: 16))
                    } else {
                        Image(systemName: "sparkle")
                            .font(.system(size: 12))
                            .foregroundColor(Color.Aurora.textMuted)
                    }
                }
                .frame(width: 24)

                // Name only (description in detail panel)
                Text(status.entry.name)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(status.disabled ? Color.Aurora.textMuted : Color.Aurora.textPrimary)
                    .lineLimit(1)

                Spacer()

                // Status indicator with icon
                Image(systemName: listStatus.icon)
                    .font(.system(size: 10))
                    .foregroundColor(listStatus.color)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(backgroundColor)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
