# Security Policy

## Supported Versions

| Version | Supported          |
|---------|--------------------|
| 0.1.x   | :white_check_mark: |

## Reporting a Vulnerability

If you discover a security vulnerability, please report it responsibly:

1. **Do not** open a public issue
2. Email details to: [wayne.li.1984@gmail.com] *(update with your contact)*
3. Include:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if any)

We aim to respond within 48 hours and will work with you to understand and address the issue.

## Security Considerations

### API Keys

- Stored in macOS Keychain, never in plain text or UserDefaults
- Never logged or transmitted except to configured AI providers

### Process Isolation

- OpenCode runs as a separate process with limited environment
- File operations require explicit user permission

### Network

- All AI provider communication uses HTTPS
- No telemetry or analytics collected

### Permissions

- Accessibility permission required only for global hotkey
- File access controlled through permission prompts

## Third-Party Dependencies

Motive relies on:

- **OpenCode** — AI agent CLI (bundled binary)
- No other runtime dependencies

## Updates

Security updates will be released as patch versions. We recommend always using the latest release.
