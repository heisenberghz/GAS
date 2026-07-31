# GAS → Advanced Windows-Native Capabilities (Phase 4 & Phase 5)

This document expands **GAS (Global AI System)** beyond feature parity with Motive, positioning it as the premier native Windows desktop client for OpenCode.

It adds **Phase 4 (Advanced Agentic Architecture & Windows Integration)** and **Phase 5 (Observability, Review Workflows & Extension Ecosystem)** to the existing implementation plan without altering Phases 1–3.

---

## Overview of Added Phases

```
+-----------------------------------------------------------------------------------+
|                              GAS ARCHITECTURE MAP                                 |
+-----------------------------------------------------------------------------------+
| Phase 1: Core Protocol, Config Engine & Trust Modes (Foundation)                 |
| Phase 2: Workspace Persona, Skills/MCP, Browser Sidecar & LLM Suite              |
| Phase 3: Observability, Basic Diff Cards & Token Tracker                          |
+-----------------------------------------------------------------------------------+
| PHASE 4: ADVANCED AGENTIC & WINDOWS NATIVE INTEGRATION                             |
|  - 4.1 Multi-Agent Specialist Swarm (Planner, Coder, Research, Browser, Verifier)|
|  - 4.2 Long-Running Autonomous Background Agents & Windows Service Engine        |
|  - 4.3 Deep Windows System API Skills (Win32, WMI, PowerShell, Registry, Control)  |
|  - 4.4 Multi-IDE Workspace Auto-Tracker (VS Code, VS, Cursor, JetBrains, Terminal)|
|  - 4.5 Unified Provider Abstraction & Fallback Chain                              |
+-----------------------------------------------------------------------------------+
| PHASE 5: ADVANCED WORKFLOWS, OBSERVABILITY & EXTENSION ECOSYSTEM                   |
|  - 5.1 Dynamic Tool & Plugin Registry Engine                                      |
|  - 5.2 4-Tier Memory Architecture (Short, Task, Workspace, Preferences)           |
|  - 5.3 Agent Timeline & Visual Execution Progress View                            |
|  - 5.4 Granular File Review, Hunk Approval & Git Rollback Workflow                |
|  - 5.5 Interactive Live Browser Session & Screencast Viewer                       |
|  - 5.6 Extension Marketplace & Third-Party Plugin Ecosystem                       |
+-----------------------------------------------------------------------------------+
```

---

# PHASE 4: Advanced Agentic & Windows Native Integration

---

## 4.1 Multi-Agent Specialist Swarm

### 1. Architecture
OpenCode supports subagent delegation and specialized agent roles (`mode: "primary"` vs `mode: "subagent"`). We expand GAS to define and orchestrate a 6-agent specialist swarm:
- **Planner Agent**: Generates task breakdown (`implementation_plan.md`), handles user strategy alignment.
- **Research Agent**: Scans codebases, documentation, web queries, and dependencies.
- **Coding Agent**: Handles code generation, multi-file refactoring, and AST modifications.
- **Browser Agent**: Controls `browser-use-sidecar` for web verification, documentation, and UI testing.
- **Terminal Agent**: Executes shell commands, build scripts, tests, and environment setups.
- **Reviewer / Verifier Agent**: Performs static analysis, runs unit tests, and verifies correctness before task completion.

The primary agent delegates subtasks using OpenCode's native subagent spawn protocol (`task` tool). GAS tracks child agent execution threads, rendering agent-to-agent delegation hierarchy in the UI.

### 2. New Files to Create
- `d:\GAS\GAS\GAS.Core\Agents\AgentDefinition.cs` — Data model for agent role, prompt, mode, permitted tools, and trust override.
- `d:\GAS\GAS\GAS.Core\Agents\SwarmOrchestrator.cs` — Manages agent role definitions, config injection, and subagent state trees.
- `d:\GAS\GAS\GAS.Core\Agents\AgentRegistry.cs` — Built-in agent definitions matching Motive's `opencode.json` agent specs.

