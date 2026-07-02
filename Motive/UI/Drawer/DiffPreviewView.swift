//
//  DiffPreviewView.swift
//  Motive
//
//  Aurora Design System - Inline diff preview component
//

import SwiftUI

struct DiffPreviewView: View {
    let diff: String
    let isDark: Bool
    @Binding var isDetailExpanded: Bool

    var body: some View {
        let lines = diff.split(separator: "\n", omittingEmptySubsequences: false)
        // Show at most 12 lines inline; truncate longer diffs
        let maxPreviewLines = 12
        let displayLines = isDetailExpanded ? Array(lines) : Array(lines.prefix(maxPreviewLines))
        let isTruncated = lines.count > maxPreviewLines

        VStack(alignment: .leading, spacing: 0) {
            diffTitle

            ForEach(Array(displayLines.enumerated()), id: \.offset) { _, line in
                let lineStr = String(line)
                Text(lineStr)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundColor(Self.diffLineForeground(lineStr))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 1)
                    .padding(.horizontal, 6)
                    .background(Self.diffLineBackground(lineStr, isDark: isDark))
            }
            if isTruncated {
                Button(action: { withAnimation(.auroraFast) { isDetailExpanded.toggle() } }) {
                    Text(isDetailExpanded ? L10n.showLess : String(format: L10n.showMoreLines, lines.count - maxPreviewLines))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(Color.Aurora.textMuted)
                        .padding(.top, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(AuroraSpacing.space2)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.xs, style: .continuous)
                .fill(Color.Aurora.glassOverlay.opacity(isDark ? 0.06 : 0.05))
        )
        .padding(.top, AuroraSpacing.space1)
    }

    private var diffTitle: some View {
        let title = Self.extractDiffTitle(diff)
        return HStack(spacing: 6) {
            Image(systemName: "doc.text")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Color.Aurora.textMuted)
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(Color.Aurora.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color.Aurora.glassOverlay.opacity(isDark ? 0.08 : 0.10))
        .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.xs, style: .continuous))
        .padding(.bottom, 4)
    }

    static func extractDiffTitle(_ diff: String) -> String {
        let lines = diff.split(separator: "\n", omittingEmptySubsequences: false)
        for line in lines {
            if line.hasPrefix("diff --git ") {
                let parts = line.split(separator: " ")
                if parts.count >= 4 {
                    let raw = parts[3]
                    return String(raw.replacingOccurrences(of: "b/", with: ""))
                }
            }
            if line.hasPrefix("+++ ") {
                let raw = line.dropFirst(4)
                return String(raw.replacingOccurrences(of: "b/", with: ""))
            }
        }
        return L10n.Drawer.changes
    }

    /// Foreground color for a single diff line based on +/- prefix
    static func diffLineForeground(_ line: String) -> Color {
        if line.hasPrefix("+++") || line.hasPrefix("---") {
            return Color.Aurora.textMuted
        } else if line.hasPrefix("+") {
            return Color.Aurora.textPrimary
        } else if line.hasPrefix("-") {
            return Color.Aurora.textPrimary
        } else if line.hasPrefix("@@") {
            return Color.Aurora.primary.opacity(0.7)
        }
        return Color.Aurora.textSecondary
    }

    /// Background color for a single diff line based on +/- prefix
    static func diffLineBackground(_ line: String, isDark: Bool) -> Color {
        if line.hasPrefix("+++ ") || line.hasPrefix("--- ") || line.hasPrefix("diff --git") {
            return Color.Aurora.glassOverlay.opacity(isDark ? 0.08 : 0.10)
        }
        if line.hasPrefix("+") {
            return Color.Aurora.success.opacity(isDark ? 0.18 : 0.12)
        }
        if line.hasPrefix("-") {
            return Color.Aurora.error.opacity(isDark ? 0.18 : 0.12)
        }
        return Color.clear
    }
}
