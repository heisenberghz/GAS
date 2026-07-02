//
//  OutputFormatter.swift
//  Motive
//
//  Aurora Design System - Tool output formatting utilities
//

import MarkdownUI
import SwiftUI

enum OutputFormatter {
    /// Detect content type and render with syntax highlighting via Markdown code blocks
    @ViewBuilder
    static func formattedOutput(_ output: String, toolName: String?, isDark: Bool) -> some View {
        let lang = detectOutputLanguage(output, toolName: toolName)
        if let lang {
            // Pretty-print JSON for readability; other languages use raw output
            let displayText = (lang == "json") ? prettyPrintJSON(output) : output
            let markdown = "```\(lang)\n\(displayText)\n```"
            Markdown(markdown)
                .markdownTextStyle {
                    FontSize(11)
                    ForegroundColor(Color.Aurora.textPrimary)
                }
                .markdownBlockStyle(\.codeBlock) { configuration in
                    configuration.label
                        .padding(6)
                        .background(Color.Aurora.glassOverlay.opacity(isDark ? 0.05 : 0.04))
                        .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.xs))
                }
        } else {
            // Plain text fallback
            Text(output)
                .font(.Aurora.monoSmall)
                .foregroundColor(Color.Aurora.textPrimary)
        }
    }

    /// Pretty-print a JSON string with indentation. Returns original on failure.
    static func prettyPrintJSON(_ raw: String) -> String {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let result = String(data: pretty, encoding: .utf8)
        else {
            return raw
        }
        return result
    }

    /// Detect the language/format of tool output for syntax highlighting
    static func detectOutputLanguage(_ output: String, toolName: String?) -> String? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)

        // JSON: starts with { or [
        if (trimmed.hasPrefix("{") && trimmed.hasSuffix("}"))
            || (trimmed.hasPrefix("[") && trimmed.hasSuffix("]"))
        {
            // Validate it's actual JSON (not just text in braces)
            if trimmed.data(using: .utf8).flatMap({ try? JSONSerialization.jsonObject(with: $0) }) != nil {
                return "json"
            }
        }

        // Diff/patch: contains diff markers
        if trimmed.hasPrefix("---") || trimmed.hasPrefix("diff ") || trimmed.hasPrefix("@@") {
            return "diff"
        }
        // Also detect inline diff markers in multiline output
        let lines = trimmed.split(separator: "\n", maxSplits: 10)
        let diffMarkers = lines.filter { $0.hasPrefix("+") || $0.hasPrefix("-") || $0.hasPrefix("@@") }
        if diffMarkers.count > 2 && Double(diffMarkers.count) / Double(lines.count) > 0.3 {
            return "diff"
        }

        // Shell output: if the tool is Shell/Bash, hint as shell
        if let toolName = toolName?.lowercased(),
           toolName == "shell" || toolName == "bash" || toolName == "command"
        {
            return "bash"
        }

        // XML/HTML: starts with < and contains >
        if trimmed.hasPrefix("<"), trimmed.contains(">") {
            return "html"
        }

        return nil // Plain text — no syntax highlighting
    }

    /// Tool icon for legacy display
    static func toolIcon(for toolName: String?) -> String {
        guard let toolName = toolName?.lowercased() else { return "terminal" }

        switch toolName {
        case "read", "read_file": return "doc.text"
        case "write", "write_file": return "square.and.pencil"
        case "edit", "edit_file": return "pencil"
        case "bash", "shell", "command": return "terminal"
        case "glob", "find", "search": return "magnifyingglass"
        case "grep": return "text.magnifyingglass"
        case "task", "agent": return "brain"
        default: return "wrench"
        }
    }
}