### 3. Existing Files to Modify
- `d:\GAS\GAS\GAS.Core\OpenCodeConfigGenerator.cs` — Inject multi-agent definitions into `opencode.json` (`agent` dictionary).
- `d:\GAS\GAS\GAS.App\DrawerWindow.xaml.cs` — Display subagent badge tags (`[Planner]`, `[Coder]`, `[Verifier]`) in transcript bubbles.

### 4. Integration with GAS Architecture
`SwarmOrchestrator` registers with `SettingsManager`. When a run starts, `OpenCodeConfigGenerator` serializes all 6 agent prompts and permission rules into `opencode.json`. `DrawerWindow` listens to SSE `message.updated` events to display which specialist agent is currently active.

### 5. Integration with OpenCode
Injects subagent configurations into `opencode.json`:
```json
{
  "agent": {
    "planner": { "mode": "subagent", "description": "Plans execution strategy", "permission": { "edit": "deny" } },
    "coder": { "mode": "subagent", "description": "Executes file edits", "permission": { "edit": "allow" } },
    "verifier": { "mode": "subagent", "description": "Runs tests and verifies output", "permission": { "bash": "allow" } }
  }
}
```

### 6. UI Changes Required
- Subagent header badge on message cards showing active agent persona (icon + title).
- Tree-view toggle in Drawer showing active child agent tasks.

### 7. Verification Checklist
- [ ] Submit complex multi-step prompt → verify primary agent delegates to `planner` subagent.
- [ ] Verify `opencode.json` contains 6 agent roles with distinct permission bounds.
- [ ] Subagent transcript bubbles clearly identify agent role and status.

---

## 4.2 Long-Running Autonomous Background Agents

### 1. Architecture
Enables agent tasks to run continuously in the background across system reboots, server crashes, and IDE restarts.
- **Background Service Host**: Managed by a system-tray daemon thread (`GAS.App` background worker).
- **Session State Persistence**: SQLite (`GASDbContext`) continuously snapshots active session memory buffers, step indices, and pending tasks every 15 seconds.
- **Auto-Resume Engine**: On system restart or OpenCode crash, `SessionResumeEngine` re-binds running session IDs and polls status via REST API.
- **Native Toast Notifications**: Uses Windows App Notifications (`Microsoft.Toolkit.Uwp.Notifications` / WinRT Toast API) to display rich Windows 11 notifications when background tasks require approval or finish.

### 2. New Files to Create
- `d:\GAS\GAS\GAS.Core\Services\SessionResumeEngine.cs` — Auto-resumes interrupted sessions after app/system restart.
- `d:\GAS\GAS\GAS.Core\Services\WindowsNotificationService.cs` — Native Windows 11 Toast notifications with direct action buttons (Approve / Deny / Open Drawer).
- `d:\GAS\GAS\GAS.App\TaskManagerWindow.xaml` + `.xaml.cs` — Background Agent Task Manager window (shows running, paused, scheduled, and background agents with CPU/memory usage).

### 3. Existing Files to Modify
- `d:\GAS\GAS\GAS.App\App.xaml.cs` — Initialize notification listener, background persistence timer, and task manager tray menu item.
- `d:\GAS\GAS\GAS.Core\Data\GASDbContext.cs` — Add `BackgroundAgentTask` entity table.

### 4. Integration with GAS Architecture
Hooks into `App.xaml.cs` startup. If an interrupted agent task is found in `GASDbContext`, `SessionResumeEngine` verifies server status via `OpenCodeClient.GetSessionAsync()` and resumes SSE event streaming seamlessly.

### 5. Integration with OpenCode
Uses OpenCode's `/session/{id}/prompt_async` and status APIs. Background agents use non-blocking HTTP requests, allowing GAS to track dozens of background runs without locking the UI.

