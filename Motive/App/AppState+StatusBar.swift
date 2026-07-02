//
//  AppState+StatusBar.swift
//  Motive
//
//  Created by geezerrrr on 2026/1/19.
//

import AppKit

extension AppState: StatusBarControllerDelegate {
    func statusBarDidRequestSettings() {
        SettingsWindowController.shared.show()
    }

    func statusBarDidRequestQuit() {
        NSApp.terminate(nil)
    }

    func statusBarDidRequestToggleDrawer() {
        toggleDrawer()
    }

    func statusBarDidRequestCommandBar() {
        showCommandBar()
    }

    func statusBarMenu() -> NSMenu {
        let menu = NSMenu()
        let running = getRunningSessions()

        let commandItem = NSMenuItem(title: L10n.StatusBar.commandBar, action: #selector(StatusBarMenuTarget.openCommandBar), keyEquivalent: "")
        commandItem.target = StatusBarMenuTarget.shared
        commandItem.representedObject = self
        let parsed = HotkeyParser.parseToMenuShortcut(configManager.hotkey)
        commandItem.keyEquivalent = parsed.keyEquivalent
        commandItem.keyEquivalentModifierMask = parsed.modifiers
        commandItem.image = NSImage(systemSymbolName: "command", accessibilityDescription: nil)
        menu.addItem(commandItem)

        let settingsItem = NSMenuItem(title: L10n.StatusBar.settings, action: #selector(StatusBarMenuTarget.openSettings), keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = .command
        settingsItem.target = StatusBarMenuTarget.shared
        settingsItem.representedObject = self
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(settingsItem)

        if !running.isEmpty {
            menu.addItem(.separator())
            let headerItem = NSMenuItem(title: "Running tasks (\(running.count))", action: nil, keyEquivalent: "")
            headerItem.isEnabled = false
            menu.addItem(headerItem)
            for session in running.prefix(8) {
                let title = String(session.intent.prefix(40)) + (session.intent.count > 40 ? "…" : "")
                let item = NSMenuItem(title: title, action: #selector(StatusBarMenuTarget.switchToSessionAndOpenDrawer), keyEquivalent: "")
                item.target = StatusBarMenuTarget.shared
                item.representedObject = StatusBarMenuTarget.SwitchContext(appState: self, session: session)
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: L10n.StatusBar.quit, action: #selector(StatusBarMenuTarget.quitApp), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = .command
        quitItem.target = StatusBarMenuTarget.shared
        quitItem.representedObject = self
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(quitItem)

        return menu
    }
}

/// Target for status bar menu items (NSMenuItem needs objc-compatible target)
@objc private final class StatusBarMenuTarget: NSObject {
    static let shared = StatusBarMenuTarget()

    struct SwitchContext {
        let appState: AppState
        let session: Session
    }

    @objc func openCommandBar(_ sender: NSMenuItem) {
        (sender.representedObject as? AppState)?.showCommandBar()
    }

    @objc func openSettings(_ sender: NSMenuItem) {
        (sender.representedObject as? AppState)?.statusBarDidRequestSettings()
    }

    @objc func quitApp(_ sender: NSMenuItem) {
        (sender.representedObject as? AppState)?.statusBarDidRequestQuit()
    }

    @objc func switchToSessionAndOpenDrawer(_ sender: NSMenuItem) {
        guard let ctx = sender.representedObject as? SwitchContext else { return }
        ctx.appState.switchToSession(ctx.session)
        ctx.appState.showDrawer()
    }
}
