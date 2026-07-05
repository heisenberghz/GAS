# GAS – Full Implementation Feature Set

## 🤖 AI Agent
- Works as a background AI coworker that continues tasks while you're focused on other work.
- Uses OpenCode as the underlying agent engine.
- Supports autonomous multi-step task execution.
- Can pause to request approval when necessary and automatically continue after receiving a response.
- Maintains live progress updates through the system tray and drawer.

## ⌨️ Keyboard-First Workflow
- Global hotkey (customizable, default Ctrl + Shift + Space).
- Instant command bar from anywhere in Windows.
- No need to switch applications.
- Quick task submission with immediate background execution.

## 🖥️ System Tray Experience
- Runs entirely from the Windows System Tray.
- Dynamic tray icon states:
  - Idle
  - Thinking
  - Executing
  - Waiting for Approval
  - Error
- Native Windows notifications for:
  - Permission requests
  - Questions from the agent
  - Task completion
  - Errors
- Left click opens the activity drawer.
- Right click opens context menu (Settings, History, Quit, etc.).

## 💬 Smart Approval System
- Native popup notifications for every action requiring user confirmation.
- Support approvals for:
  - File modifications
  - Terminal commands
  - Package installation
  - Browser actions
  - External integrations
- Approve / Reject / Always Allow options.
- Configurable trust levels.

## 🛡️ Trust Modes
- Careful: Ask permission for every action.
- Balanced: Automatically approve safe operations and ask before destructive actions.
- YOLO: Fully autonomous execution and only notify on completion or critical failures.

## 📂 Project & Workspace Awareness
- Automatically detect the active project/workspace.
- Support VS Code, Visual Studio, JetBrains IDEs, and Explorer-selected folders.
- Manual folder selection.
- Recent project history.
- No hardcoded working directories.

## 💻 Code & Development
- Read and understand entire codebases.
- Search across projects.
- Explain project architecture.
- Generate new files.
- Edit existing files.
- Refactor multiple files.
- Fix compiler/runtime errors.
- Run unit tests.
- Debug failing applications.
- Generate documentation.
- Create new projects from prompts.
- Perform multi-step development workflows autonomously.

## 📁 File System Operations
- Create files and folders.
- Read project files.
- Edit files.
- Rename files.
- Move files.
- Delete files.
- Bulk organize folders.
- Search files by content or name.
- Respect trust mode and approval rules for destructive operations.

## 🖥️ Terminal & Shell
- Execute shell commands.
- Install dependencies.
- Run build scripts.
- Run tests.
- Execute Git commands.
- Manage virtual environments.
- Support PowerShell, CMD, Bash, WSL, and Git Bash.
- Require approval for potentially destructive commands.

## 🌐 Browser Automation
- Control a real browser.
- Research topics.
- Compare products and prices.
- Fill forms.
- Download files.
- Perform multi-step web workflows.
- Log into websites (with approval).
- Place orders (with confirmation).
- Extract structured information from websites.

## 🔗 Integrations
- GitHub integration.
- Slack integration.
- Notion integration.
- Calendar integration.
- Email integration.
- MCP server support.
- OpenCode extensions.
- 50+ built-in skills.
- Plugin/extension architecture for future integrations.

## 🧩 Custom Skills
- Support custom Python skills.
- Support custom JavaScript skills.
- Skills folder auto-discovery.
- User-installable skills.
- Skill configuration UI.

## 🧠 Memory & Context
- Persistent conversation history.
- Workspace-specific memory.
- Remember previous tasks.
- Resume interrupted sessions.
- Search previous conversations.
- SQLite-backed session history.

## 🤖 AI Provider Support
- Reuse existing OpenCode configuration whenever possible.
- Support all providers supported by OpenCode, including:
  - OpenAI
  - Anthropic
  - Gemini
  - Ollama
  - Zen
  - OpenRouter
  - Future providers automatically
- Optional provider configuration inside GAS for convenience.

## ⚙️ Background Engine Management
- Automatically locate OpenCode.
- Start and monitor the background server.
- Perform health checks.
- Automatically restart on failure.
- Gracefully shut down on exit.
- Clean up child processes automatically.
- Optional bundled OpenCode installation.

## 📊 Activity Drawer
- Live transcript.
- Agent reasoning/thoughts.
- Tool execution timeline.
- Terminal output.
- File changes.
- Approval history.
- Previous sessions.
- Searchable history.

## 🔐 Security
- DPAPI-encrypted local secrets.
- SQLite local database.
- No cloud storage of conversations by GAS.
- User-controlled API credentials (if not reusing OpenCode configuration).
- Granular permission controls.

## 🚀 Quality of Life
- Launch on Windows startup.
- Configurable hotkeys.
- Custom OpenCode path.
- Theme support.
- Lightweight background memory usage.
- Portable ZIP distribution.
- Automatic update support (future).