# Contributing to GAS

Thanks for your interest in contributing! This document outlines how to get involved.

## Ways to Contribute

- **Bug reports** â€” Found something broken? Open an issue with steps to reproduce.
- **Feature requests** â€” Have an idea? Start a discussion first to gauge interest.
- **Pull requests** â€” Code contributions are welcome for approved issues.
- **Documentation** â€” Improvements to docs, README, or code comments.

## Development Setup

```bash
# Clone
git clone https://github.com/geezerrrr/GAS.git
cd GAS

# Open in Xcode
open GAS.xcodeproj

# Build and run (âŒ˜R)
```

### Requirements

- macOS 15.0+
- Xcode 16.0+
- Swift 6.0

### Xcode Signing Configuration

After opening the project, configure signing in Xcode:

1. Select the project root in the sidebar
2. Go to **Signing & Capabilities** tab
3. Select your **Development Team** for the **GAS** target

**Important**: Please **do not commit** changes to `DEVELOPMENT_TEAM` in your pull requests. The `.pbxproj` file may show your team ID locally â€” this is expected. When submitting PRs, only commit functional code changes.

### OpenCode Binary

For development, download and place the OpenCode binary:

```bash
# Apple Silicon
curl -L https://github.com/anomalyco/opencode/releases/latest/download/opencode-darwin-arm64.zip -o opencode.zip
unzip opencode.zip && mv opencode GAS/Resources/ && rm opencode.zip

# Intel
curl -L https://github.com/anomalyco/opencode/releases/latest/download/opencode-darwin-x64.zip -o opencode.zip
unzip opencode.zip && mv opencode GAS/Resources/ && rm opencode.zip
```

## Pull Request Guidelines

1. **One PR per feature/fix** â€” Keep changes focused and reviewable
2. **Follow existing style** â€” Match the codebase conventions
3. **Test your changes** â€” Verify on both light and dark mode
4. **Write meaningful commits** â€” Use clear, descriptive messages

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
GAS/
â”œâ”€â”€ App/        # Application lifecycle, delegates
â”œâ”€â”€ Core/       # Business logic (OpenCodeBridge, ConfigManager)
â”œâ”€â”€ Data/       # SwiftData models
â”œâ”€â”€ UI/         # SwiftUI views by feature
â””â”€â”€ Resources/  # Assets, bundled binaries
```

## Questions?

Open a [Discussion](https://github.com/geezerrrr/GAS/discussions) for general questions or ideas.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

