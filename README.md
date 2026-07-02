<p align="center">
  <img src="assets/icon.png" width="128" height="128" alt="Motive">
</p>

<h1 align="center">Motive</h1>

<h3 align="center"><strong>Say it. Walk away.</strong></h3>
<p align="center">A macOS menu bar app that runs AI agents in the background — and finds you when they need approval.</p>

<p align="center">
  <a href="https://github.com/geezerrrr/motive/releases/latest"><img src="https://img.shields.io/github/v/release/geezerrrr/motive?style=flat-square&color=blue" alt="Release"></a>
  <a href="https://github.com/geezerrrr/motive/stargazers"><img src="https://img.shields.io/github/stars/geezerrrr/motive?style=flat-square" alt="Stars"></a>
  <img src="https://img.shields.io/badge/platform-macOS%2015+-blue?style=flat-square" alt="Platform">
  <img src="https://img.shields.io/badge/swift-6.0-orange?style=flat-square" alt="Swift">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" alt="License"></a>
</p>

<p align="center">
  <a href="https://motivework.app/docs">Documentation</a> · <a href="https://github.com/geezerrrr/motive/releases/latest">Download</a> · <a href="https://github.com/geezerrrr/motive/issues">Feedback</a>
</p>

---

## Why Motive?

AI coding agents are powerful, but they all assume you're watching. Switch away from the terminal or editor, and you'll come back to find the agent stuck on a permission approval that's been sitting there for minutes.

Motive puts the agent in your menu bar. No window to babysit. When it needs a yes/no or has a question, a native popup drops down — no matter what app you're in. You respond, it continues, you go back to what you were doing.

Under the hood it uses [OpenCode](https://github.com/anomalyco/opencode) as the agent engine. Motive doesn't try to be a better agent — it just makes sure the agent can reach you.

| | Desktop Apps | CLI Tools | Motive |
|---|---|---|---|
| Where it lives | App window | Terminal | Menu bar |
| When it needs you | Buried in UI | Waits in terminal | Native popup |
| Switch away? | Miss responses | Miss prompts | Finds you |

## Demo

<p align="center">

https://github.com/user-attachments/assets/6209e3d9-60db-4166-a14a-ae90cdbc01d6

</p>

## Features

### Core

- **Background execution** — The agent runs in the background. No window to watch, no terminal to babysit.
- **Native popups** — Permission requests and questions appear as macOS-native popups from the menu bar.
- **Ambient status** — Menu bar icon shows progress at a glance without demanding attention.
- **Concurrent sessions** — Run multiple tasks in parallel, each working independently.

### Control & Privacy

- **Trust levels** — Three modes to control what the agent can do on its own:

  | Level | Behavior |
  |-------|----------|
  | Careful | Asks before every edit and shell command |
  | Balanced | Auto-approves safe actions, asks for unknown commands |
  | Yolo | Full autonomy for trusted environments |

- **Approval system** — Fine-grained file permission policies with per-action Always Allow / Ask / Deny.
- **Local-first** — All data stays on your machine. Only API requests leave your device.

### Extensibility

- **Multiple providers** — Claude, OpenAI, Gemini, Ollama, OpenRouter, Azure, Bedrock, and more. Bring your own key.
- **50+ built-in skills** — GitHub, Slack, Notion, Calendar, and others. Enable/disable in Settings.
- **Custom skills** — Create your own in `~/.motive/skills/`, no code changes required.
- **Browser automation** — Web scraping, form filling, and multi-step browser workflows.

### Built for Mac

- **Native macOS** — Swift 6, SwiftUI, AppKit. No Electron, no web views.
- **Keychain storage** — API keys stored securely in macOS Keychain.
- **Global hotkey** — `⌥Space` from anywhere, like Spotlight.
- **Multi-language UI** — English, 简体中文, 日本語.

## Quick Start

### Install

| Chip | Download |
|------|----------|
| Apple Silicon | [Motive-arm64.dmg](https://github.com/geezerrrr/motive/releases/latest/download/Motive-arm64.dmg) |
| Intel | [Motive-x86_64.dmg](https://github.com/geezerrrr/motive/releases/latest/download/Motive-x86_64.dmg) |

> **First launch:** macOS may block unsigned apps. Go to System Settings → Privacy & Security → Click "Open Anyway".

### Configure

1. Click the menu bar icon → **Settings**
2. Select your AI provider (Claude / OpenAI / Gemini / Ollama)
3. Enter your API key

### Use

1. Press `⌥Space` to open the command bar
2. Describe what you want done, press Enter
3. The command bar disappears — the agent works in the background
4. When the agent needs approval or has a question, a native popup appears
5. Check the menu bar icon anytime for status; click to view details

For detailed guides, see the [documentation](https://motivework.app/docs).

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌥Space` | Open command bar |
| `↵` | Submit task |
| `Esc` | Dismiss command bar |
| `⌘,` | Open settings |

## FAQ

<details>
<summary><strong>How is this different from Cursor / Claude Code?</strong></summary>

Cursor needs you in its window. Claude Code needs you in the terminal. Switch away and you won't notice when they need input.

Motive runs the agent as a background process. When it needs input, a native popup appears from the menu bar regardless of what app you're in.
</details>

<details>
<summary><strong>What can it do?</strong></summary>

Anything <a href="https://github.com/anomalyco/opencode">OpenCode</a> can do — refactor code, generate files, run scripts, organize projects, write docs, and more. OpenCode handles the agent work; Motive handles the macOS experience on top.
</details>

<details>
<summary><strong>Is my data sent to the cloud?</strong></summary>

No. Sessions and history stay on your machine. The only network traffic is API requests to your chosen AI provider. Use Ollama for fully offline operation.
</details>

<details>
<summary><strong>Can I use a local LLM?</strong></summary>

Yes. Select Ollama as your provider and point it to your local instance.
</details>

<details>
<summary><strong>Why does it need Accessibility permission?</strong></summary>

To register the global hotkey (`⌥Space`) that opens the command bar from anywhere.
</details>

## Roadmap

- [ ] Scheduled tasks — recurring or time-based tasks that run automatically
- [ ] iOS companion — send tasks to your Mac from your iPhone
- [ ] Multi-agent workflows — orchestrate multiple agents on related tasks

## Build from Source

```bash
git clone https://github.com/geezerrrr/motive.git
cd motive
open Motive.xcodeproj
```

The [OpenCode](https://github.com/anomalyco/opencode) binary is bundled automatically during release builds. For development, place it at `Motive/Resources/opencode`.

## Requirements

- macOS 15.0 (Sequoia) or later
- API key for Claude, OpenAI, Gemini, or local Ollama setup

## Acknowledgments

Powered by [OpenCode](https://github.com/anomalyco/opencode) — the open-source AI coding agent.

---

<p align="center">
  <sub>Let AI wait for you, not the other way around.</sub>
</p>
