//
//  TodoBubble.swift
//  Motive
//
//  Aurora Design System - Todo/task list message bubble component
//

import SwiftUI

struct TodoBubble: View {
    let message: ConversationMessage
    let isDark: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AuroraSpacing.space2) {
            // Header
            HStack(spacing: AuroraSpacing.space2) {
                Image(systemName: "checklist")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.Aurora.primary)

                Text(L10n.Drawer.tasks)
                    .font(.Aurora.caption.weight(.semibold))
                    .foregroundColor(Color.Aurora.textSecondary)

                Spacer()

                // Progress summary
                if let items = message.todoItems {
                    let completed = items.count(where: { $0.status == .completed })
                    Text("\(completed)/\(items.count)")
                        .font(.Aurora.micro.weight(.medium))
                        .foregroundColor(Color.Aurora.textMuted)
                }
            }

            // Todo items list
            if let items = message.todoItems {
                // Progress bar
                todoProgressBar(items: items)

                VStack(alignment: .leading, spacing: AuroraSpacing.space1) {
                    ForEach(items) { item in
                        todoItemRow(item)
                    }
                }
            }
        }
        .padding(AuroraSpacing.space3)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                .fill(Color.Aurora.glassOverlay.opacity(isDark ? 0.04 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                .strokeBorder(Color.Aurora.primary.opacity(0.2), lineWidth: 0.5)
        )
    }

    /// Progress bar showing overall todo completion
    private func todoProgressBar(items: [TodoItem]) -> some View {
        let completed = Double(items.count(where: { $0.status == .completed }))
        let total = Double(items.count)
        let progress = total > 0 ? completed / total : 0

        return GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.Aurora.glassOverlay.opacity(isDark ? 0.06 : 0.08))
                    .frame(height: 3)

                RoundedRectangle(cornerRadius: 2)
                    .fill(progress >= 1.0 ? Color.Aurora.success : Color.Aurora.primary)
                    .frame(width: geometry.size.width * progress, height: 3)
                    .animation(.auroraSpring, value: progress)
            }
        }
        .frame(height: 3)
    }

    /// Single todo item row with status icon
    private func todoItemRow(_ item: TodoItem) -> some View {
        HStack(spacing: AuroraSpacing.space2) {
            todoStatusIcon(item.status)

            Text(item.content)
                .font(.Aurora.caption)
                .foregroundColor(todoTextColor(item.status))
                .strikethrough(
                    item.status == .completed || item.status == .cancelled,
                    color: Color.Aurora.textMuted.opacity(0.5)
                )
                .lineLimit(2)
        }
        .padding(.vertical, 1)
    }

    /// Icon for todo item status
    @ViewBuilder
    private func todoStatusIcon(_ status: TodoItem.Status) -> some View {
        switch status {
        case .pending:
            Image(systemName: "circle")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Color.Aurora.textMuted)
        case .inProgress:
            Image(systemName: "arrow.trianglehead.clockwise.rotate.90")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Color.Aurora.primary)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Color.Aurora.success)
        case .cancelled:
            Image(systemName: "xmark.circle")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Color.Aurora.textMuted)
        }
    }

    /// Text color based on todo status
    private func todoTextColor(_ status: TodoItem.Status) -> Color {
        switch status {
        case .pending: Color.Aurora.textSecondary
        case .inProgress: Color.Aurora.textPrimary
        case .completed: Color.Aurora.textMuted
        case .cancelled: Color.Aurora.textMuted
        }
    }
}
