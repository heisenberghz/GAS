//
//  OnboardingCompleteStep.swift
//  Motive
//
//  Aurora Design System - Onboarding Flow
//

import SwiftUI

// MARK: - Aurora Complete Step

struct AuroraCompleteStep: View {
    @EnvironmentObject var configManager: ConfigManager
    let onFinish: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool {
        colorScheme == .dark
    }

    var body: some View {
        VStack(spacing: AuroraSpacing.space6) {
            Spacer()

            // Success icon with gradient
            ZStack {
                Circle()
                    .fill(Color.Aurora.success.opacity(0.15))
                    .frame(width: 80, height: 80)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 50))
                    .foregroundColor(Color.Aurora.success)
            }

            VStack(spacing: AuroraSpacing.space3) {
                Text(L10n.Onboarding.completeTitle)
                    .font(.Aurora.title1)
                    .foregroundColor(Color.Aurora.textPrimary)

                Text(L10n.Onboarding.completeSubtitle)
                    .font(.Aurora.body)
                    .foregroundColor(Color.Aurora.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AuroraSpacing.space10)
            }

            // Hotkey display
            VStack(spacing: AuroraSpacing.space2) {
                Text(L10n.Onboarding.hotkeyLabel)
                    .font(.Aurora.bodySmall)
                    .foregroundColor(Color.Aurora.textSecondary)

                Text(configManager.hotkey)
                    .font(.system(size: 28, weight: .medium, design: .rounded))
                    .foregroundColor(Color.Aurora.textPrimary)
                    .padding(.horizontal, AuroraSpacing.space6)
                    .padding(.vertical, AuroraSpacing.space3)
                    .background(
                        RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                            .fill(Color.Aurora.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                                    .stroke(Color.Aurora.auroraGradient, lineWidth: 1.5)
                            )
                    )
            }
            .padding(.top, AuroraSpacing.space3)

            Text(L10n.Onboarding.hotkeyHint)
                .font(.Aurora.caption)
                .foregroundColor(Color.Aurora.textMuted)

            Spacer()

            Button(action: onFinish) {
                HStack(spacing: AuroraSpacing.space2) {
                    Text(L10n.Onboarding.startUsing)
                        .font(.Aurora.body.weight(.semibold))
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AuroraSpacing.space4)
                .background(Color.Aurora.auroraGradient)
                .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous))
                .shadow(color: Color.Aurora.accentMid.opacity(0.4), radius: 16, y: 8)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, AuroraSpacing.space12)
            .padding(.bottom, AuroraSpacing.space10)
        }
    }
}
