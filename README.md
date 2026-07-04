<p align="center">
  <img src="assets/icon.png" width="128" height="128" alt="GAS">
</p>

<h1 align="center">GAS</h1>

<h3 align="center"><strong>Say it. Walk away.</strong></h3>
<p align="center">A background desktop assistant that runs AI agents in the background â€” and finds you when they need approval.</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-Windows%2010%2F11-blue?style=flat-square" alt="Platform">
  <img src="https://img.shields.io/badge/language-C%23%20%2F%20.NET%208-orange?style=flat-square" alt="Languages">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" alt="License"></a>
</p>

<p align="center">
  <a href="https://GASwork.app/docs">Documentation</a> Â· <a href="https://github.com/geezerrrr/GAS/releases/latest">Download</a> Â· <a href="https://github.com/geezerrrr/GAS/issues">Feedback</a>
</p>

---

## Why GAS?

AI coding agents are powerful, but they all assume you're watching. Switch away from the terminal or editor, and you'll come back to find the agent stuck on a permission approval that's been sitting there for minutes.

GAS puts the agent in your Windows System Tray (next to your clock). No window to babysit. When it needs a yes/no or has a question, a native popup drops down â€” no matter what app you're in. You respond, it continues, you go back to what you were doing.

Under the hood it uses [OpenCode](https://github.com/anomalyco/opencode) as the agent engine. GAS doesn't try to be a better agent â€” it just makes sure the agent can reach you.

| Feature | Desktop Apps | CLI Tools | GAS |
|---|---|---|---|
| Where it lives | App window | Terminal | System tray |
| When it needs you | Buried in UI | Waits in terminal | System notification |
| Switch away? | Miss responses | Miss prompts | Finds you |

---

## Architecture & Tech Stack

GAS is built as a lightweight, native Windows background application:

*   **UI Framework:** WPF (.NET 8.0) styled with Lepo's Fluent `WPF-UI` library.
*   **System Tray:** Context menu and dynamic icon status representation:
    *   ðŸŸ£ **Purple:** Idle
    *   ðŸŸ¡ **Orange:** Thinking
    *   ðŸŸ¢ **Green:** Executing task
    *   `ðŸ”´` **Red:** Error state
*   **Database:** Session logs and transcripts persistent history via SQLite and Entity Framework Core.
*   **API Security:** Local credentials storage utilizing Windows Data Protection API (DPAPI) encryption.
*   **Global Hotkey:** Low-level Win32 keyboard hook (`Ctrl + Shift + Space` default).
*   **Visual Layouts:** Features a sliding sidebar **Drawer** docked to the right edge of your screen and a tabbed settings window with dynamic hotkey re-binding.

---

## Features

### Core
- **Background execution** â€” The agent runs in the background. No window to watch, no terminal to babysit.
- **Native popups** â€” Permission requests and questions appear as popups from the tray.
- **Ambient status** â€” Tray icon shows execution states at a glance without demanding attention.
- **Concurrent sessions** â€” Run multiple tasks in parallel, each working independently.

### Control & Privacy
- **Trust levels** â€” Three modes to control what the agent can do on its own: Careful, Balanced, and Yolo.
- **Local-first** â€” All data stays on your machine. Only API requests leave your device.

---

## Build from Source

Ensure you have the .NET 8 SDK and the OpenCode CLI engine installed globally via npm:
```bash
npm install -g opencode-ai
```

Clone the repository and build the C# solution:
```bash
git clone https://github.com/geezerrrr/GAS.git
cd GAS
dotnet build GAS.sln
```

*(The application automatically resolves your global npm installation paths for the OpenCode background server process on startup).*

---

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Ctrl+Shift+Space` | Open command bar |
| `Enter` | Submit task |
| `Esc` | Dismiss command bar |

---

## Requirements

- Windows 10 / 11.
- .NET 8.0 Runtime.
- API key for Claude, OpenAI, Gemini, or local Ollama.

---

## Acknowledgments

Powered by [OpenCode](https://github.com/anomalyco/opencode) â€” the open-source AI coding agent.

---

<p align="center">
  <sub>Let AI wait for you, not the other way around.</sub>
</p>

