//
//  OnboardingWelcomeStep.swift
//  Motive
//
//  Aurora Design System - Onboarding Flow
//

import SwiftUI

// MARK: - Aurora Welcome Step

struct AuroraWelcomeStep: View {
    let onContinue: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool {
        colorScheme == .dark
    }

    var body: some View {
        VStack(spacing: AuroraSpacing.space6) {
            Spacer()

            // App icon with glow
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: Color.Aurora.auroraGradientColors.map { $0.opacity(0.2) },
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                    .blur(radius: 20)

                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 100, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: Color.Aurora.accentMid.opacity(0.3), radius: 20, y: 8)
            }

            VStack(spacing: AuroraSpacing.space3) {
                Text(L10n.Onboarding.welcomeTitle)
                    .font(.Aurora.display)
                    .foregroundColor(Color.Aurora.textPrimary)

                Text(L10n.Onboarding.welcomeSubtitle)
                    .font(.Aurora.body)
                    .foregroundColor(Color.Aurora.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AuroraSpacing.space10)
            }

            Spacer()

            Button(action: onContinue) {
                HStack(spacing: AuroraSpacing.space2) {
                    Text(L10n.Onboarding.getStarted)
                        .font(.Aurora.body.weight(.semibold))
                    Image(systemName: "arrow.right")
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
