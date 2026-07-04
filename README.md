<p align="center">
  <img src="assets/icon.png" width="128" height="128" alt="Motive">
</p>

<h1 align="center">Motive</h1>

<h3 align="center"><strong>Say it. Walk away.</strong></h3>
<p align="center">A background desktop assistant that runs AI agents in the background — and finds you when they need approval.</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2015+%20%7C%20Windows%2010%2F11-blue?style=flat-square" alt="Platform">
  <img src="https://img.shields.io/badge/language-Swift%206%20%7C%20C%23%20%2F%20.NET%208-orange?style=flat-square" alt="Languages">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" alt="License"></a>
</p>

<p align="center">
  <a href="https://motivework.app/docs">Documentation</a> · <a href="https://github.com/geezerrrr/motive/releases/latest">Download</a> · <a href="https://github.com/geezerrrr/motive/issues">Feedback</a>
</p>

---

## Why Motive?

AI coding agents are powerful, but they all assume you're watching. Switch away from the terminal or editor, and you'll come back to find the agent stuck on a permission approval that's been sitting there for minutes.

Motive puts the agent in your menu bar (macOS) or system tray (Windows). No window to babysit. When it needs a yes/no or has a question, a native popup drops down — no matter what app you're in. You respond, it continues, you go back to what you were doing.

Under the hood it uses [OpenCode](https://github.com/anomalyco/opencode) as the agent engine. Motive doesn't try to be a better agent — it just makes sure the agent can reach you.

| Feature | Desktop Apps | CLI Tools | Motive |
|---|---|---|---|
| Where it lives | App window | Terminal | Menu bar / System tray |
| When it needs you | Buried in UI | Waits in terminal | Native popup |
| Switch away? | Miss responses | Miss prompts | Finds you |

---

## Multi-Platform Implementations

Motive is built as a native experience optimized for each desktop platform.

### 🍏 macOS Native App (Swift)
*   **Built with:** Swift 6.0, SwiftUI, and AppKit.
*   **Menu Bar:** Runs in the macOS Menu Bar.
*   **Security:** Stores your API keys securely inside Apple Keychain.
*   **Hotkey:** `⌥Space` global shortcut hook.

### Windows Port (C# / WPF)
*   **Built with:** C#, WPF (.NET 8), and Lepo's `WPF-UI` library.
*   **System Tray:** Runs in the Windows System Tray with dynamic tray icon states (Thinking, Executing, Idle, Error).
*   **Security:** Stores your API credentials securely via Windows DPAPI (Data Protection API) encryption.
*   **Database:** Local persistence of session histories and transcripts using SQLite and Entity Framework Core.
*   **Hotkey:** `Ctrl + Shift + Space` global hotkey.
*   **Visual Layouts:** Features a sliding sidebar **Drawer** docked to the right edge of your screen and a tabbed settings window with dynamic hotkey re-binding.

---

## Features

### Core
- **Background execution** — The agent runs in the background. No window to watch, no terminal to babysit.
- **Native popups** — Permission requests and questions appear as popups from the tray or menu bar.
- **Ambient status** — Menu bar/tray icon shows execution states at a glance without demanding attention.
- **Concurrent sessions** — Run multiple tasks in parallel, each working independently.

### Control & Privacy
- **Trust levels** — Three modes to control what the agent can do on its own: Careful, Balanced, and Yolo.
- **Approval system** — Fine-grained file permission policies with per-action Always Allow / Ask / Deny.
- **Local-first** — All data stays on your machine. Only API requests leave your device.

---

## Build from Source

### macOS (Xcode)
```bash
git clone https://github.com/geezerrrr/motive.git
cd motive
open Motive.xcodeproj
```
*The OpenCode binary is bundled automatically during release builds. For development, place it at `Motive/Resources/opencode`.*

### Windows (Visual Studio / .NET CLI)
```bash
git clone https://github.com/geezerrrr/motive.git
cd motive/MotiveWindows
dotnet build
```
Ensure you have the OpenCode CLI engine installed globally via npm:
```bash
npm install -g opencode-ai
```
*(The Windows app automatically resolves your global installation paths upon startup).*

---

## Keyboard Shortcuts

### macOS
| Shortcut | Action |
|----------|--------|
| `⌥Space` | Open command bar |
| `Enter` | Submit task |
| `Esc` | Dismiss command bar |
| `⌘,` | Open settings |

### Windows
| Shortcut | Action |
|----------|--------|
| `Ctrl+Shift+Space` | Open command bar |
| `Enter` | Submit task |
| `Esc` | Dismiss command bar |

---

## Requirements

### macOS
- macOS 15.0 (Sequoia) or later.
- API key for Claude, OpenAI, Gemini, or local Ollama.

### Windows
- Windows 10 / 11.
- .NET 8.0 Runtime.
- API key for Claude, OpenAI, Gemini, or local Ollama.

---

## Acknowledgments

Powered by [OpenCode](https://github.com/anomalyco/opencode) — the open-source AI coding agent.

---

<p align="center">
  <sub>Let AI wait for you, not the other way around.</sub>
</p>