### 6. UI Changes Required
- **Background Task Manager Window**: WPF DataGrid listing active tasks, runtime duration, status, and control actions (Pause, Resume, Abort, Inspect).
- **Windows Toast Notifications**: Interactive Windows 11 action toasts with inline Approve/Deny buttons for permission requests.

### 7. Verification Checklist
- [ ] Launch long-running task → kill `GAS.App.exe` → restart app → verify session auto-resumes without data loss.
- [ ] Trigger permission request while drawer is closed → verify native Windows 11 Toast notification appears with action buttons.

---

## 4.3 Deep Windows System API Skills

### 1. Architecture
Expands OpenCode's tool capability on Windows by implementing native Win32, WMI, PowerShell, and Windows API tool providers. All operations are strictly audited and gated by the `TrustLevel` engine.
Supported Windows Subsystems:
- **File Explorer & Search**: Windows Search Indexer API (`ISearchQueryHelper`), File Explorer selection integration.
- **PowerShell / CMD**: Execution with admin elevation prompts, UTF-8 output encoding, ANSI color stripping.
- **Windows Registry**: Safe `HKCU` / `HKLM` key reading and modification with explicit permission prompts.
- **Clipboard**: System clipboard read/write (text, images, file references).
- **Task Manager & Services**: Process list (`Get-Process`), service controller (`ServiceController`), startup apps (`HKCU\...\Run`).
- **Control Panel & System Settings**: Volume control (CoreAudio API), Wi-Fi status (Native Wifi API `wlanapi.dll`), Display brightness (WMI `WmiMonitorBrightness`).
- **Recycle Bin**: Safe file deletion (`SHFileOperation` `FO_DELETE` with `FOF_ALLOWUNDO` to move files to Recycle Bin instead of hard delete).

### 2. New Files to Create
- `d:\GAS\GAS\GAS.Core\Win32\NativeMethods.cs` — P/Invoke bindings for Win32, Shell32, CoreAudio, and WlanAPI.
- `d:\GAS\GAS\GAS.Core\Win32\WindowsSystemTools.cs` — Tool handler implementations for Windows-specific actions.
- `d:\GAS\GAS\GAS.Core\Win32\RecycleBinProvider.cs` — `SHFileOperation` wrapper for safe Recycle Bin file deletion.

### 3. Existing Files to Modify
- `d:\GAS\GAS\GAS.Core\ToolPermissionPolicy.cs` — Add Windows system permissions (`registry`, `system_control`, `process_manage`, `clipboard`).
- `d:\GAS\GAS\GAS.Core\OpenCodeConfigGenerator.cs` — Register Windows-native tool definitions in generated `opencode.json`.

### 4. Integration with GAS Architecture
Invoked through the `SkillManager` / MCP tool execution pipeline. When OpenCode emits a tool call like `win32_recycle_file` or `win32_get_services`, GAS routes it to `WindowsSystemTools`.

### 5. Integration with OpenCode
Exposed to OpenCode as custom MCP tools or local tool handlers in `opencode.json`.

### 6. UI Changes Required
- Settings > Trust Mode: Configure permission policies for individual Windows system tool categories (e.g. Registry: Always Ask, System Volume: Auto Approve).

### 7. Verification Checklist
- [ ] Execute file deletion tool → verify file goes to Windows Recycle Bin instead of permanent deletion.
- [ ] Query system Wi-Fi / Volume via agent prompt → verify Win32 API returns accurate system info.

---

## 4.4 Multi-IDE Workspace Auto-Tracker

### 1. Architecture
Upgrades `WorkspaceDetector.cs` to automatically detect the active project workspace across all major Windows developer tools:
- **Supported IDEs**: Visual Studio Code, Visual Studio (2022/2019), Cursor AI, JetBrains IDEs (IntelliJ, PyCharm, WebStorm, Rider, CLion), Windows Terminal, Windows File Explorer.
- **Detection Mechanism**: Win32 `GetForegroundWindow()`, UI Automation API (`UIAutomationClient`), process command-line inspection via WMI, and window title pattern parsing.
- **Auto-Switching**: When the user switches focus to a different IDE window, GAS detects the active folder path and updates command bar context instantly.
- **Multi-Workspace Concurrency**: Allows opening multiple drawer instances or tabs bound to different workspace paths simultaneously.

