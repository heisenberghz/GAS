//
//  SystemErrorBubble.swift
//  Motive
//
//  Aurora Design System - System/completion/error message bubble component
//

import SwiftUI

struct SystemErrorBubble: View {
    let message: ConversationMessage
    let isDark: Bool
    @Binding var isDetailExpanded: Bool

    var body: some View {
        Group {
            if message.status == .failed {
                errorBubble
            } else {
                completionBubble
            }
        }
    }

    /// Compact completion / interruption indicator
    private var completionBubble: some View {
        HStack(spacing: AuroraSpacing.space2) {
            Image(systemName: completionIcon)
                .font(.system(size: 11))
                .foregroundColor(completionIconColor)

            Text(message.content)
                .font(.Aurora.bodySmall)
                .foregroundColor(Color.Aurora.textMuted)
        }
        .padding(.horizontal, AuroraSpacing.space3)
        .padding(.vertical, AuroraSpacing.space2)
    }

    /// Error bubble — shows a concise title with expandable details
    @ViewBuilder
    private var errorBubble: some View {
        let (title, detail) = Self.parseErrorMessage(message.content)
        let fullDetail = (detail ?? message.content).trimmingCharacters(in: .whitespacesAndNewlines)

        VStack(alignment: .leading, spacing: 0) {
            // Header row: icon + title + Show button
            HStack(spacing: AuroraSpacing.space2) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(Color.Aurora.error)

                Text(title)
                    .font(.Aurora.bodySmall.weight(.medium))
                    .foregroundColor(Color.Aurora.error)
                    .lineLimit(1)

                Spacer()

                if !fullDetail.isEmpty {
                    Button {
                        withAnimation(.auroraFast) { isDetailExpanded.toggle() }
                    } label: {
                        Text(isDetailExpanded ? L10n.hide : L10n.show)
                            .font(.Aurora.micro.weight(.semibold))
                            .foregroundColor(Color.Aurora.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, AuroraSpacing.space3)
            .padding(.vertical, AuroraSpacing.space2)

            // Expandable detail
            if isDetailExpanded, !fullDetail.isEmpty {
                Divider()
                    .background(Color.Aurora.error.opacity(0.15))

                Text(fullDetail)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundColor(Color.Aurora.textSecondary)
                    .textSelection(.enabled)
                    .padding(AuroraSpacing.space2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.sm, style: .continuous)
                .fill(Color.Aurora.error.opacity(isDark ? 0.08 : 0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: AuroraRadius.sm, style: .continuous)
                        .strokeBorder(Color.Aurora.error.opacity(0.15), lineWidth: 0.5)
                )
        )
    }

    /// Parse a raw error string into a concise title and optional detail body.
    /// Handles formats like "APIError: Bad Request: {...json...} (HTTP 400)"
    static func parseErrorMessage(_ raw: String) -> (title: String, detail: String?) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try to extract a human-readable message from JSON body
        if let jsonStart = trimmed.range(of: "{"),
           let data = String(trimmed[jsonStart.lowerBound...]).data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? [String: Any],
           let message = error["message"] as? String
        {
            let shortMessage = message.components(separatedBy: "..").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? message
            return (shortMessage, trimmed)
        }

        // Try to extract "Name: short description" before any JSON
        if let jsonStart = trimmed.range(of: "{") {
            let prefix = String(trimmed[trimmed.startIndex ..< jsonStart.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !prefix.isEmpty {
                return (prefix, trimmed)
            }
        }

        // Short enough to show inline — no expansion needed
        if trimmed.count <= 100 {
            return (trimmed, nil)
        }

        // Truncate for title, full text as detail
        let titleEnd = trimmed.index(trimmed.startIndex, offsetBy: min(80, trimmed.count))
        return (String(trimmed[trimmed.startIndex ..< titleEnd]) + "…", trimmed)
    }

    private var completionIcon: String {
        let lower = message.content.lowercased()
        if lower.contains("interrupt") || lower.contains("中断") || lower.contains("停止") {
            return "stop.circle.fill"
        }
        return "checkmark.circle.fill"
    }

    private var completionIconColor: Color {
        let lower = message.content.lowercased()
        if lower.contains("interrupt") || lower.contains("中断") || lower.contains("停止") {
            return Color.Aurora.textMuted
        }
        return Color.Aurora.success
    }
}
