//
//  CommandBarSupport.swift
//  Motive
//
//  Created by geezerrrr on 2026/1/19.
//

import Foundation

extension AppState.MenuBarState {
    var displayText: String {
        switch self {
        case .idle: L10n.CommandBar.ready
        case .reasoning: L10n.StatusBar.reasoning
        case .executing: L10n.StatusBar.executing
        case .responding: L10n.StatusBar.executing
        }
    }
}
