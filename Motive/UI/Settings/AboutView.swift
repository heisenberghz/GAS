//
//  AboutView.swift
//  Motive
//
//  Compact About page with open-source acknowledgments
//

import SwiftUI

struct AboutView: View {
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool {
        colorScheme == .dark
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                // Hero: Logo + Name + Version
                heroSection

                // Open Source Acknowledgments
                acknowledgementsSection

                // Action buttons
                actionButtons
            }
            .padding(.vertical, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Hero Section

    private var heroSection: some View {
        VStack(spacing: 14) {
            // App Logo
            ZStack {
                if let logoImage = NSImage(named: isDark ? "logo-light" : "logo-dark") {
                    Image(nsImage: logoImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.Aurora.primary)
                        .frame(width: 72, height: 72)
                        .overlay(
                            Text("M")
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        )
                }
            }
            .shadow(color: Color.black.opacity(0.12), radius: 12, y: 4)

            VStack(spacing: 4) {
                // App Name
                Text(L10n.appName)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(Color.Aurora.textPrimary)

                // Version
                Text("\(L10n.Settings.version) \(appVersion) (\(buildNumber))")
                    .font(.system(size: 12))
                    .foregroundColor(Color.Aurora.textSecondary)
            }

            // Copyright
            Text(L10n.Settings.allRightsReserved)
                .font(.system(size: 11))
                .foregroundColor(Color.Aurora.textMuted)
        }
    }

    // MARK: - Acknowledgements Section

    private var acknowledgementsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.Settings.poweredBy)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color.Aurora.textMuted)
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                // OpenCode
                AcknowledgementRow(
                    name: "OpenCode",
                    description: "AI-powered coding agent",
                    license: "MIT",
                    url: "https://github.com/anomalyco/opencode"
                )

                Divider()
                    .padding(.leading, 16)

                // Browser-use
                AcknowledgementRow(
                    name: "Browser Use",
                    description: "Web automation for AI agents",
                    license: "MIT",
                    url: "https://github.com/browser-use/browser-use",
                    showDivider: false
                )
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.Aurora.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(SettingsUIStyle.borderColor, lineWidth: SettingsUIStyle.borderWidth)
            )
        }
        .frame(maxWidth: 400)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 10) {
            AboutActionButton(
                title: "GitHub",
                icon: "link",
                action: {
                    if let url = URL(string: "https://github.com/AugustDev/motive") {
                        NSWorkspace.shared.open(url)
                    }
                }
            )

            AboutActionButton(
                title: "Feedback",
                icon: "bubble.left",
                action: {
                    if let url = URL(string: "https://github.com/AugustDev/motive/issues") {
                        NSWorkspace.shared.open(url)
                    }
                }
            )

            AboutActionButton(
                title: "License",
                icon: "doc.text",
                action: {
                    if let url = URL(string: "https://github.com/AugustDev/motive/blob/main/LICENSE") {
                        NSWorkspace.shared.open(url)
                    }
                }
            )
        }
    }
}

// MARK: - Acknowledgement Row

private struct AcknowledgementRow: View {
    let name: String
    let description: String
    let license: String
    let url: String
    var showDivider: Bool = true

    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool {
        colorScheme == .dark
    }

    var body: some View {
        Button {
            if let url = URL(string: url) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color.Aurora.textPrimary)

                        Text(license)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color.Aurora.primary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color.Aurora.primary.opacity(0.12))
                            )
                    }

                    Text(description)
                        .font(.system(size: 11))
                        .foregroundColor(Color.Aurora.textMuted)
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color.Aurora.textMuted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(isHovering ? (isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.02)) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Action Button

private struct AboutActionButton: View {
    let title: String
    var icon: String?
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool {
        colorScheme == .dark
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                }
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(Color.Aurora.textPrimary)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(borderColor, lineWidth: SettingsUIStyle.borderWidth)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var backgroundColor: Color {
        if isHovering {
            return isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
        }
        return isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.03)
    }

    private var borderColor: Color {
        isDark ? Color.white.opacity(0.08) : SettingsUIStyle.borderColor
    }
}