### 2. New Files to Create
- `d:\GAS\GAS\GAS.Core\Workspace\IDEDetector.cs` — Specialized window title & process inspector for VS Code, Visual Studio, JetBrains, and Explorer.
- `d:\GAS\GAS\GAS.Core\Workspace\WorkspaceContext.cs` — Active workspace tracking entity (path, name, active IDE type, git branch).

### 3. Existing Files to Modify
- `d:\GAS\GAS\GAS.Core\WorkspaceDetector.cs` — Integrate `IDEDetector` and background window focus hook (`SetWinEventHook`).
- `d:\GAS\GAS\GAS.App\CommandBarWindow.xaml.cs` — Auto-update breadcrumb display when active workspace changes.

### 4. Integration with GAS Architecture
`WorkspaceDetector` runs a lightweight Win32 event hook for `EVENT_SYSTEM_FOREGROUND`. On focus change, it resolves the folder path and fires `WorkspaceChanged` event to `App.xaml.cs`.

### 5. Integration with OpenCode
Sets `x-opencode-directory` header on all subsequent OpenCode REST API calls matching the newly focused workspace folder.

### 6. UI Changes Required
- Breadcrumb bar shows current IDE icon (e.g., VS Code icon, Visual Studio icon, Explorer icon) next to the project path.

### 7. Verification Checklist
- [ ] Focus a project in Visual Studio Code → press `Ctrl+Shift+Space` → verify Command Bar shows VS Code project path.
- [ ] Switch focus to Visual Studio 2022 → verify Command Bar breadcrumb switches to Visual Studio solution path.

---

## 4.5 Unified Provider Abstraction & Fallback Chain

### 1. Architecture
Provides an intelligent provider resilience layer:
- **Capability Detection**: Normalizes features across providers (e.g. vision, tool call format, context window size, streaming support).
- **Fallback Chaining**: If the primary provider fails (e.g. Anthropic rate limit / 503 error), GAS automatically fails over to a secondary provider (e.g. OpenAI GPT-4o or local Ollama) without interrupting the session.
- **Runtime Provider Switcher**: User can switch providers mid-conversation via command bar syntax (`@openai`, `@gemini`, `@claude`, `@ollama`).

### 2. New Files to Create
- `d:\GAS\GAS\GAS.Core\Providers\ProviderFallbackChain.cs` — Fallback sequence manager and health tracker.
- `d:\GAS\GAS\GAS.Core\Providers\ProviderCapabilities.cs` — Capability flags per provider (max tokens, vision support, tool call schema).

### 3. Existing Files to Modify
- `d:\GAS\GAS\GAS.Core\OpenCodeClient.cs` — Catch provider HTTP 429/500/503 errors and attempt fallback retry.
- `d:\GAS\GAS\GAS.Core\SettingsManager.cs` — Save fallback chain order in settings.

### 4. Integration with GAS Architecture
`OpenCodeClient` wraps prompt requests with `ProviderFallbackChain.ExecuteWithFallbackAsync()`.

### 5. Integration with OpenCode
Maps fallback provider selections to OpenCode model payloads (`providerID` + `modelID`).

### 6. UI Changes Required
- Status strip badge shows fallback indicator (e.g., `Claude (Failed) ➔ GPT-4o (Active)`).

### 7. Verification Checklist
- [ ] Simulate 503 API error on primary provider → verify session automatically falls back to secondary provider and completes.

---

# PHASE 5: Advanced Workflows, Observability & Extension Ecosystem

---

## 5.1 Dynamic Tool & Plugin Registry Engine

