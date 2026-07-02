//
//  HotkeyParser.swift
//  Motive
//
//  Shared hotkey parsing utilities for AppDelegate and StatusBarController.
//

import AppKit

/// Shared hotkey parsing utilities.
///
/// Parses hotkey strings like `"⌥Space"` or `"⌘⇧K"` into modifier flags
/// and key codes / key equivalents.
enum HotkeyParser {

    // MARK: - Modifier Mapping

    /// Modifier symbol/name → flag, ordered longest-name-first so prefix
    /// matching doesn't collide (e.g. "Control" before "Ctrl").
    private static let modifierTable: [(symbols: [String], flag: NSEvent.ModifierFlags)] = [
        (["⌘", "Cmd"], .command),
        (["⌥", "Option", "Alt"], .option),
        (["⇧", "Shift"], .shift),
        (["⌃", "Control", "Ctrl"], .control),
    ]

    // MARK: - Key Code Mapping

    /// Human-readable key name → macOS virtual key code.
    static let keyCodeMap: [String: UInt16] = [
        // Special keys
        "space": 49,
        "return": 36, "enter": 36, "↵": 36,
        "tab": 48,
        "delete": 51, "backspace": 51,
        "escape": 53, "esc": 53,
        // Arrows
        "←": 123, "left": 123,
        "→": 124, "right": 124,
        "↓": 125, "down": 125,
        "↑": 126, "up": 126,
        // Function keys
        "f1": 122, "f2": 120, "f3": 99, "f4": 118,
        "f5": 96, "f6": 97, "f7": 98, "f8": 100,
        "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        // Letters
        "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3,
        "g": 5, "h": 4, "i": 34, "j": 38, "k": 40, "l": 37,
        "m": 46, "n": 45, "o": 31, "p": 35, "q": 12, "r": 15,
        "s": 1, "t": 17, "u": 32, "v": 9, "w": 13, "x": 7,
        "y": 16, "z": 6,
        // Numbers
        "0": 29, "1": 18, "2": 19, "3": 20, "4": 21,
        "5": 23, "6": 22, "7": 26, "8": 28, "9": 25,
    ]

    /// Key name → NSMenuItem key equivalent string.
    private static let keyEquivalentMap: [String: String] = [
        "space": " ", " ": " ",
        "return": "\r", "enter": "\r",
        "tab": "\t",
        "escape": "\u{1B}", "esc": "\u{1B}",
    ]

    // MARK: - Public API

    /// Parse a hotkey string into modifier flags and a virtual key code.
    ///
    /// Used by `AppDelegate` to register global event monitors.
    static func parseToKeyCode(_ hotkey: String) -> (modifiers: NSEvent.ModifierFlags, keyCode: UInt16) {
        let (modifiers, keyName) = stripModifiers(from: hotkey)
        let keyCode = keyCodeMap[keyName.lowercased()] ?? 49 // default: Space
        return (modifiers, keyCode)
    }

    /// Parse a hotkey string into an `NSMenuItem`-compatible key equivalent
    /// and modifier mask.
    ///
    /// Used by `StatusBarController` to display the shortcut in menus.
    static func parseToMenuShortcut(_ hotkey: String) -> (keyEquivalent: String, modifiers: NSEvent.ModifierFlags) {
        let (modifiers, keyName) = stripModifiers(from: hotkey)
        let key = keyName.lowercased()
        let equivalent = keyEquivalentMap[key] ?? key
        return (equivalent, modifiers)
    }

    // MARK: - Internal

    /// Strip modifier symbols/names from the front of a hotkey string,
    /// returning the accumulated flags and the remaining key name.
    private static func stripModifiers(from hotkey: String) -> (NSEvent.ModifierFlags, String) {
        var modifiers: NSEvent.ModifierFlags = []
        var remaining = hotkey

        // Loop until no more modifier prefixes are found.
        var madeProgress = true
        while madeProgress {
            madeProgress = false
            for entry in modifierTable {
                for symbol in entry.symbols {
                    if remaining.hasPrefix(symbol) {
                        modifiers.insert(entry.flag)
                        remaining = String(remaining.dropFirst(symbol.count))
                        madeProgress = true
                        break // restart the inner loop for this entry
                    }
                }
                // Also handle the symbol-based contains approach (e.g. "⌥Space" where ⌥ is anywhere)
                for symbol in entry.symbols where symbol.count == 1 {
                    if remaining.contains(symbol) {
                        modifiers.insert(entry.flag)
                        remaining = remaining.replacingOccurrences(of: symbol, with: "")
                        madeProgress = true
                    }
                }
            }
        }

        return (modifiers, remaining.trimmingCharacters(in: .whitespaces))
    }
}
