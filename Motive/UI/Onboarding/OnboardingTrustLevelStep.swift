//
//  OnboardingTrustLevelStep.swift
//  Motive
//
//  Aurora Design System - Onboarding Flow
//

import SwiftUI

// MARK: - Aurora Trust Level Step

struct AuroraTrustLevelStep: View {
    @EnvironmentObject var configManager: ConfigManager
    let onContinue: () -> Void
    let onSkip: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool {
        colorScheme == .dark
    }

    var body: some View {
        VStack(spacing: AuroraSpacing.space4) {
            // Header
            VStack(spacing: AuroraSpacing.space2) {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.Aurora.auroraGradient)

                Text(L10n.Onboarding.permissionMode)
                    .font(.Aurora.title2)
                    .foregroundColor(Color.Aurora.textPrimary)

                Text(L10n.Onboarding.permissionModeDesc)
                    .font(.Aurora.bodySmall)
                    .foregroundColor(Color.Aurora.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, AuroraSpacing.space4)

            // Trust level cards
            VStack(spacing: AuroraSpacing.space2) {
                ForEach(TrustLevel.allCases, id: \.self) { level in
                    trustLevelRow(level)
                }
            }
            .padding(.horizontal, AuroraSpacing.space10)

            // YOLO warning
            if configManager.trustLevel == .yolo {
                HStack(spacing: AuroraSpacing.space2) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Color.Aurora.warning)
                    Text(L10n.Onboarding.permissionYoloWarning)
                        .font(.Aurora.caption)
                        .foregroundColor(Color.Aurora.warning)
                }
                .padding(.horizontal, AuroraSpacing.space10)
            }

            Text(L10n.Onboarding.permissionChangeHint)
                .font(.Aurora.caption)
                .foregroundColor(Color.Aurora.textMuted)
                .padding(.horizontal, AuroraSpacing.space10)

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
    }

    private func trustLevelRow(_ level: TrustLevel) -> some View {
        let isSelected = configManager.trustLevel == level

        return Button(action: {
            withAnimation(.auroraFast) {
                configManager.trustLevel = level
            }
        }) {
            HStack(spacing: AuroraSpacing.space3) {
                Image(systemName: level.systemSymbol)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(isSelected ? .white : Color.Aurora.textSecondary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(level.displayName)
                        .font(.Aurora.bodySmall.weight(.semibold))
                        .foregroundColor(isSelected ? .white : Color.Aurora.textPrimary)

                    Text(level.description)
                        .font(.Aurora.caption)
                        .foregroundColor(isSelected ? .white.opacity(0.8) : Color.Aurora.textMuted)
                        .lineLimit(1)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, AuroraSpacing.space4)
            .padding(.vertical, AuroraSpacing.space3)
            .background(
                RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(Color.Aurora.auroraGradient) : AnyShapeStyle(Color.Aurora.surface))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                    .stroke(isSelected ? Color.clear : Color.Aurora.border, lineWidth: 1)
            )
            .shadow(color: isSelected ? Color.Aurora.accentMid.opacity(0.25) : .clear, radius: 6, y: 3)
        }
        .buttonStyle(.plain)
    }
}
