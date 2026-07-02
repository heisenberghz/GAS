//
//  OnboardingView.swift
//  Motive
//
//  Aurora Design System - Onboarding Flow
//

import SwiftUI

// MARK: - Onboarding View

struct OnboardingView: View {
    @EnvironmentObject var configManager: ConfigManager
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @State private var currentStep: OnboardingStep = .welcome

    private var isDark: Bool {
        colorScheme == .dark
    }

    enum OnboardingStep: Int, CaseIterable {
        case welcome
        case aiProvider
        case accessibility
        case browserAutomation
        case trustLevel
        case complete

        var next: OnboardingStep? {
            OnboardingStep(rawValue: rawValue + 1)
        }

        var previous: OnboardingStep? {
            OnboardingStep(rawValue: rawValue - 1)
        }
    }

    var body: some View {
        ZStack {
            // Aurora background
            Color.Aurora.backgroundDeep
                .ignoresSafeArea()

            // Subtle gradient overlay
            if isDark {
                LinearGradient(
                    colors: [
                        Color.Aurora.accentMid.opacity(0.05),
                        Color.clear,
                        Color.Aurora.accentStart.opacity(0.03)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                // Progress indicator
                if currentStep != .welcome, currentStep != .complete {
                    AuroraOnboardingProgress(currentStep: currentStep)
                        .padding(.top, AuroraSpacing.space5)
                        .padding(.bottom, AuroraSpacing.space3)
                }

                // Content
                Group {
                    switch currentStep {
                    case .welcome:
                        AuroraWelcomeStep(onContinue: { goToNext() })
                    case .aiProvider:
                        AuroraAIProviderStep(
                            onContinue: { goToNext() },
                            onSkip: { goToNext() }
                        )
                    case .accessibility:
                        AuroraAccessibilityStep(
                            onContinue: { goToNext() },
                            onSkip: { goToNext() }
                        )
                    case .browserAutomation:
                        AuroraBrowserStep(
                            onContinue: { goToNext() },
                            onSkip: { goToNext() }
                        )
                    case .trustLevel:
                        AuroraTrustLevelStep(
                            onContinue: { goToNext() },
                            onSkip: { goToNext() }
                        )
                    case .complete:
                        AuroraCompleteStep(onFinish: { completeOnboarding() })
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
                .animation(.auroraSpring, value: currentStep)
            }
            .frame(width: 520, height: 480)
        }
    }

    private func goToNext() {
        withAnimation {
            if let next = currentStep.next {
                currentStep = next
            }
        }
    }

    private func completeOnboarding() {
        configManager.hasCompletedOnboarding = true
        NotificationCenter.default.post(name: .onboardingCompleted, object: nil)
    }
}

// MARK: - Notification Extension

extension Notification.Name {
    static let onboardingCompleted = Notification.Name("onboardingCompleted")
}

// MARK: - Aurora Onboarding Settings Row

struct OnboardingSettingsRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AuroraSpacing.space4)
            .padding(.vertical, AuroraSpacing.space3)
    }
}

// MARK: - Aurora Progress Indicator

struct AuroraOnboardingProgress: View {
    let currentStep: OnboardingView.OnboardingStep

    private let steps: [OnboardingView.OnboardingStep] = [.aiProvider, .accessibility, .browserAutomation, .trustLevel]

    var body: some View {
        HStack(spacing: AuroraSpacing.space2) {
            ForEach(steps, id: \.rawValue) { step in
                Circle()
                    .fill(
                        step.rawValue <= currentStep.rawValue
                            ? AnyShapeStyle(Color.Aurora.auroraGradient)
                            : AnyShapeStyle(Color.Aurora.textMuted.opacity(0.3))
                    )
                    .frame(width: 8, height: 8)
            }
        }
    }
}

// MARK: - Aurora Onboarding Button Style

struct AuroraOnboardingButtonStyle: ButtonStyle {
    enum Style { case primary, secondary }
    let style: Style

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(background(isPressed: configuration.isPressed))
            .foregroundColor(foregroundColor)
            .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.sm, style: .continuous))
            .overlay(overlay)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(isEnabled ? 1.0 : 0.5)
            .animation(.auroraSpringStiff, value: configuration.isPressed)
    }

    @ViewBuilder
    private func background(isPressed: Bool) -> some View {
        switch style {
        case .primary:
            LinearGradient(
                colors: Color.Aurora.auroraGradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .opacity(isPressed ? 0.8 : 1.0)
        case .secondary:
            Color.Aurora.surface
                .opacity(isPressed ? 0.8 : 1.0)
        }
    }

    private var foregroundColor: Color {
        style == .primary ? .white : Color.Aurora.textPrimary
    }

    @ViewBuilder
    private var overlay: some View {
        if style == .secondary {
            RoundedRectangle(cornerRadius: AuroraRadius.sm, style: .continuous)
                .stroke(Color.Aurora.border, lineWidth: 1)
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingView()
        .environmentObject(ConfigManager())
        .environmentObject(AppState(configManager: ConfigManager()))
}
