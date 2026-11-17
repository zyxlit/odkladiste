import AppKit
import ServiceManagement
import SwiftUI
import OdkladisteCore

enum AppearanceMode: String, CaseIterable {
    case system
    case light
    case dark

    @MainActor
    func title(l10n: L10n) -> String {
        switch self {
        case .system: return l10n.t("Systémový", "System")
        case .light: return l10n.t("Světlý", "Light")
        case .dark: return l10n.t("Tmavý", "Dark")
        }
    }

    @MainActor
    func apply() {
        switch self {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

struct SettingsView: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage("odkladiste.allSpaces") private var allSpaces = true
    @AppStorage("odkladiste.defaultAlwaysOnTop") private var defaultAlwaysOnTop = true
    @AppStorage("odkladiste.appearance") private var appearanceRaw = AppearanceMode.system.rawValue
    @AppStorage("odkladiste.thumbnailSize") private var thumbnailSizeRaw = ThumbnailSizeOption.medium.rawValue
    @AppStorage("odkladiste.defaultDisplayMode") private var defaultDisplayModeRaw = DisplayMode.grid.rawValue

    @ViewState private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @ViewState private var launchAtLoginError: String?
    @ViewState private var cacheClearedNotice = false

    let hotkeyStatusSummary: [(label: String, shortcut: String, isRegistered: Bool)]
    let onAllSpacesChanged: (Bool) -> Void

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label(l10n.t("Obecné", "General"), systemImage: "gearshape")
                }

            appearanceTab
                .tabItem {
                    Label(l10n.t("Vzhled", "Appearance"), systemImage: "paintbrush")
                }

            shortcutsTab
                .tabItem {
                    Label(l10n.t("Zkratky", "Shortcuts"), systemImage: "keyboard")
                }
        }
        .padding(16)
        .frame(width: 440, height: 300)
    }

    private var generalTab: some View {
        Form {
            Picker(l10n.t("Jazyk", "Language"), selection: $l10n.language) {
                ForEach(AppLanguage.allCases, id: \.self) { lang in
                    Text(l10n.languageOptionTitle(lang)).tag(lang)
                }
            }

            Toggle(l10n.t("Spustit po přihlášení", "Launch at Login"), isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    updateLaunchAtLogin(enabled)
                }

            if let launchAtLoginError {
                Text(launchAtLoginError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Toggle(l10n.t("Zobrazovat poličky na všech plochách", "Show shelves on all Spaces"), isOn: $allSpaces)
                .onChange(of: allSpaces) { _, value in
                    onAllSpacesChanged(value)
                }

            Toggle(l10n.t("Nové poličky otevírat vždy navrchu", "Keep new shelves always on top"), isOn: $defaultAlwaysOnTop)

            Section {
                Link(destination: URL(string: "https://buymeacoffee.com/cameklibor")!) {
                    Label(l10n.t("Podpořit vývoj (Buy Me a Coffee)", "Support Development (Buy Me a Coffee)"), systemImage: "cup.and.saucer")
                }
            }
        }
        .formStyle(.grouped)
    }

    private var appearanceTab: some View {
        Form {
            Picker(l10n.t("Vzhled", "Appearance"), selection: $appearanceRaw) {
                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                    Text(mode.title(l10n: l10n)).tag(mode.rawValue)
                }
            }
            .onChange(of: appearanceRaw) { _, raw in
                AppearanceMode(rawValue: raw)?.apply()
            }

            Picker(l10n.t("Velikost náhledů", "Thumbnail Size"), selection: $thumbnailSizeRaw) {
                ForEach(ThumbnailSizeOption.allCases, id: \.self) { size in
                    Text(size.localizedTitle(l10n: l10n)).tag(size.rawValue)
                }
            }

            Picker(l10n.t("Výchozí zobrazení", "Default View"), selection: $defaultDisplayModeRaw) {
                Text(l10n.t("Mřížka", "Grid")).tag(DisplayMode.grid.rawValue)
                Text(l10n.t("Seznam", "List")).tag(DisplayMode.list.rawValue)
            }

            HStack {
                Button(l10n.t("Vymazat cache náhledů", "Clear Thumbnail Cache")) {
                    ThumbnailService.shared.clearCache()
                    cacheClearedNotice = true
                }
                if cacheClearedNotice {
                    Text(l10n.t("Vymazáno", "Cleared"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var shortcutsTab: some View {
        Form {
            Section(l10n.t("Globální klávesové zkratky", "Global Keyboard Shortcuts")) {
                ForEach(hotkeyStatusSummary, id: \.label) { entry in
                    HStack {
                        Text(entry.label)
                        Spacer()
                        Text(entry.shortcut)
                            .font(.system(.body, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                        Image(systemName: entry.isRegistered ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(entry.isRegistered ? .green : .orange)
                            .help(entry.isRegistered ? l10n.t("Aktivní", "Active") : l10n.t("Zkratka je obsazena jinou aplikací", "Shortcut is used by another app"))
                    }
                }
            }

            Text(l10n.t("Globální zkratky využívají systémovou registraci bez sledování kláves.", "Global shortcuts use system registration without keylogging."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            launchAtLoginError = l10n.t(
                "Změna vyžaduje schválení v Nastavení systému → Položky přihlášení.",
                "Change requires approval in System Settings → Login Items."
            )
        }
    }
}
