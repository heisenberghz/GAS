//
//  ConfigManager+Localization.swift
//  Motive
//
//  Created by geezerrrr on 2026/1/19.
//

import Foundation

extension ConfigManager {
    enum Language: String, CaseIterable, Identifiable {
        case system
        case english = "en"
        case chinese = "zh-Hans"
        case japanese = "ja"

        var id: String {
            rawValue
        }

        var displayName: String {
            switch self {
            case .system: "System"
            case .english: "English"
            case .chinese: "简体中文"
            case .japanese: "日本語"
            }
        }

        var localizedName: String {
            switch self {
            case .system: L10n.Settings.languageSystem
            case .english: L10n.Settings.languageEnglish
            case .chinese: L10n.Settings.languageChinese
            case .japanese: L10n.Settings.languageJapanese
            }
        }
    }

    var language: Language {
        get { Language(rawValue: languageRawValue) ?? .system }
        set {
            languageRawValue = newValue.rawValue
            applyLanguage(newValue)
        }
    }

    private func applyLanguage(_ language: Language) {
        if language == .system {
            // Remove override, use system language
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            // Set specific language
            UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
        }
        UserDefaults.standard.synchronize()

        // Notify user that restart is needed
        NotificationCenter.default.post(name: .languageDidChange, object: nil)
    }
}
