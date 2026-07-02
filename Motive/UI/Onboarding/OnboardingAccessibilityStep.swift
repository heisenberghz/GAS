//
//  OnboardingAccessibilityStep.swift
//  Motive
//
//  Aurora Design System - Onboarding Flow
//

import SwiftUI

// MARK: - Aurora Accessibility Step

struct AuroraAccessibilityStep: View {
    let onContinue: () -> Void
    let onSkip: () -> Void

    @State private var hasPermission: Bool = false
    @State private var checkTask: Task<Void, Never>?
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool {
        colorScheme == .dark
    }

    var body: some View {
        VStack(spacing: AuroraSpacing.space5) {
            // Header
            VStack(spacing: AuroraSpacing.space2) {
                Image(systemName: hasPermission ? "checkmark.shield.fill" : "hand.raised.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(hasPermission ? AnyShapeStyle(Color.Aurora.success) : AnyShapeStyle(Color.Aurora.auroraGradient))

                Text(L10n.Onboarding.accessibilityTitle)
                    .font(.Aurora.title2)
                    .foregroundColor(Color.Aurora.textPrimary)

                Text(L10n.Onboarding.accessibilitySubtitle)
                    .font(.Aurora.bodySmall)
                    .foregroundColor(Color.Aurora.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AuroraSpacing.space5)
            }
            .padding(.top, AuroraSpacing.space5)

            // Status Card
            VStack(spacing: AuroraSpacing.space4) {
                HStack(spacing: AuroraSpacing.space3) {
                    // Status icon with background
                    ZStack {
                        Circle()
                            .fill(hasPermission ? Color.Aurora.success.opacity(0.15) : Color.Aurora.warning.opacity(0.15))
                            .frame(width: 36, height: 36)

                        Image(systemName: hasPermission ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(hasPermission ? Color.Aurora.success : Color.Aurora.warning)
                    }

                    VStack(alignment: .leading, spacing: AuroraSpacing.space1) {
                        Text(hasPermission ? L10n.Onboarding.accessibilityGranted : L10n.Onboarding.accessibilityRequired)
                            .font(.Aurora.body.weight(.medium))
                            .foregroundColor(Color.Aurora.textPrimary)

                        Text(hasPermission ? L10n.Onboarding.hotkeyReady : L10n.Onboarding.hotkeyRequired)
                            .font(.Aurora.caption)
                            .foregroundColor(Color.Aurora.textSecondary)
                    }

                    Spacer()
                }
                .padding(AuroraSpacing.space4)
                .background(
                    RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                        .fill(Color.Aurora.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                        .stroke(
                            hasPermission ? Color.Aurora.success.opacity(0.3) : Color.Aurora.warning.opacity(0.3),
                            lineWidth: 1
                        )
                )

                if !hasPermission {
                    Button(action: openAccessibilitySettings) {
                        HStack(spacing: AuroraSpacing.space2) {
                            Image(systemName: "gear")
                                .font(.system(size: 14, weight: .medium))
                            Text(L10n.Onboarding.openSystemSettings)
                                .font(.Aurora.body.weight(.medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AuroraSpacing.space3)
                    }
                    .buttonStyle(AuroraOnboardingButtonStyle(style: .secondary))
                }
            }
            .padding(.horizontal, AuroraSpacing.space10)

            if !hasPermission {
                Text(L10n.Onboarding.accessibilityInstructions)
                    .font(.Aurora.caption)
                    .foregroundColor(Color.Aurora.textMuted)
                    .padding(.horizontal, AuroraSpacing.space10)
            }

            Spacer()

            // Buttons
            HStack(spacing: AuroraSpacing.space3) {
                Button(action: onSkip) {
                    Text(L10n.Onboarding.skip)
                        .font(.Aurora.body.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AuroraSpacing.space3)
                }
                .buttonStyle(AuroraOnboardingButtonStyle(style: .secondary))

                Button(action: onContinue) {
                    Text(L10n.Onboarding.continueButton)
                        .font(.Aurora.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AuroraSpacing.space3)
                }
                .buttonStyle(AuroraOnboardingButtonStyle(style: .primary))
            }
            .padding(.horizontal, AuroraSpacing.space10)
            .padding(.bottom, AuroraSpacing.space8)
        }
        .onAppear {
            checkPermission()
            startPermissionCheck()
        }
        .onDisappear {
            checkTask?.cancel()
        }
    }

    private func checkPermission() {
        hasPermission = AccessibilityHelper.hasPermission
    }

    private func startPermissionCheck() {
        checkTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                checkPermission()
            }
        }
    }

    private func openAccessibilitySettings() {
        AccessibilityHelper.openAccessibilitySettings()
    }
}