### 1. Architecture
Replaces hardcoded tool lists with a dynamic tool discovery and registration runtime:
- **Plugin Architecture**: Tools are discovered dynamically from user skill folders (`~/.gas/skills/`), MCP servers, and custom C# assemblies.
- **Lifecycle Management**: Load, unload, enable, disable, and reload tools at runtime without restarting GAS or OpenCode.
- **Tool Metadata**: Schema definition (JSON Schema), permission level, provider requirements, and execution constraints.

### 2. New Files to Create
- `d:\GAS\GAS\GAS.Core\Plugins\PluginRegistry.cs` — Dynamic plugin & tool registry.
- `d:\GAS\GAS\GAS.Core\Plugins\IToolPlugin.cs` — Interface for custom C# / MCP tool plugins.

### 3. Existing Files to Modify
- `d:\GAS\GAS\GAS.Core\Skills\SkillManager.cs` — Integrate `PluginRegistry` for dynamic loading.
- `d:\GAS\GAS\GAS.App\SettingsWindow.xaml` — Add Plugin Manager tab.

### 4. Integration with GAS Architecture
Plugins register their tool schemas with `PluginRegistry`. `OpenCodeConfigGenerator` queries `PluginRegistry` to generate tool definitions in `opencode.json`.

### 5. Integration with OpenCode
Exports tools to OpenCode via generated `opencode.json` MCP tool definitions or plugin entries.

### 6. UI Changes Required
- Settings > Plugins: Install, update, disable, or remove tools dynamically with toggle switches.

### 7. Verification Checklist
- [ ] Add a new skill folder → click Refresh in Settings → verify tool is immediately discovered and registered.

---

## 5.2 4-Tier Memory Architecture

### 1. Architecture
Implements a 4-tier memory system inspired by Motive's `motive-memory` plugin:
1. **Short-Term Memory**: Conversation context buffer during active session.
2. **Task Memory**: Intermediate goals, steps completed, and decisions made during a specific task run.
3. **Workspace Memory**: Repository architecture notes, codebase structure, and project conventions stored in `~/.gas/MEMORY.md`.
4. **Long-Term User Memory**: User preferences, coding style, tool preferences, and global rules stored in `~/.gas/USER.md`.

Uses SQLite vector embeddings / keyword search (`GASDbContext`) for fast, offline searchable memory.

### 2. New Files to Create
- `d:\GAS\GAS\GAS.Core\Memory\MemoryStore.cs` — SQLite-backed memory indexer and search engine.
- `d:\GAS\GAS\GAS.Core\Memory\MemoryQueryResult.cs` — Search result model for relevant context injection.

### 3. Existing Files to Modify
- `d:\GAS\GAS\GAS.Core\WorkspaceManager.cs` — Manage `MEMORY.md` and `USER.md` sync.
- `d:\GAS\GAS\GAS.Core\OpenCodeConfigGenerator.cs` — Point OpenCode `instructions` to memory files.

### 4. Integration with GAS Architecture
`MemoryStore` indexes user messages and agent learnings after session completion. Before sending a prompt, relevant memories are queried and injected into the prompt context.

### 5. Integration with OpenCode
Injected natively via persona file instructions (`MEMORY.md`, `USER.md`) in `opencode.json`.

### 6. UI Changes Required
- Settings > Memory: View, search, edit, or clear stored memories.

### 7. Verification Checklist
- [ ] Tell agent "Always use NamingConvention X" → start new session → verify agent recalls preference from memory.

---

## 5.3 Agent Timeline & Progress View

### 1. Architecture
Visual execution timeline in the Activity Drawer showing the agent's internal cognitive process:
- **Visual Nodes**: Goal ➔ Planning ➔ Tool Execution (Read/Write/Terminal) ➔ Verification ➔ Completion.
- **Live Progress Meter**: Estimated percentage completion based on `TodoWrite` task checklist steps.
- **Tool Visualizer**: Expandable cards showing inputs, outputs, execution duration, and status chips.

