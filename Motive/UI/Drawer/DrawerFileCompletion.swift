//
//  DrawerFileCompletion.swift
//  Motive
//
//  Aurora Design System - File completion overlay and @ token logic
//

import SwiftUI

struct DrawerFileCompletion: View {
    @EnvironmentObject private var configManager: ConfigManager
    @StateObject private var fileCompletion: FileCompletionManager
    @Binding var inputText: String
    @Binding var showFileCompletion: Bool
    @Binding var selectedFileIndex: Int
    @Binding var atQueryRange: Range<String.Index>?

    init(
        fileCompletion: FileCompletionManager,
        inputText: Binding<String>,
        showFileCompletion: Binding<Bool>,
        selectedFileIndex: Binding<Int>,
        atQueryRange: Binding<Range<String.Index>?>
    ) {
        _fileCompletion = StateObject(wrappedValue: fileCompletion)
        _inputText = inputText
        _showFileCompletion = showFileCompletion
        _selectedFileIndex = selectedFileIndex
        _atQueryRange = atQueryRange
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Dismiss area
            Color.black.opacity(0.01)
                .onTapGesture {
                    hideFileCompletion()
                }

            // File completion popup
            VStack(spacing: 0) {
                FileCompletionView(
                    items: fileCompletion.items,
                    selectedIndex: selectedFileIndex,
                    currentPath: fileCompletion.currentPath,
                    onSelect: selectFileCompletion,
                    maxHeight: 240
                )
                .id("fileCompletion-\(fileCompletion.currentPath)-\(fileCompletion.items.count)")
            }
            .frame(width: 360)
            .background(
                RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                    .fill(Color.Aurora.surface)
                    .shadow(color: Color.black.opacity(0.15), radius: 16, y: -6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                    .strokeBorder(Color.Aurora.border.opacity(0.4), lineWidth: 0.5)
            )
            .padding(.bottom, 80) // Position above input area
        }
        .transition(.opacity)
    }

    // MARK: - @ File Completion Logic

    func checkForAtCompletion(_ text: String) {
        guard let token = currentAtToken(in: text) else {
            hideFileCompletion()
            return
        }

        let query = token.query
        let newRange = token.range

        // Skip if range and query haven't changed (avoid re-loading after manual selection)
        if showFileCompletion, let oldRange = atQueryRange, oldRange == newRange {
            return
        }

        atQueryRange = newRange

        let baseDir = fileCompletion.getBaseDirectory(for: configManager)
        fileCompletion.loadItems(query: query, baseDir: baseDir)

        showFileCompletion = true
        selectedFileIndex = 0
    }

    /// Find the current @ token (from @ to next whitespace)
    static func currentAtToken(in text: String) -> (query: String, range: Range<String.Index>)? {
        guard let atIndex = text.lastIndex(of: "@") else { return nil }

        // Require @ to be at start or preceded by whitespace
        if atIndex > text.startIndex {
            let beforeAt = text[text.index(before: atIndex)]
            if !beforeAt.isWhitespace {
                return nil
            }
        }

        let afterAt = text[atIndex...]
        if afterAt.dropFirst().firstIndex(where: { $0.isWhitespace }) != nil {
            // Found space after @ - this means the @ token is complete
            // Return nil to exit completion mode (user typed "@path " with space)
            return nil
        } else {
            let range = atIndex ..< text.endIndex
            let query = String(text[range])
            return (query, range)
        }
    }

    func hideFileCompletion() {
        showFileCompletion = false
        atQueryRange = nil
        fileCompletion.clear()
    }

    func selectFileCompletion(_ item: FileCompletionItem) {
        guard let range = atQueryRange else { return }

        let replacement = if item.isDirectory {
            "@\(item.path)/"
        } else {
            "@\(item.path) "
        }

        // Calculate the new @ range after replacement
        let startIndex = range.lowerBound
        inputText.replaceSubrange(range, with: replacement)

        // Reset selection index
        selectedFileIndex = 0

        // If it's a directory, reload completions for the new path
        if item.isDirectory {
            // Update atQueryRange to point to the new @ token
            if let newEndIndex = inputText.index(startIndex, offsetBy: replacement.count, limitedBy: inputText.endIndex) {
                atQueryRange = startIndex ..< newEndIndex

                // Directly load items for the new directory
                let baseDir = fileCompletion.getBaseDirectory(for: configManager)
                fileCompletion.loadItems(query: replacement, baseDir: baseDir)

                // Keep completion visible
                showFileCompletion = true
            } else {
                hideFileCompletion()
            }
        } else {
            // File selected - hide completion (space already added)
            hideFileCompletion()
        }
    }

    // MARK: - Private helpers

    private func currentAtToken(in text: String) -> (query: String, range: Range<String.Index>)? {
        Self.currentAtToken(in: text)
    }
}
