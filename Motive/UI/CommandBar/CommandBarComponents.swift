//
//  CommandBarComponents.swift
//  Motive
//
//  Created by geezerrrr on 2026/1/19.
//

import SwiftUI

struct CommandListItem: View {
    let command: CommandDefinition
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: AuroraSpacing.space3) {
                Image(systemName: command.icon)
                    .font(.Aurora.bodySmall.weight(.medium))
                    .foregroundColor(isSelected ? Color.Aurora.microAccent : Color.Aurora.textSecondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: AuroraSpacing.space2) {
                        Text("/\(command.name)")
                            .font(.Aurora.body.weight(.medium))
                            .foregroundColor(Color.Aurora.textPrimary)

                        if let shortcut = command.shortcut {
                            Text("/\(shortcut)")
                                .font(.Aurora.caption)
                                .foregroundColor(Color.Aurora.textMuted)
                        }
                    }

                    Text(command.description)
                        .font(.Aurora.caption)
                        .foregroundColor(Color.Aurora.textMuted)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "return")
                        .font(.Aurora.micro.weight(.medium))
                        .foregroundColor(Color.Aurora.textMuted)
                }
            }
            .padding(.horizontal, AuroraSpacing.space3)
            .padding(.vertical, AuroraSpacing.space2)
            .background(
                RoundedRectangle(cornerRadius: AuroraRadius.sm, style: .continuous)
                    .fill(
                        isSelected
                            ? Color.Aurora.microAccentSoft
                            : (isHovering ? Color.Aurora.surfaceElevated : Color.clear)
                    )
            )
            .overlay(alignment: .leading) {
                if isSelected {
                    RoundedRectangle(cornerRadius: AuroraRadius.xs, style: .continuous)
                        .fill(Color.Aurora.microAccent.opacity(0.9))
                        .frame(width: 2, height: 22)
                        .padding(.leading, 1)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel("/\(command.name)")
        .accessibilityHint(command.description)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

struct ProjectListItem: View {
    let name: String
    let path: String
    let icon: String
    let isSelected: Bool
    let isCurrent: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: AuroraSpacing.space3) {
                Image(systemName: icon)
                    .font(.Aurora.bodySmall.weight(.medium))
                    .foregroundColor(isSelected ? Color.Aurora.microAccent : Color.Aurora.textSecondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: AuroraSpacing.space2) {
                        Text(name)
                            .font(.Aurora.body.weight(.medium))
                            .foregroundColor(Color.Aurora.textPrimary)

                        if isCurrent {
                            Text("current")
                                .font(.Aurora.micro)
                                .foregroundColor(Color.Aurora.microAccent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(Color.Aurora.microAccentSoft)
                                )
                        }
                    }

                    if !path.isEmpty {
                        Text(path)
                            .font(.Aurora.caption)
                            .foregroundColor(Color.Aurora.textMuted)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "return")
                        .font(.Aurora.micro.weight(.medium))
                        .foregroundColor(Color.Aurora.textMuted)
                }
            }
            .padding(.horizontal, AuroraSpacing.space3)
            .padding(.vertical, AuroraSpacing.space2)
            .background(
                RoundedRectangle(cornerRadius: AuroraRadius.sm, style: .continuous)
                    .fill(
                        isSelected
                            ? Color.Aurora.microAccentSoft
                            : (isHovering ? Color.Aurora.surfaceElevated : Color.clear)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(name)
        .accessibilityHint(path.isEmpty ? "Select project" : path)
        .accessibilityValue(isCurrent ? "Current project" : (isSelected ? "Selected" : "Not selected"))
    }
}

struct ModeListItem: View {
    let name: String
    let icon: String
    let description: String
    let isSelected: Bool
    let isCurrent: Bool
    let action: () -> Void

    @State private var isHovering = false

    private var currentModeAccent: Color {
        name.lowercased() == "plan" ? Color.Aurora.planAccent : Color.Aurora.textSecondary
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: AuroraSpacing.space3) {
                Image(systemName: icon)
                    .font(.Aurora.bodySmall.weight(.medium))
                    .foregroundColor(isSelected ? Color.Aurora.microAccent : Color.Aurora.textSecondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: AuroraSpacing.space2) {
                        Text(name)
                            .font(.Aurora.body.weight(.medium))
                            .foregroundColor(Color.Aurora.textPrimary)

                        if isCurrent {
                            Text("current")
                                .font(.Aurora.micro)
                                .foregroundColor(currentModeAccent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(
                                            name.lowercased() == "plan"
                                                ? Color.Aurora.planAccent.opacity(0.16)
                                                : Color.Aurora.glassOverlay.opacity(0.06)
                                        )
                                )
                        }
                    }

                    Text(description)
                        .font(.Aurora.caption)
                        .foregroundColor(Color.Aurora.textMuted)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "return")
                        .font(.Aurora.micro.weight(.medium))
                        .foregroundColor(Color.Aurora.textMuted)
                }
            }
            .padding(.horizontal, AuroraSpacing.space3)
            .padding(.vertical, AuroraSpacing.space2)
            .background(
                RoundedRectangle(cornerRadius: AuroraRadius.sm, style: .continuous)
                    .fill(
                        isSelected
                            ? Color.Aurora.microAccentSoft
                            : (isHovering ? Color.Aurora.surfaceElevated : Color.clear)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(name)
        .accessibilityHint(description)
        .accessibilityValue(isCurrent ? "Current mode" : (isSelected ? "Selected" : "Not selected"))
    }
}