### 2. New Files to Create
- `d:\GAS\GAS\GAS.App\Controls\TimelineView.xaml` + `.xaml.cs` — Custom WPF execution timeline control.
- `d:\GAS\GAS\GAS.App\Controls\ProgressStrip.xaml` + `.xaml.cs` — Live execution progress meter bar.

### 3. Existing Files to Modify
- `d:\GAS\GAS\GAS.App\DrawerWindow.xaml` — Embed `TimelineView` and `ProgressStrip` above transcript.
- `d:\GAS\GAS\GAS.App\DrawerWindow.xaml.cs` — Feed SSE events into `TimelineView`.

### 4. Integration with GAS Architecture
Consumes events from `OpenCodeClient` (`tool.started`, `tool.completed`, `message.part.delta`).

### 5. Integration with OpenCode
Parses step indices and tool call IDs directly from OpenCode SSE event streams.

### 6. UI Changes Required
- Sleek Fluent timeline header displaying step sequence and live progress bar.

### 7. Verification Checklist
- [ ] Run a multi-step coding task → verify timeline nodes update live from Planning to Tool Execution to Verification.

---

## 5.4 Granular File Review, Hunk Approval & Git Rollback Workflow

### 1. Architecture
Gives users complete control over code changes proposed by the agent:
- **Side-by-Side Diff Viewer**: WPF side-by-side or unified diff viewer control (`DiffPlex` / WPF custom syntax highlighter).
- **Hunk-Level Selection**: Accept or reject individual line changes or file hunks before applying.
- **Batch Approval**: One-click "Approve All" or "Reject All".
- **Git Rollback**: Automatic Git commit checkpointing before agent runs, allowing instant one-click rollback (`git reset --hard`) if changes are undesirable.

### 2. New Files to Create
- `d:\GAS\GAS\GAS.App\FileReviewWindow.xaml` + `.xaml.cs` — Standalone file review and diff approval dialog.
- `d:\GAS\GAS\GAS.Core\Git\GitCheckpointService.cs` — Creates temporary stash/commit checkpoints before file-editing sessions.

### 3. Existing Files to Modify
- `d:\GAS\GAS\GAS.App\DrawerWindow.xaml.cs` — Add "Review Changes" button on file edit tool cards.
- `d:\GAS\GAS\GAS.Core\ToolPermissionPolicy.cs` — Support "Review Before Apply" permission policy.

### 4. Integration with GAS Architecture
When an agent edits a file under "Review" mode, `GitCheckpointService` snapshots state. `FileReviewWindow` displays the diff. Applying writes the file; rejecting rolls back to checkpoint.

### 5. Integration with OpenCode
Intercepts `edit` / `write` tool permissions or inspects file output diffs before finalizing.

### 6. UI Changes Required
- Fullscreen/modal Diff Review Window with green/red line highlights, checkbox per hunk, and "Apply Selected" / "Rollback" buttons.

### 7. Verification Checklist
- [ ] Agent edits 3 files → click "Review Changes" → uncheck 1 file hunk → click Apply → verify only checked hunks are written.

---

## 5.5 Interactive Live Browser Session & Screencast Viewer

### 1. Architecture
Visual observer window for browser automation tasks:
- **Live Frame Streaming**: Captures browser screencast frames or page state snapshots from `browser-use-sidecar` and displays them in a WPF image view.
- **Interactive Inspection**: Highlights interactive DOM elements with numbered overlays matching sidecar element indices.
- **User Intervention Indicator**: Displays prominent banner when browser task requires manual CAPTCHA or login completion by the user.

### 2. New Files to Create
- `d:\GAS\GAS\GAS.App\BrowserViewerWindow.xaml` + `.xaml.cs` — Live browser view and element inspector window.

### 3. Existing Files to Modify
- `d:\GAS\GAS\GAS.Core\BrowserUseBridge.cs` — Stream screenshot frame file paths and state data to UI.
- `d:\GAS\GAS\GAS.App\DrawerWindow.xaml.cs` — Add "View Browser" button on browser tool cards.

