//
//  CommandBarView+FileCompletion.swift
//  Motive
//
//  Created by geezerrrr on 2026/1/19.
//

import Foundation

extension CommandBarView {
    /// Check if input contains @ trigger for file completion
    func checkForAtCompletion(_ text: String) {
        guard let token = currentAtToken(in: text) else {
            hideFileCompletion()
            return
        }

        let query = token.query
        let newRange = token.range

        // Skip if range and query haven't changed (avoid re-loading after manual selection)
        if showFileCompletion, let oldRange = atQueryRange, oldRange == newRange {
            Log.config("🔍 checkForAtCompletion: skipping (range unchanged)")
            return
        }

        atQueryRange = newRange

        // Load file completions
        let baseDir = fileCompletion.getBaseDirectory(for: configManager)
        Log.config("🔍 checkForAtCompletion: loading query '\(query)'")
        fileCompletion.loadItems(query: query, baseDir: baseDir)

        // Only show file completion if there are matching results
        // (loadItems is synchronous, so items are available immediately)
        guard !fileCompletion.items.isEmpty else {
            Log.config("🔍 checkForAtCompletion: no results, hiding")
            hideFileCompletion()
            return
        }

        showFileCompletion = true
        selectedFileIndex = 0
        // Window height is auto-synced via onChange(of: currentHeight) — no manual call needed.
    }

    /// Find the current @ token (from @ to next whitespace)
    func currentAtToken(in text: String) -> (query: String, range: Range<String.Index>)? {
        guard let atIndex = text.lastIndex(of: "@") else { return nil }

        // Require @ to be at start or preceded by whitespace
        if atIndex > text.startIndex {
            let beforeAt = text[text.index(before: atIndex)]
            if !beforeAt.isWhitespace {
                return nil
            }
        }

        let afterAt = text[atIndex...]
        if let spaceIndex = afterAt.dropFirst().firstIndex(where: { $0.isWhitespace }) {
            // Found space after @ - this means the @ token is complete
            // Return nil to exit completion mode (user typed "@path " with space)
            return nil
        } else {
            let range = atIndex ..< text.endIndex
            let query = String(text[range])
            return (query, range)
        }
    }

    /// Hide file completion popup
    func hideFileCompletion() {
        showFileCompletion = false
        atQueryRange = nil
        fileCompletion.clear()
        // Window height is auto-synced via onChange(of: currentHeight) — no manual call needed.
    }

    /// Select a file completion item
    func selectFileCompletion(_ item: FileCompletionItem) {
        guard let range = atQueryRange else { return }

        Log.config("📂 Select: '\(item.name)' isDir:\(item.isDirectory) path:'\(item.path)'")

        // Build the replacement text
        let replacement = if item.isDirectory {
            "@\(item.path)/"
        } else {
            "@\(item.path) " // Add space after file selection
        }

        Log.config("📂 Replacement: '\(replacement)'")

        // Calculate the new @ range after replacement
        let startIndex = range.lowerBound
        inputText.replaceSubrange(range, with: replacement)

        Log.config("📂 New inputText: '\(inputText)'")

        // Reset selection index
        selectedFileIndex = 0

        // If it's a directory, reload completions for the new path
        if item.isDirectory {
            // Update atQueryRange to point to the new @ token
            if let newEndIndex = inputText.index(startIndex, offsetBy: replacement.count, limitedBy: inputText.endIndex) {
                atQueryRange = startIndex ..< newEndIndex

                // Directly load items for the new directory
                let baseDir = fileCompletion.getBaseDirectory(for: configManager)
                Log.config("📂 Reloading with query: '\(replacement)', baseDir: \(baseDir.path)")
                fileCompletion.loadItems(query: replacement, baseDir: baseDir)

                // Only keep completion visible if there are items to show.
                // Empty subdirectories must not leave a large empty box.
                if fileCompletion.items.isEmpty {
                    Log.config("📂 Subdirectory is empty, hiding file completion")
                    hideFileCompletion()
                } else {
                    showFileCompletion = true
                    // Window height auto-syncs via onChange(of: currentHeight)
                }
            } else {
                hideFileCompletion()
            }
        } else {
            // File selected - hide completion (space already added)
            hideFileCompletion()
        }
    }
}
