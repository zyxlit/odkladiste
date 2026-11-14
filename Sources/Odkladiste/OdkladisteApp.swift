import AppKit
import SwiftUI
import Combine
import OdkladisteCore

@main
@MainActor
final class OdkladisteAppDelegate: NSObject, NSApplicationDelegate {
    private var store: ShelfStore!
    private var controllers: [UUID: ShelfPanelController] = [:]
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var settingsWindow: NSWindow?
    private var aboutWindow: NSWindow?
    private var hotkeyService: HotkeyService?
    private var cancellables = Set<AnyCancellable>()
    private var hiddenSetForToggle: [UUID] = []

    static func main() {
        let app = NSApplication.shared
        let delegate = OdkladisteAppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = ShelfStore()

        if let raw = UserDefaults.standard.string(forKey: "odkladiste.appearance") {
            AppearanceMode(rawValue: raw)?.apply()
        }

        setupMenuBar()
        syncPanels()

        hotkeyService = HotkeyService { [weak self] action in
            guard let self else { return }
            switch action {
            case .newShelf:
                self.createNewShelfAction()
            case .toggleAllShelves:
                self.toggleAllShelvesAction()
            }
        }

        store.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncPanels()
            }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyService?.invalidate()
        store.flushPersistence()
    }

    // MARK: - Panel Coordination

    private func syncPanels() {
        let shelves = store.state.shelves
        let activeIDs = Set(shelves.map(\.id))

        for id in Array(controllers.keys) where !activeIDs.contains(id) {
            controllers[id]?.hide()
            controllers.removeValue(forKey: id)
        }

        for (index, shelf) in shelves.enumerated() {
            if let existing = controllers[shelf.id] {
                existing.sync(with: shelf)
            } else {
                var initialShelf = shelf
                if initialShelf.windowPlacement == nil, let screen = NSScreen.main ?? NSScreen.screens.first {
                    let offset = CGFloat(index) * 36
                    let base = DisplayPlacement.resolveFrame(for: nil, screens: ShelfPanelController.currentScreenDescriptors())
                    let shifted = CGRect(
                        x: base.origin.x + offset - 160,
                        y: base.origin.y - offset + 40,
                        width: base.width,
                        height: base.height
                    )
                    let clamped = DisplayPlacement.clamp(shifted, into: screen.visibleFrame)
                    let placement = OdkladisteCore.WindowPlacement(
                        displayUUID: ShelfPanelController.displayUUID(for: screen),
                        rect: clamped
                    )
                    store.updatePlacement(for: shelf.id, placement: placement)
                    initialShelf.windowPlacement = placement
                }

                let controller = ShelfPanelController(shelf: initialShelf, store: store)
                controllers[shelf.id] = controller
                if initialShelf.isVisible {
                    controller.show()
                }
            }
        }
    }

    @objc private func handleScreenParametersChanged() {
        for controller in controllers.values {
            controller.ensureVisibleOnScreen()
        }
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "tray.2", accessibilityDescription: "Odkladiště")
            button.image?.isTemplate = true
            button.action = #selector(togglePopoverAction(_:))
            button.target = self
        }
        self.statusItem = item

        let pop = NSPopover()
        pop.behavior = .transient
        pop.animates = true
        let hostingController = NSHostingController(
            rootView: MenuBarPopoverView(
                store: store,
                onNewShelf: { [weak self] in
                    self?.createNewShelfAction()
                },
                onSelectShelf: { [weak self] shelfID in
                    self?.store.setShelfVisible(id: shelfID, isVisible: true)
                    self?.controllers[shelfID]?.show()
                },
                onToggleShelfVisibility: { [weak self] shelfID in
                    guard let self, let shelf = self.store.shelf(id: shelfID) else { return }
                    let nextVisible = !shelf.isVisible
                    self.store.setShelfVisible(id: shelfID, isVisible: nextVisible)
                    if nextVisible {
                        self.controllers[shelfID]?.show()
                    } else {
                        self.controllers[shelfID]?.hide()
                    }
                },
                onToggleAllShelves: { [weak self] in
                    self?.toggleAllShelvesAction()
                },
                onSettings: { [weak self] in
                    self?.popover?.performClose(nil)
                    self?.openSettingsAction()
                },
                onAbout: { [weak self] in
                    self?.popover?.performClose(nil)
                    self?.aboutAction()
                },
                onQuit: { [weak self] in
                    self?.popover?.performClose(nil)
                    self?.quitAction()
                }
            )
        )
        hostingController.sizingOptions = [.preferredContentSize]
        pop.contentViewController = hostingController
        self.popover = pop
    }

    @objc private func togglePopoverAction(_ sender: AnyObject?) {
        guard let button = statusItem?.button, let popover else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    @objc private func createNewShelfAction() {
        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first

        var placement: OdkladisteCore.WindowPlacement?
        if let targetScreen {
            let rect = DisplayPlacement.frameNearCursor(mouseLocation, in: targetScreen.visibleFrame)
            placement = OdkladisteCore.WindowPlacement(displayUUID: ShelfPanelController.displayUUID(for: targetScreen), rect: rect)
        }

        let shelf = store.createShelf(placement: placement)
        controllers[shelf.id]?.show()
    }

    @objc private func toggleAllShelvesAction() {
        let shelves = store.state.shelves
        let visible = shelves.filter(\.isVisible)
        if !visible.isEmpty {
            hiddenSetForToggle = visible.map(\.id)
            for shelf in visible {
                store.setShelfVisible(id: shelf.id, isVisible: false)
            }
        } else {
            let idsToShow = hiddenSetForToggle.isEmpty ? shelves.map(\.id) : hiddenSetForToggle
            for id in idsToShow {
                store.setShelfVisible(id: id, isVisible: true)
                controllers[id]?.show()
            }
        }
    }

    private func openSettingsAction() {
        NSApp.activate(ignoringOtherApps: true)
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            return
        }

        let l10n = L10n.shared
        let summary: [(label: String, shortcut: String, isRegistered: Bool)] = [
            (l10n.t("Nová polička", "New Shelf"), "⌃⌥N", hotkeyService?.registrationStatus[.newShelf] ?? false),
            (l10n.t("Zobrazit / skrýt všechny", "Show / Hide All"), "⌃⌥O", hotkeyService?.registrationStatus[.toggleAllShelves] ?? false)
        ]

        let view = SettingsView(hotkeyStatusSummary: summary) { [weak self] allSpaces in
            guard let self else { return }
            for controller in self.controllers.values {
                controller.updateAllSpaces(allSpaces)
            }
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = l10n.t("Nastavení — Odkladiště", "Settings — Odkladiště")
        window.isReleasedWhenClosed = false
        window.center()
        window.contentViewController = NSHostingController(rootView: view)
        window.makeKeyAndOrderFront(nil)
        self.settingsWindow = window
    }

    @objc private func aboutAction() {
        NSApp.activate(ignoringOtherApps: true)
        if let aboutWindow {
            aboutWindow.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 310),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.shared.t("O aplikaci Odkladiště", "About Odkladiště")
        window.isReleasedWhenClosed = false
        window.center()
        window.contentViewController = NSHostingController(rootView: AboutView())
        window.makeKeyAndOrderFront(nil)
        self.aboutWindow = window
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }
}
