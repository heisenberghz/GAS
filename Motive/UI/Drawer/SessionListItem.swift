//
//  SessionListItem.swift
//  Motive
//
//  Aurora Design System - Drawer Components
//

import SwiftUI

// MARK: - Session List Item

struct SessionListItem: View {
    let session: Session
    var isDark: Bool = true
    let onSelect: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: AuroraSpacing.space3) {
                // Status indicator with gradient for active
                Circle()
                    .fill(statusGradient)
                    .frame(width: 6, height: 6)

                // Content
                VStack(alignment: .leading, spacing: AuroraSpacing.space1) {
                    Text(session.intent)
                        .font(.Aurora.bodySmall.weight(.medium))
                        .foregroundColor(Color.Aurora.textPrimary)
                        .lineLimit(1)

                    Text(timeAgo)
                        .font(.Aurora.micro)
                        .foregroundColor(Color.Aurora.textMuted)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color.Aurora.textMuted)
                    .opacity(isHovering ? 1 : 0)
            }
            .padding(.horizontal, AuroraSpacing.space3)
            .padding(.vertical, AuroraSpacing.space3)
            .background(
                RoundedRectangle(cornerRadius: AuroraRadius.sm, style: .continuous)
                    .fill(isHovering ? Color.Aurora.glassOverlay.opacity(0.06) : Color.clear)
            )
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(.auroraFast) {
                    isHovering = hovering
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var statusGradient: AnyShapeStyle {
        switch session.status {
        case "running":
            AnyShapeStyle(Color.Aurora.primary)
        case "completed":
            AnyShapeStyle(Color.Aurora.success)
        case "failed":
            AnyShapeStyle(Color.Aurora.error)
        default:
            AnyShapeStyle(Color.Aurora.textMuted)
        }
    }

    private var timeAgo: String {
        let now = Date()
        let diff = now.timeIntervalSince(session.createdAt)

        if diff < 60 { return L10n.Time.justNow }
        if diff < 3600 { return String(format: L10n.Time.minutesAgo, Int(diff / 60)) }
        if diff < 86400 { return String(format: L10n.Time.hoursAgo, Int(diff / 3600)) }
        return String(format: L10n.Time.daysAgo, Int(diff / 86400))
    }
}
