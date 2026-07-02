//
//  PermissionRequestView.swift
//  Motive
//
//  Aurora Design System - Permission Request Modal
//  Adapted for native OpenCode question/permission system.
//

import SwiftUI

struct PermissionRequestView: View {
    let request: PermissionRequest
    let onRespond: (PermissionResponse) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedOptions: Set<String> = []
    @State private var customResponse: String = ""
    @State private var showCustomInput: Bool = false

    private var isDark: Bool {
        colorScheme == .dark
    }

    var body: some View {
        VStack(spacing: 0) {
            // Backdrop
            Color.black.opacity(isDark ? 0.5 : 0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    respond(allowed: false)
                }

            // Modal Card
            VStack(alignment: .leading, spacing: AuroraSpacing.space4) {
                // Header
                HStack(alignment: .top, spacing: AuroraSpacing.space3) {
                    // Icon with gradient background
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: iconGradientColors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ).opacity(0.15)
                            )
                            .frame(width: 44, height: 44)

                        iconImage
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: iconGradientColors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }

                    VStack(alignment: .leading, spacing: AuroraSpacing.space1) {
                        Text(headerTitle)
                            .font(.Aurora.headline)
                            .foregroundColor(Color.Aurora.textPrimary)

                        requestContent
                    }
                }

                // Action Buttons
                actionButtons
            }
            .padding(AuroraSpacing.space5)
            .background(Color.Aurora.background)
            .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AuroraRadius.lg, style: .continuous)
                    .stroke(AuroraPromptStyle.borderColor, lineWidth: AuroraPromptStyle.borderWidth)
            )
            .shadow(color: Color.Aurora.accentMid.opacity(isDark ? 0.1 : 0.05), radius: 30, y: 10)
            .shadow(color: Color.black.opacity(isDark ? 0.3 : 0.15), radius: 20, y: 10)
            .padding(AuroraSpacing.space8)
        }
        .onAppear {
            if request.type == .question,
               request.options?.isEmpty ?? true
            {
                showCustomInput = true
            }
        }
    }

    // MARK: - Computed Properties

    private var headerTitle: String {
        switch request.type {
        case .question:
            return request.header ?? L10n.Permission.question
        case .permission:
            if let permType = request.permissionType {
                return "\(permType.capitalized) Permission"
            }
            return L10n.Permission.permissionRequired
        }
    }

    private var iconGradientColors: [Color] {
        switch request.type {
        case .question:
            Color.Aurora.auroraGradientColors
        case .permission:
            [Color.Aurora.warning, Color(hex: "F97316")]
        }
    }

    private var iconImage: Image {
        switch request.type {
        case .question:
            Image(systemName: "hand.raised.fill")
        case .permission:
            Image(systemName: "lock.shield.fill")
        }
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        switch request.type {
        case .question:
            // Question: Cancel + Submit
            HStack(spacing: AuroraSpacing.space3) {
                Button(action: { respond(allowed: false) }) {
                    Text(L10n.cancel)
                        .font(.Aurora.bodySmall.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AuroraSpacing.space3)
                }
                .buttonStyle(AuroraPermissionButtonStyle(style: .secondary))

                Button(action: { respond(allowed: true) }) {
                    Text(L10n.submit)
                        .font(.Aurora.bodySmall.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AuroraSpacing.space3)
                }
                .buttonStyle(AuroraPermissionButtonStyle(style: .primary))
                .disabled(isSubmitDisabled)
            }

        case .permission:
            // Permission: Reject / Allow Once / Always Allow
            HStack(spacing: AuroraSpacing.space2) {
                Button(action: { respondPermission(reply: "Reject") }) {
                    Text(L10n.reject)
                        .font(.Aurora.bodySmall.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AuroraSpacing.space3)
                }
                .buttonStyle(AuroraPermissionButtonStyle(style: .danger))

                Button(action: { respondPermission(reply: "Allow Once") }) {
                    Text(L10n.allowOnce)
                        .font(.Aurora.bodySmall.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AuroraSpacing.space3)
                }
                .buttonStyle(AuroraPermissionButtonStyle(style: .secondary))

                Button(action: { respondPermission(reply: "Always Allow") }) {
                    Text(L10n.alwaysAllow)
                        .font(.Aurora.bodySmall.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AuroraSpacing.space3)
                }
                .buttonStyle(AuroraPermissionButtonStyle(style: .primary))
            }
        }
    }

    private var isSubmitDisabled: Bool {
        if request.type == .question,
           !showCustomInput,
           let options = request.options,
           !options.isEmpty
        {
            return selectedOptions.isEmpty
        }
        return false
    }

    // MARK: - Request Content

    @ViewBuilder
    private var requestContent: some View {
        switch request.type {
        case .question:
            questionContent
        case .permission:
            toolPermissionContent
        }
    }

    private var toolPermissionContent: some View {
        VStack(alignment: .leading, spacing: AuroraSpacing.space3) {
            // Permission type badge
            if let permType = request.permissionType {
                Text(permType.uppercased())
                    .font(.Aurora.micro.weight(.bold))
                    .foregroundColor(Color.Aurora.warning)
                    .padding(.horizontal, AuroraSpacing.space2)
                    .padding(.vertical, AuroraSpacing.space1)
                    .background(Color.Aurora.warning.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.xs, style: .continuous))
            }

            // Patterns (file paths or commands)
            if let patterns = request.patterns, !patterns.isEmpty {
                VStack(alignment: .leading, spacing: AuroraSpacing.space1) {
                    ForEach(patterns, id: \.self) { pattern in
                        Text(patterns.count > 1 ? "• \(pattern)" : pattern)
                            .font(.Aurora.monoSmall)
                            .foregroundColor(Color.Aurora.textPrimary)
                    }
                }
                .padding(AuroraSpacing.space3)
                .background(Color.Aurora.surface)
                .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.sm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AuroraRadius.sm, style: .continuous)
                        .stroke(AuroraPromptStyle.subtleBorderColor, lineWidth: AuroraPromptStyle.subtleBorderWidth)
                )
            }

            // Diff preview
            if let diff = request.diff, !diff.isEmpty {
                DisclosureGroup(L10n.Permission.previewChanges) {
                    ScrollView {
                        Text(diff)
                            .font(.Aurora.monoSmall)
                            .foregroundColor(Color.Aurora.textSecondary)
                    }
                    .frame(maxHeight: 150)
                }
                .font(.Aurora.caption)
                .foregroundColor(Color.Aurora.textSecondary)
            }
        }
    }

    private var questionContent: some View {
        VStack(alignment: .leading, spacing: AuroraSpacing.space3) {
            if let question = request.question {
                Text(question)
                    .font(.Aurora.body)
                    .foregroundColor(Color.Aurora.textPrimary)
            }

            if showCustomInput {
                VStack(alignment: .leading, spacing: AuroraSpacing.space2) {
                    TextField(L10n.Permission.typeResponse, text: $customResponse)
                        .textFieldStyle(AuroraModernTextFieldStyle())
                        .onSubmit {
                            if !customResponse.trimmingCharacters(in: .whitespaces).isEmpty {
                                respond(allowed: true)
                            }
                        }

                    if request.options != nil, !request.options!.isEmpty {
                        Button("← Back to options") {
                            showCustomInput = false
                            customResponse = ""
                        }
                        .font(.Aurora.caption)
                        .foregroundColor(Color.Aurora.textSecondary)
                    }
                }
            } else if let options = request.options, !options.isEmpty {
                VStack(spacing: AuroraSpacing.space2) {
                    ForEach(options, id: \.label) { option in
                        AuroraOptionButton(
                            option: option,
                            isSelected: selectedOptions.contains(option.label),
                            isMultiSelect: request.multiSelect == true
                        ) {
                            if option.label.lowercased() == "other" {
                                showCustomInput = true
                                selectedOptions.removeAll()
                            } else if request.multiSelect == true {
                                if selectedOptions.contains(option.label) {
                                    selectedOptions.remove(option.label)
                                } else {
                                    selectedOptions.insert(option.label)
                                }
                            } else {
                                selectedOptions = [option.label]
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Response Helpers

    private func respond(allowed: Bool) {
        var response = PermissionResponse(
            requestId: request.id,
            taskId: request.taskId,
            decision: allowed ? .allow : .deny
        )

        if request.type == .question {
            if showCustomInput, !customResponse.trimmingCharacters(in: .whitespaces).isEmpty {
                response.customText = customResponse.trimmingCharacters(in: .whitespaces)
            } else if !selectedOptions.isEmpty {
                response.selectedOptions = Array(selectedOptions)
            }
        }

        onRespond(response)
    }

    private func respondPermission(reply: String) {
        var response = PermissionResponse(
            requestId: request.id,
            taskId: request.taskId,
            decision: reply == "Reject" ? .deny : .allow,
            message: reply
        )
        response.selectedOptions = [reply]
        onRespond(response)
    }
}

// MARK: - Aurora Option Button

private struct AuroraOptionButton: View {
    let option: PermissionRequest.QuestionOption
    let isSelected: Bool
    let isMultiSelect: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: AuroraSpacing.space1) {
                    Text(option.label)
                        .font(.Aurora.body.weight(.medium))
                        .foregroundColor(Color.Aurora.textPrimary)

                    if let desc = option.description {
                        Text(desc)
                            .font(.Aurora.caption)
                            .foregroundColor(Color.Aurora.textSecondary)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.Aurora.auroraGradient)
                }
            }
            .padding(AuroraSpacing.space3)
            .background(
                RoundedRectangle(cornerRadius: AuroraRadius.sm, style: .continuous)
                    .fill(isSelected ? Color.Aurora.accent.opacity(0.1) : (isHovering ? Color.Aurora.surfaceElevated : Color.Aurora.surface))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AuroraRadius.sm, style: .continuous)
                    .stroke(
                        isSelected
                            ? Color.Aurora.accent.opacity(0.3)
                            : AuroraPromptStyle.subtleBorderColor,
                        lineWidth: isSelected ? AuroraPromptStyle.emphasisBorderWidth : AuroraPromptStyle.subtleBorderWidth
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Aurora Permission Button Style

private struct AuroraPermissionButtonStyle: ButtonStyle {
    enum Style {
        case primary, secondary, danger
    }

    let style: Style
    @Environment(\.colorScheme) private var colorScheme
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
        case .danger:
            LinearGradient(
                colors: [Color.Aurora.error, Color(hex: "DC2626")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .opacity(isPressed ? 0.8 : 1.0)
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .primary, .danger: .white
        case .secondary: Color.Aurora.textPrimary
        }
    }

    @ViewBuilder
    private var overlay: some View {
        if style == .secondary {
            RoundedRectangle(cornerRadius: AuroraRadius.sm, style: .continuous)
                .stroke(AuroraPromptStyle.borderColor, lineWidth: AuroraPromptStyle.borderWidth)
        }
    }
}

// MARK: - Preview

#Preview {
    PermissionRequestView(
        request: PermissionRequest(
            id: "test",
            taskId: "task_1",
            type: .permission,
            question: "Allow edit for src/main.ts?",
            header: "Edit Permission",
            permissionType: "edit",
            patterns: ["src/main.ts"],
            diff: """
            - const x = 1;
            + const x = 2;
            """
        ),
        onRespond: { _ in }
    )
    .frame(width: 500, height: 400)
}
