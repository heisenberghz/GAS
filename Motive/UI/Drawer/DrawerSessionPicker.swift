//
//  DrawerSessionPicker.swift
//  Motive
//
//  Aurora Design System - Session picker overlay for drawer
//

import SwiftUI

struct DrawerSessionPicker: View {
    @EnvironmentObject private var appState: AppState
    let sessions: [Session]
    @Binding var showSessionPicker: Bool
    let onLoadSessions: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Dismiss area
            Color.black.opacity(0.01)
                .onTapGesture {
                    withAnimation(.auroraFast) {
                        showSessionPicker = false
                    }
                }

            // Dropdown menu
            VStack(spacing: 0) {
                if sessions.isEmpty {
                    Text(L10n.Drawer.noHistory)
                        .font(.Aurora.caption)
                        .foregroundColor(Color.Aurora.textMuted)
                        .padding(AuroraSpacing.space4)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(sessions.prefix(15)) { session in
                                SessionPickerItem(session: session) {
                                    appState.switchToSession(session)
                                    withAnimation(.auroraFast) {
                                        showSessionPicker = false
                                    }
                                } onDelete: {
                                    appState.deleteSession(session)
                                    onLoadSessions()
                                }
                            }
                        }
                        .padding(AuroraSpacing.space2)
                    }
                    .frame(maxHeight: 300)
                }
            }
            .frame(width: 280)
            .background(
                RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                    .fill(Color.Aurora.surface)
                    .shadow(color: Color.black.opacity(0.15), radius: 16, y: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                    .strokeBorder(Color.Aurora.border.opacity(0.4), lineWidth: 0.5)
            )
            .padding(.top, 52) // Below header
            .padding(.leading, AuroraSpacing.space4)
        }
        .transition(.opacity)
    }
}

// MARK: - Session Picker Item

struct SessionPickerItem: View {
    let session: Session
    let onSelect: () -> Void
    let onDelete: () -> Void
    @EnvironmentObject private var appState: AppState

    @State private var isHovering = false
    @State private var isPulsing = false

    private var isRunning: Bool {
        session.sessionStatus == .running
    }

    var body: some View {
        HStack(spacing: AuroraSpacing.space3) {
            // Status indicator
            statusIndicator

            // Session info
            VStack(alignment: .leading, spacing: 2) {
                Text(session.intent)
                    .font(.Aurora.bodySmall.weight(.medium))
                    .foregroundColor(Color.Aurora.textPrimary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.Aurora.caption)
                    .foregroundColor(isRunning ? Color.Aurora.success : Color.Aurora.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Delete button (separate hit target, only on hover, not for running sessions)
            if isHovering, !isRunning {
                Button(action: {
                    showDeleteConfirmation()
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color.Aurora.textMuted)
                        .frame(width: 20, height: 20)
                        .background(Color.Aurora.glassOverlay.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.CommandBar.delete)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, AuroraSpacing.space3)
        .padding(.vertical, AuroraSpacing.space2)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.sm, style: .continuous)
                .fill(isHovering ? Color.Aurora.surfaceElevated : Color.clear)
        )
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
        .animation(.auroraFast, value: isHovering)
    }

    // MARK: - Status Indicator

    @ViewBuilder
    private var statusIndicator: some View {
        if isRunning {
            // Pulsing dot for running sessions
            Circle()
                .fill(Color.Aurora.success)
                .frame(width: 6, height: 6)
                .opacity(isPulsing ? 0.4 : 1.0)
                .animation(
                    .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                    value: isPulsing
                )
                .onAppear { isPulsing = true }
        } else {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
        }
    }

    // MARK: - Helpers

    private var subtitle: String {
        if isRunning {
            return "Running"
        }
        return timeAgo
    }

    private func showDeleteConfirmation() {
        guard let window = appState.drawerWindowRef else { return }

        appState.setDrawerAutoHideSuppressed(true)

        let alert = NSAlert()
        alert.messageText = L10n.Alert.deleteSessionTitle
        let sessionName = String(session.intent.prefix(50))
        alert.informativeText = String(format: L10n.Alert.deleteSessionMessage, sessionName)
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.CommandBar.delete)
        alert.addButton(withTitle: L10n.CommandBar.cancel)

        alert.beginSheetModal(for: window) { [onDelete] response in
            if response == .alertFirstButtonReturn {
                onDelete()
            }
            appState.setDrawerAutoHideSuppressed(false)
            window.makeKeyAndOrderFront(nil)
        }
    }

    private var statusColor: Color {
        switch session.sessionStatus {
        case .running: Color.Aurora.success
        case .completed: Color.Aurora.accent
        case .failed: Color.Aurora.error
        case .interrupted: Color.Aurora.warning
        default: Color.Aurora.textMuted
        }
    }

    private var timeAgo: String {
        let now = Date()
        let diff = now.timeIntervalSince(session.createdAt)

        if diff < 60 { return L10n.Time.justNow }
        if diff < 3600 { return String(format: L10n.Time.minutesAgo, Int(diff / 60)) }
        if diff < 86400 { return String(format: L10n.Time.hoursAgo, Int(diff / 3600)) }
        if diff < 604_800 { return String(format: L10n.Time.daysAgo, Int(diff / 86400)) }

        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: session.createdAt)
    }
}