### 4. Integration with GAS Architecture
`BrowserUseBridge` emits `FrameUpdated` events when `browser-use-sidecar` generates frame snapshots.

### 5. Integration with OpenCode
Integrates with OpenCode browser tools (`browser_open`, `browser_click`, `browser_state`).

### 6. UI Changes Required
- Fluent floating window rendering live page screenshots, element indices, and interactive URL bar.

### 7. Verification Checklist
- [ ] Run browser automation task → click "View Browser" → verify live page screenshot renders with element overlays.

---

## 5.6 Extension Marketplace & Third-Party Plugin Ecosystem

### 1. Architecture
Architecture for installing third-party skills, prompt templates, and custom MCP tools from remote repositories / zip archives:
- **Plugin Installer**: Downloads and extracts skills from GitHub releases or plugin URLs into `~/.gas/skills/`.
- **Manifest Validator**: Validates plugin manifests (`plugin.json` / `SKILL.md`) for schema compliance and permission requirements.
- **Version Management**: Check for updates, upgrade plugins, or uninstall extensions cleanly.

### 2. New Files to Create
- `d:\GAS\GAS\GAS.Core\Plugins\PluginInstaller.cs` — Downloads, verifies, and installs extension packages.
- `d:\GAS\GAS\GAS.Core\Plugins\PluginManifest.cs` — Extension metadata model.

### 3. Existing Files to Modify
- `d:\GAS\GAS\GAS.App\SettingsWindow.xaml` + `.xaml.cs` — Add "Extension Marketplace / Store" UI tab.

### 4. Integration with GAS Architecture
Integrates directly with `SkillManager` and `PluginRegistry`.

### 5. Integration with OpenCode
Automatically generates tool definitions and permission rules in `opencode.json` when new plugins are installed.

### 6. UI Changes Required
- Marketplace grid view in Settings showing available plugins, descriptions, install buttons, and version tags.

### 7. Verification Checklist
- [ ] Install sample skill package via URL → verify skill installs into `~/.gas/skills/` and appears as active in Settings.

---

## Summary of New Files across Phase 4 & Phase 5

| Subsystem | New Files |
|---|---|
| **Multi-Agent Swarm (4.1)** | `AgentDefinition.cs`, `SwarmOrchestrator.cs`, `AgentRegistry.cs` |
| **Autonomous Background Agents (4.2)** | `SessionResumeEngine.cs`, `WindowsNotificationService.cs`, `TaskManagerWindow.xaml/.cs` |
| **Deep Windows Systems (4.3)** | `NativeMethods.cs`, `WindowsSystemTools.cs`, `RecycleBinProvider.cs` |
| **Multi-IDE Tracker (4.4)** | `IDEDetector.cs`, `WorkspaceContext.cs` |
| **Provider Fallback (4.5)** | `ProviderFallbackChain.cs`, `ProviderCapabilities.cs` |
| **Dynamic Plugin Registry (5.1)** | `PluginRegistry.cs`, `IToolPlugin.cs` |
| **4-Tier Memory (5.2)** | `MemoryStore.cs`, `MemoryQueryResult.cs` |
| **Agent Timeline (5.3)** | `TimelineView.xaml/.cs`, `ProgressStrip.xaml/.cs` |
| **File Review Workflow (5.4)** | `FileReviewWindow.xaml/.cs`, `GitCheckpointService.cs` |
| **Browser Session Viewer (5.5)** | `BrowserViewerWindow.xaml/.cs` |
| **Extension Marketplace (5.6)** | `PluginInstaller.cs`, `PluginManifest.cs` |

---

## Overall Verification Roadmap
1. **Compilation**: `dotnet build GAS.sln` must compile cleanly with 0 errors after each phase module.
2. **Backward Compatibility**: Existing Phase 1–3 functionality (Command Bar, Drawer, Settings, SQLite persistence) remains untouched and functional.
3. **End-to-End Test**: Execute complex multi-agent coding and browser tasks on live Windows system to confirm zero regressions and maximum agentic capability.
