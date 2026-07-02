# Contributing to Motive

Thanks for your interest in contributing! This document outlines how to get involved.

## Ways to Contribute

- **Bug reports** — Found something broken? Open an issue with steps to reproduce.
- **Feature requests** — Have an idea? Start a discussion first to gauge interest.
- **Pull requests** — Code contributions are welcome for approved issues.
- **Documentation** — Improvements to docs, README, or code comments.

## Development Setup

```bash
# Clone
git clone https://github.com/geezerrrr/motive.git
cd motive

# Open in Xcode
open Motive.xcodeproj

# Build and run (⌘R)
```

### Requirements

- macOS 15.0+
- Xcode 16.0+
- Swift 6.0

### Xcode Signing Configuration

After opening the project, configure signing in Xcode:

1. Select the project root in the sidebar
2. Go to **Signing & Capabilities** tab
3. Select your **Development Team** for the **Motive** target

**Important**: Please **do not commit** changes to `DEVELOPMENT_TEAM` in your pull requests. The `.pbxproj` file may show your team ID locally — this is expected. When submitting PRs, only commit functional code changes.

### OpenCode Binary

For development, download and place the OpenCode binary:

```bash
# Apple Silicon
curl -L https://github.com/anomalyco/opencode/releases/latest/download/opencode-darwin-arm64.zip -o opencode.zip
unzip opencode.zip && mv opencode Motive/Resources/ && rm opencode.zip

# Intel
curl -L https://github.com/anomalyco/opencode/releases/latest/download/opencode-darwin-x64.zip -o opencode.zip
unzip opencode.zip && mv opencode Motive/Resources/ && rm opencode.zip
```

## Pull Request Guidelines

1. **One PR per feature/fix** — Keep changes focused and reviewable
2. **Follow existing style** — Match the codebase conventions
3. **Test your changes** — Verify on both light and dark mode
4. **Write meaningful commits** — Use clear, descriptive messages

### Commit Style

```
type: brief description

Longer explanation if needed.
```

Types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`

## Code Style

- Swift 6 with strict concurrency
- SwiftUI for views, AppKit only for window-level customization
- Use `@MainActor` appropriately
- Prefer `async/await` over callbacks

## Project Structure

```
Motive/
├── App/        # Application lifecycle, delegates
├── Core/       # Business logic (OpenCodeBridge, ConfigManager)
├── Data/       # SwiftData models
├── UI/         # SwiftUI views by feature
└── Resources/  # Assets, bundled binaries
```

## Questions?

Open a [Discussion](https://github.com/geezerrrr/motive/discussions) for general questions or ideas.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
