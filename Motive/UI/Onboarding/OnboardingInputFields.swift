//
//  OnboardingInputFields.swift
//  Motive
//
//  Aurora Design System - Onboarding Flow
//

import SwiftUI

// MARK: - Aurora Input Field Style

enum AuroraInputFieldStyle {
    static let height: CGFloat = 36
    static let horizontalPadding: CGFloat = AuroraSpacing.space3
    static let cornerRadius: CGFloat = AuroraRadius.sm

    /// Shared input background color matching the onboarding card surface.
    static func backgroundColor(isDark: Bool) -> Color {
        isDark ? Color(red: 0x19 / 255.0, green: 0x19 / 255.0, blue: 0x19 / 255.0)
            : Color(red: 0xFA / 255.0, green: 0xFA / 255.0, blue: 0xFA / 255.0)
    }
}

// MARK: - Aurora Styled Text Field

struct StyledTextField: View {
    let placeholder: String
    @Binding var text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.Aurora.body)
            .foregroundColor(Color.Aurora.textPrimary)
            .padding(.horizontal, AuroraInputFieldStyle.horizontalPadding)
            .frame(height: AuroraInputFieldStyle.height)
            .background(
                RoundedRectangle(cornerRadius: AuroraInputFieldStyle.cornerRadius, style: .continuous)
                    .fill(AuroraInputFieldStyle.backgroundColor(isDark: colorScheme == .dark))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AuroraInputFieldStyle.cornerRadius, style: .continuous)
                    .stroke(Color.Aurora.border, lineWidth: 1)
            )
    }
}

// MARK: - Aurora Secure Input Field

struct SecureInputField: View {
    let placeholder: String
    @Binding var text: String
    @State private var showingText: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if showingText {
                    TextField(placeholder, text: $text)
                } else {
                    SecureField(placeholder, text: $text)
                }
            }
            .textFieldStyle(.plain)
            .font(.Aurora.body)
            .foregroundColor(Color.Aurora.textPrimary)

            Button(action: { showingText.toggle() }) {
                Image(systemName: showingText ? "eye.slash" : "eye")
                    .foregroundColor(Color.Aurora.textMuted)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .padding(.trailing, AuroraSpacing.space1)
        }
        .padding(.horizontal, AuroraInputFieldStyle.horizontalPadding)
        .frame(height: AuroraInputFieldStyle.height)
        .background(
            RoundedRectangle(cornerRadius: AuroraInputFieldStyle.cornerRadius, style: .continuous)
                .fill(AuroraInputFieldStyle.backgroundColor(isDark: colorScheme == .dark))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AuroraInputFieldStyle.cornerRadius, style: .continuous)
                .stroke(Color.Aurora.border, lineWidth: 1)
        )
    }
}
