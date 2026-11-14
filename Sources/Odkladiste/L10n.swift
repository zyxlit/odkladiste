import Foundation
import SwiftUI
import OdkladisteCore

enum AppLanguage: String, CaseIterable {
    case system
    case cs
    case en

    var resolvedIsCzech: Bool {
        switch self {
        case .cs:
            return true
        case .en:
            return false
        case .system:
            return Locale.preferredLanguages.first?.lowercased().hasPrefix("cs") ?? true
        }
    }
}

/// Runtime localization helper supporting instant CS/EN switching without requiring app restart.
@MainActor
final class L10n: ObservableObject {
    static let shared = L10n()

    private static let storageKey = "odkladiste.language"

    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Self.storageKey)
        }
    }

    var isCzech: Bool {
        language.resolvedIsCzech
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.storageKey) ?? AppLanguage.system.rawValue
        self.language = AppLanguage(rawValue: raw) ?? .system
    }

    func t(_ cs: String, _ en: String) -> String {
        isCzech ? cs : en
    }

    func colorName(_ color: ShelfColor) -> String {
        switch color {
        case .blue: return t("Modrá", "Blue")
        case .purple: return t("Fialová", "Purple")
        case .pink: return t("Růžová", "Pink")
        case .orange: return t("Oranžová", "Orange")
        case .green: return t("Zelená", "Green")
        case .graphite: return t("Grafitová", "Graphite")
        }
    }

    func languageOptionTitle(_ option: AppLanguage) -> String {
        switch option {
        case .system: return t("Systémový", "System")
        case .cs: return "Čeština"
        case .en: return "English"
        }
    }
}