struct AuroraActionPill: View {
    let icon: String
    let label: String
    let style: Style
    let action: () -> Void

    @State private var isHovering = false
    @State private var isPressed = false

    enum Style {
        case primary, warning, error

        var gradientColors: [Color] {
            switch self {
            case .primary: [Color.Aurora.primary, Color.Aurora.primaryDark]
            case .warning: [Color.Aurora.warning, Color.Aurora.warning.opacity(0.9)]
            case .error: [Color.Aurora.error, Color.Aurora.error.opacity(0.9)]
            }
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: AuroraSpacing.space2) {
                Text(label)
                    .font(.Aurora.caption.weight(.semibold))
                    .foregroundColor(.white)

                Image(systemName: icon)
                    .font(.Aurora.micro.weight(.bold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, AuroraSpacing.space4)
            .frame(height: 36)
            .background(style.gradientColors.first ?? Color.Aurora.primary)
            .clipShape(Capsule())
            .shadow(color: Color.black.opacity(0.2), radius: isHovering ? 10 : 6, y: 3)
            .scaleEffect(isPressed ? 0.96 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .animation(.auroraSpringStiff, value: isHovering)
        .animation(.auroraSpringStiff, value: isPressed)
    }
}

struct AuroraShortcutBadge: View {
    let keys: [String]
    let label: String

    var body: some View {
        HStack(spacing: AuroraSpacing.space1) {
            ForEach(keys, id: \.self) { key in
                Group {
                    if key == "↵" {
                        Image(systemName: "return")
                            .font(.Aurora.micro.weight(.medium))
                            .foregroundColor(Color.Aurora.textSecondary)
                            .frame(width: 16, height: 16)
                    } else {
                        Text(key)
                            .font(.Aurora.micro.weight(.medium))
                            .foregroundColor(Color.Aurora.textSecondary)
                            .frame(minWidth: 16)
                    }
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: AuroraRadius.xs, style: .continuous)
                        .fill(Color.Aurora.surfaceElevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AuroraRadius.xs, style: .continuous)
                        .stroke(Color.Aurora.border.opacity(0.6), lineWidth: 1)
                )
            }

            Text(label)
                .font(.Aurora.micro.weight(.regular))
                .foregroundColor(Color.Aurora.textSecondary)
        }
    }
}

/// Raycast-style inline shortcut hint: "Label  key  |  Label  key"
/// Much cleaner than individual bordered badges for the footer.
struct InlineShortcutHint: View {
    let items: [(label: String, key: String)]
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool {
        colorScheme == .dark
    }

    var body: some View {
        HStack(spacing: AuroraSpacing.space3) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 {
                    Text("|")
                        .font(.Aurora.micro.weight(.regular))
                        .foregroundColor(Color.Aurora.textMuted.opacity(0.5))
                }
                HStack(spacing: AuroraSpacing.space1) {
                    Text(item.label)
                        .font(.Aurora.micro.weight(.regular))
                        .foregroundColor(Color.Aurora.textMuted)

                    Text(item.key)
                        .font(.Aurora.micro.weight(.medium))
                        .foregroundColor(Color.Aurora.textSecondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: AuroraRadius.xs, style: .continuous)
                                .fill(Color.Aurora.glassOverlay.opacity(isDark ? 0.06 : 0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: AuroraRadius.xs, style: .continuous)
                                .strokeBorder(Color.Aurora.glassOverlay.opacity(isDark ? 0.08 : 0.12), lineWidth: 0.5)
                        )
                }
            }
        }
    }
}

struct AuroraPulsingDot: View {
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.Aurora.primary.opacity(0.25))
                .frame(width: 12, height: 12)
                .scaleEffect(isPulsing ? 1.5 : 1)
                .opacity(isPulsing ? 0 : 0.6)

            Circle()
                .fill(Color.Aurora.primary)
                .frame(width: 6, height: 6)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) {
                isPulsing = true
            }
        }
    }
}

struct PulsingBorderModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.6 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}
